---
description: RevenueCat (purchases_flutter) integration rules covering one-time configuration, user identity, entitlement state, offerings, purchase and restore flows, error classification and paywall gating. Load before editing billing, paywall or entitlement code.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# RevenueCat (purchases_flutter)

Target: `purchases_flutter` 10.x on Flutter 3.3x-3.47 / Dart 3.9-3.13. Facts that changed across majors are flagged `[VERSION]`; check the installed release (`flutter pub deps --style=compact | grep purchases_flutter`) before trusting a sample copied from a tutorial.

## 1. Configure exactly once, in main()

`Purchases.configure` is process-global. Call it in `main()` before `runApp`, after `WidgetsFlutterBinding.ensureInitialized()`. Never in a widget, a provider body, a lazy service locator, or anything hot reload can re-run.
```dart
// WRONG - re-initialises the SDK on every screen entry; identity and cached
// CustomerInfo are discarded mid-session
@override
void initState() {
  super.initState();
  Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey));
}

// RIGHT - one call, one place, before the first frame
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug); // debug only
  await Purchases.configure(PurchasesConfiguration(kRevenueCatApiKey));
  runApp(const ProviderScope(child: App()));
}
```

`configure` takes `PurchasesConfiguration` positionally, which takes the API key positionally. The key is per-platform and comes from `--dart-define`, never source. `flutter run --dart-define=RC_APPLE_KEY=appl_xxx --dart-define=RC_GOOGLE_KEY=goog_xxx`:
```dart
// lib/core/config/env.dart - `const` is required: fromEnvironment is compile-time.
// defaultTargetPlatform is web-safe, unlike dart:io Platform.
const String kRevenueCatAppleKey = String.fromEnvironment('RC_APPLE_KEY');
const String kRevenueCatGoogleKey = String.fromEnvironment('RC_GOOGLE_KEY');
const bool kIsApple = defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;
const String kRevenueCatApiKey = kIsApple ? kRevenueCatAppleKey : kRevenueCatGoogleKey;
```

A missing define yields `''` and surfaces later as `configurationError`, so assert it: `assert(kRevenueCatApiKey.isNotEmpty, 'pass --dart-define=RC_APPLE_KEY/RC_GOOGLE_KEY');`

## 2. Identity: logIn after auth, logOut on sign-out

`Purchases.logIn(appUserId)` links the store receipt to your user. Await it **before any entitlement check**: the anonymous-to-identified transition can merge the anonymous customer's purchases into the identified one, and that merge is not instant. Read entitlements first and you read the pre-merge, empty state - a paying user is shown the paywall, sometimes permanently.
```dart
// WRONG - still anonymous when the entitlements are read
unawaited(Purchases.logIn(user.id));
final info = await Purchases.getCustomerInfo();

// RIGHT - use the CustomerInfo that logIn itself returns
final LogInResult result = await Purchases.logIn(user.id);
isPro.value = result.customerInfo.entitlements.active.containsKey('pro');
// result.created == true means a brand new RevenueCat customer was created

// RIGHT - sign-out, guarded: logOut() throws while already anonymous
if (!await Purchases.isAnonymous) await Purchases.logOut();
```

`Purchases.appUserID`, `.isAnonymous` and `.isConfigured` are `Future` getters and need `await`. `logOut()` returns the new anonymous `CustomerInfo` - read it rather than assuming the user now has nothing.

## 3. Derive entitlement state, never cache a bool

```dart
// WRONG - a bool in prefs outlives the subscription, survives a refund, and
// is trivially editable on a rooted device: prefs.getBool('is_pro') ?? false

// RIGHT - one pure function, recomputed from CustomerInfo
bool hasPro(CustomerInfo info) => info.entitlements.active.containsKey('pro');
```

Gate on the entitlement identifier, never on a product id (product ids change; entitlement ids are the stable contract) and never on `activeSubscriptions`. `entitlements.all` includes inactive entitlements; `entitlements.active` is the gate. `EntitlementInfo` carries `isActive`, `willRenew`, `expirationDate`, `billingIssueDetectedAt`, `unsubscribeDetectedAt`, `periodType`, `isSandbox`.

## 4. Drive the UI from the CustomerInfo stream, not a timer

The update listener fires on purchase, renewal, restore, expiry, billing issue and cross-device sync, and it fires **immediately with the last known CustomerInfo** when you register it, so there is no "first fetch" special case.
```dart
// RIGHT - registered once, removed with the same reference on dispose
late final CustomerInfoUpdateListener _onInfo = _handleInfo;
CustomerInfo? _info;

void _handleInfo(CustomerInfo info) => setState(() => _info = info);

@override
void initState() {
  super.initState();
  Purchases.addCustomerInfoUpdateListener(_onInfo); // fires immediately
}

@override
void dispose() {
  Purchases.removeCustomerInfoUpdateListener(_onInfo); // same tear-off
  super.dispose();
}

// WRONG - burns battery, still misses renewals, races the SDK cache
Timer.periodic(const Duration(seconds: 5), (_) async {
  final info = await Purchases.getCustomerInfo();
  setState(() => _isPro = info.entitlements.active.isNotEmpty);
});
```

`addCustomerInfoUpdateListener` returns `void`, not a subscription. A closure created inline in `initState` and re-created in `dispose` removes nothing and leaks a callback.

## 5. The paywall renders only after offerings load

`Offerings` is a network fetch with three outcomes. Model all three. Rendering with `offerings.current == null` shows blank prices or crashes on `availablePackages.first`; gating the app on `offerings != null` alone leaves a spinner forever when the fetch fails.

