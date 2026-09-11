---
description: Flutter test structure, fakes vs mocks, widget test idioms, golden tests and what is not worth testing. Applies to test files and to any widget that needs to be testable.
globs: ["test/**/*.dart", "integration_test/**/*.dart", "**/*_test.dart"]
alwaysApply: true
---

# Testing

The gate is `flutter test`. It runs on every push for `standard` and `strict`, and
skips itself when there is no `test/` directory — so the first test you write is
the one that turns the gate on.

## Layout

```
test/
  unit/                 # pure Dart, no widgets
    cart_total_test.dart
  widget/               # one widget, pumped in isolation
    paywall_screen_test.dart
  golden/               # pixel snapshots
    price_card_golden_test.dart
  helpers/
    pump_app.dart       # shared pumping helper
    fakes.dart          # in-memory implementations
integration_test/
  app_test.dart         # real app, real routing, real plugins
```

## Fakes before mocks

A hand-written fake is usually better than a generated mock: it holds state, so it
behaves like the real thing across a sequence of calls.

```dart
// test/helpers/fakes.dart
class FakeSubscriptionRepository implements SubscriptionRepository {
  FakeSubscriptionRepository({this.isPremium = false});
  bool isPremium;

  @override
  Future<bool> hasActiveSubscription() async => isPremium;

  @override
  Future<void> purchase(String productId) async => isPremium = true;
}
```

```dart
// then, in a test, the state is part of the fixture
final repo = FakeSubscriptionRepository(isPremium: true);
```

Reach for `mocktail` when you need to assert *how* something was called, or when
the interface is huge. Reach for a fake whenever you can — a fake that stores what
you put in it catches bugs a mock's `when(...)` will happily hide.

If you use `mockito`, remember it needs a `build_runner` pass
(`dart run build_runner build`) to generate the mocks, which adds a build step to
your test loop.

## Unit tests

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartTotal', () {
    test('sums line items', () {
      final cart = Cart(items: [
        const Item(price: 10.0, quantity: 2),
        const Item(price: 5.5, quantity: 1),
      ]);
      expect(cart.total, 25.5);
    });

    test('is zero when empty', () {
      expect(const Cart(items: []).total, 0.0);
    });

    test('rounds to two decimals', () {
      final cart = Cart(items: [const Item(price: 0.1, quantity: 3)]);
      expect(cart.total, closeTo(0.3, 1e-9));   // never compare doubles with ==
    });
  });
}
```

Use `closeTo` for floating point. `expect(0.1 * 3, 0.3)` fails, and the failure
message ("expected 0.3, got 0.30000000000000004") has wasted a lot of afternoons.

## Widget tests

```dart
testWidgets('shows the price and calls onPurchase', (tester) async {
  var purchased = false;

  await tester.pumpWidget(
    MaterialApp(
      home: PaywallScreen(
        priceLabel: r'$4.99',
        onPurchase: () => purchased = true,
      ),
    ),
  );

  expect(find.text(r'$4.99'), findsOneWidget);

  await tester.tap(find.byKey(const Key('purchase-button')));
  await tester.pump();                 // let the tap's callbacks run

  expect(purchased, isTrue);
});
```

Idioms that matter:

| Situation | Use |
|-----------|-----|
| after triggering async work, want the settled state | `await tester.pumpAndSettle()` |
| want to observe an intermediate frame | `await tester.pump()` |
| a repeating animation is on screen | `pump()` with a duration — `pumpAndSettle` hangs forever |
| find by test hook, not by copy | `find.byKey(const Key('purchase-button'))` |
| find by visible text | `find.text(l10n.purchaseAction)` |
| find by widget type | `find.byType(ElevatedButton)` — brittle, prefer a key |
| enter text | `await tester.enterText(find.byType(TextField), 'hello')` |

**Find by text from the localization bundle, not a hardcoded literal.** If you
write `find.text('Purchase')` and the app ships three languages, the test breaks
in two of them for no reason.

```dart
// pumping a widget that needs providers / localization
Future<void> pumpApp(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

## Golden tests

```dart
testWidgets('PriceCard golden', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: Center(child: PriceCard(price: r'$4.99'))),
    ),
  );
  await expectLater(
    find.byType(PriceCard),
    matchesGoldenFile('goldens/price_card.png'),
  );
});
```

```bash
flutter test --update-goldens     # regenerate, then LOOK at the diff before committing
```

Golden tests fail on a different font-rendering platform. Pin one platform for
goldens (CI), or they will fail on your laptop and pass in CI for no reason.
Regenerating goldens without looking at the image turns the test into a change
detector with no signal.

For golden tests that survive CI and local runs, the maintained helper is
`alchemist` (pre-1.0, but alive). The older `golden_toolkit` is unmaintained —
if a tutorial tells you to add it, it was written before 2024.

## Testing async state

```dart
test('emits loading then data', () {
  final container = ProviderContainer(overrides: [
    repoProvider.overrideWithValue(FakeRepo(delay: Duration.zero)),
  ]);
  addTearDown(container.dispose);

  expect(container.read(itemsProvider), const AsyncLoading<List<Item>>());
  await container.read(itemsProvider.future);
  expect(container.read(itemsProvider).hasValue, isTrue);
});
```

`addTearDown(container.dispose)` — without it the container leaks between tests
and you get failures that only appear when the full file runs.

## Integration tests

```dart
// integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('golden path 1: onboarding to main screen', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('get-started')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
```

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

Integration tests run against a real device or emulator, so they exercise the
plugin channels that widget tests stub out. They are slow — keep them to the
Golden Paths, not to everything.

## Fake time, not sleeps

```dart
// WRONG - slow, and flaky on a loaded CI box
await Future<void>.delayed(const Duration(seconds: 2));
```

```dart
// RIGHT for widgets
await tester.pump(const Duration(seconds: 2));

// RIGHT for unit tests that use timers
fakeAsync((async) {
  scheduleSomething();
  async.elapse(const Duration(seconds: 2));
  expect(done, isTrue);
});
```

Never `Future.delayed` in a test. It makes the suite slow and it fails on a busy
machine.

## What not to test

- Generated code (`*.g.dart`, `*.freezed.dart`) — the generator's job
- Third-party plugin internals
- Trivial getters and one-line `copyWith`s
- The theme, or `ThemeData` values
- Pixel positions outside golden tests

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| `pumpAndSettle` with an infinite animation | test hangs until the timeout |
| Missing `addTearDown(container.dispose)` | passes alone, fails in the full file |
| `find.text('literal')` in a localized app | passes in English, fails in Portuguese |
| Comparing doubles with `==` | "expected 0.3, got 0.30000000000000004" |
| `Future.delayed` instead of `pump(duration)` | slow suite, flaky CI |
| Asserting on `MediaQuery.of(context)` metrics | breaks when the test surface size changes |
| Mocking the class under test | the test asserts the mock, not the code |
| Committing regenerated goldens unread | the test stops meaning anything |