```dart
// RIGHT - loading / failed / ready; the store is the only source of prices
sealed class PaywallState { const PaywallState(); }
class PaywallLoading extends PaywallState { const PaywallLoading(); }
class PaywallFailed extends PaywallState { const PaywallFailed(this.message); final String message; }
class PaywallReady extends PaywallState { const PaywallReady(this.offering); final Offering offering; }

Future<PaywallState> loadPaywall() async {
  try {
    final current = (await Purchases.getOfferings()).current;
    if (current == null || current.availablePackages.isEmpty) {
      return const PaywallFailed('No current offering is configured.');
    }
    return PaywallReady(current);
  } on PlatformException catch (e) {
    return PaywallFailed(messageFor(PurchasesErrorHelper.getErrorCode(e)));
  }
}
```

Fetch offerings on paywall entry rather than caching for the session: prices are A/B tested and localized per user. `offerings.current` is the dashboard's current offering; `offerings.getOffering(id)` targets one by id. Never hardcode a price - read `package.storeProduct.priceString` and `.currencyCode`.

## 6. Purchasing

```dart
Future<void> buy(Package package) async {
  setState(() => _busy = true);           // disable the button: two taps are
  try {                                   // two transactions, the second a refund
    final result = await Purchases.purchasePackage(package);
    applyEntitlements(result.customerInfo); // result.storeTransaction has the order
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code != PurchasesErrorCode.purchaseCancelledError) showPurchaseFailed(messageFor(code));
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

`[VERSION]` In 9.0.0 `purchasePackage` changed from returning `CustomerInfo` to returning `PurchaseResult` (`.customerInfo` + `.storeTransaction`). Recent 10.x deprecates it in favour of `Purchases.purchase(PurchaseParams(...))`; both work, but do not mix the two styles in one codebase.

## 7. A user cancel is not an error

```dart
// RIGHT - classify the code, then decide whether the user sees anything at all
String messageFor(PurchasesErrorCode code) => switch (code) {
      PurchasesErrorCode.purchaseCancelledError => '', // silent
      PurchasesErrorCode.paymentPendingError =>
        'Your payment is pending approval. Access unlocks automatically.',
      PurchasesErrorCode.networkError || PurchasesErrorCode.storeProblemError =>
        'The store could not be reached. Try again.',
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        'That plan is not available in your store region.',
      _ => 'Something went wrong. Please try again.',
    };

// WRONG - the user tapped Cancel and gets a "Purchase failed" dialog.
// This is the most common RevenueCat bug in shipped apps.
on PlatformException catch (e) {
  showDialog(/* 'Purchase failed: ${e.message}' */);
}
```

`PurchasesErrorHelper.getErrorCode(PlatformException)` returns a `PurchasesErrorCode` and falls back to `unknownError` outside the enum range - log `e.message` for that case so you can add a branch later. `paymentPendingError` means the transaction is real but unsettled: show no failure, grant nothing yet, and expect the CustomerInfo listener to fire when it settles. Route `purchasePackage`, `restorePurchases` and `getOfferings` through one error mapper so the copy cannot drift.

## 8. Restore Purchases is mandatory

App Store Review Guideline 3.1.1 requires a restore mechanism on any screen that sells a non-consumable or subscription, and Play reviewers look for it too. It must be a visible button on the paywall, not a hidden link in Settings.

```dart
Future<void> restore() async {
  // Same _busy / mounted guard as buy(): a restore is a network round trip.
  try {
    final info = await Purchases.restorePurchases();
    // "nothing to restore" and "restore failed" are different outcomes and
    // need different copy; a silent no-op restore is a support ticket.
    info.entitlements.active.containsKey('pro') ? goToApp() : showNoPurchasesFound();
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code != PurchasesErrorCode.purchaseCancelledError) showRestoreFailed(messageFor(code));
  }
}
```
## 9. Anything that matters is verified server-side

- The client check is for UI; the server check is for money.
- Keep a RevenueCat webhook into your backend as the authority and store entitlements in your own table keyed by your user id; re-verify before serving paid content or paid APIs.
- `EntitlementInfo.verification` adds assurance but is not a substitute for a check you control. Assume the client can be patched: `const bool kIsPro = true` in a decompiled APK must unlock nothing that costs you money.

## 10. Testing, and why sandbox is not production

- iOS, StoreKit configuration file in the Xcode scheme: local purchase/restore/renewal loop, no Apple servers involved.
- iOS, sandbox account via TestFlight: real StoreKit, still not production.
- Android, Play Console license testers on the internal testing track: real Billing responses, 3-minute acknowledge window.
- Both: separate sandbox and production RevenueCat keys, so test traffic does not pollute real analytics.

Sandbox subscriptions renew on an accelerated clock, sandbox receipts are not production receipts, and StoreKit configuration files bypass the store entirely. Before shipping, exercise a real renewal, a real cancellation, a billing-issue state (declined card) and the store-account-signed-out path.

## 11. Common mistakes

| Mistake | Symptom |
|---------|---------|
| `configure` in a widget or called twice | identity resets, entitlements flicker, `configurationError` |
| Entitlement check before `logIn` resolves | paying user sees the paywall, sometimes permanently |
| Gating on a cached `isPro` bool | refunds and expiries never take effect |
| Paywall before `offerings.current` is non-null | blank prices, `null` crash on `availablePackages.first` |
| No Restore button | App Store rejection under 3.1.1 |
| Cancel treated as failure | "Purchase failed" after the user tapped Cancel |
| Trusting the client for access | free premium for anyone who patches the binary |
