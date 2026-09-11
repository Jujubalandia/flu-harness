---
description: Push and local notification rules for firebase_messaging plus flutter_local_notifications, covering permission, tokens, the three app states, the background isolate handler, Android channels, timezone-correct scheduling and tap routing. Load before editing notification code or the Android manifest entries that support it.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Notifications (firebase_messaging + flutter_local_notifications)

Target: `firebase_messaging` 16.x and `flutter_local_notifications` 22.x on Flutter 3.3x-3.47 / Dart 3.9-3.13. You normally need **both**: FCM delivers remote pushes, but a data-only message that arrives while the app is backgrounded or terminated displays nothing on its own, so the official pattern renders it with `flutter_local_notifications`.

`[VERSION]` `flutter_local_notifications` 20.0.0 converted every positional parameter on `initialize`, `show`, `zonedSchedule` and `cancel` to named parameters, and 21.0.0 raised the floor to Flutter 3.38.1 / Dart 3.10, Android minSdk 24, iOS 13. Tutorials written before 2026 will not compile.

## 1. Boot order in main()

Firebase must be initialised before any messaging call, and the background handler must be registered before `runApp`, exactly once per launch.
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // BEFORE runApp: a message arriving during startup needs a handler.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initLocalNotifications();
  runApp(const ProviderScope(child: App()));
}
```
```dart
// WRONG - registered after runApp: startup messages are dropped, and the
// second registration of the same handler throws
void main() { runApp(const App()); FirebaseMessaging.onBackgroundMessage(h); }
```
## 2. Permission: iOS prompts, Android does not

`FirebaseMessaging.instance.requestPermission()` shows a dialog on iOS and macOS. On Android it only **reports** status: the plugin returns a `NotificationSettings` whose `authorizationStatus` mirrors the system setting and never prompts. Calling it and assuming you asked is the most common push bug.
```dart
// iOS / macOS
final settings = await FirebaseMessaging.instance.requestPermission(
  alert: true, badge: true, sound: true,
); // AuthorizationStatus.denied -> do not nag, offer a settings button.

// Android 13+ (API 33): request POST_NOTIFICATIONS yourself.
final android = FlutterLocalNotificationsPlugin()
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
final bool? granted = await android?.requestNotificationsPermission();
```
`<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` is merged into your manifest by the messaging plugin, but declare it explicitly in `android/app/src/main/AndroidManifest.xml` so a future plugin change cannot silently remove your only path to that permission. Ask at a moment that makes sense (after onboarding, when the user enables a reminder) and re-check on resume, because the user can revoke it in system settings at any time.

## 3. Tokens: send on every launch, re-send on refresh, delete on logout

```dart
StreamSubscription<String>? _tokenSub;

Future<void> startDeviceRegistration() async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await api.registerDeviceToken(token); // token -> user id, server side
  _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen(api.registerDeviceToken);
}

Future<void> onSignedOut() async {
  await _tokenSub?.cancel();
  await api.unregisterDeviceToken();              // server: detach from the user
  await FirebaseMessaging.instance.deleteToken(); // client: fresh anonymous token
}
```
```dart
// WRONG - the token is read once at first launch and never again
final token = await FirebaseMessaging.instance.getToken();
await api.save(token!);
```
Tokens rotate on reinstall, restore-from-backup, app-data clear and, on iOS, at the platform's discretion. Without `onTokenRefresh` those users silently stop receiving pushes. Without `deleteToken()` on logout a shared device keeps delivering the previous user's notifications, which is a privacy incident rather than a bug report.

## 4. The three app states, and which callback fires

| App state | Message arrives | User taps |
|-----------|-----------------|-----------|
| Foreground | `FirebaseMessaging.onMessage` | n/a, the app is already open |
| Background (process alive) | `onBackgroundMessage` for data-only; a `notification` block is drawn by the OS and your Dart never runs | `FirebaseMessaging.onMessageOpenedApp` |
| Terminated | `onBackgroundMessage` for data-only | `FirebaseMessaging.getInitialMessage()` |
```dart
FirebaseMessaging.onMessage.listen((msg) {
  // Foreground: the OS shows nothing. Render it yourself or drop it.
  LocalNotifications.show(msg);
});

FirebaseMessaging.onMessageOpenedApp.listen((msg) {
  router.go(routeFor(msg.data)); // background -> foreground via a tap
});

// Terminated -> tap. Returns the message ONCE, and only for that cold start.
final initial = await FirebaseMessaging.instance.getInitialMessage();
if (initial != null) pendingRoute.value = routeFor(initial.data);
```
`onMessage` and `onMessageOpenedApp` are **static** streams on `FirebaseMessaging`, not instance members. `getInitialMessage()` returns `Future<RemoteMessage?>` and is null for any launch that a notification did not start, so call it once during startup and stash the result.

## 5. The background handler must be top-level and annotated

```dart
// WRONG - a closure throws ArgumentError ("must be a top-level function"),
// and an unannotated function is tree-shaken out of release builds
FirebaseMessaging.onBackgroundMessage((message) async => await doSomething(message));
```
```dart
// RIGHT - top-level, annotated, self-sufficient
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Separate isolate: no providers, no singletons, no BuildContext, no shared
  // in-memory state. Re-create everything this function needs.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initLocalNotifications();
  await showLocalNotification(message);
}
```
`@pragma('vm:entry-point')` is what stops the Dart compiler from tree-shaking the function. Forget it and **the handler works in debug and silently never runs in release** - the classic "background notifications work on my machine" bug. Debug keeps everything reachable; AOT release builds do not.

Because the handler owns its isolate, results travel by persistence: write to storage and read that state on the next foreground. A `notification` block in the payload is displayed by the OS while backgrounded and never runs your Dart code; only data-only messages reach the handler. If you want custom rendering, omit the `notification` block and build it yourself.

## 6. Local notifications: initialise per platform, create the Android channel

```dart
final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'high_importance_channel',   // id: must match the manifest meta-data below
  'High importance notifications',
  description: 'Account and reminder alerts.',
  importance: Importance.high,
);

Future<void> initLocalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwin = DarwinInitializationSettings();
  await _plugin.initialize(
    settings: const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
    onDidReceiveNotificationResponse: _onLocalTap,
  );
  // Android 8.0 (API 26)+: no channel means it is dropped, silently.
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
}
```
`initialize` takes the settings as the **named** `settings:` parameter in 20.0.0+, and `InitializationSettings` takes `android`, `iOS`, `macOS`, `linux`, `windows` and `web` by name. `DarwinInitializationSettings` covers iOS and macOS.

Android renders the small notification icon as a **silhouette**: only the alpha channel survives, so a colour launcher icon appears as a white blob. Ship a white-on-transparent PNG and point the manifest at it and at the channel:
```xml
<meta-data android:name="com.google.firebase.messaging.default_notification_icon"
           android:resource="@drawable/ic_notification" />
<meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"
           android:value="high_importance_channel" />
```
That value must be the id of a channel you actually created, or FCM falls back to a low-importance default with no heads-up banner.

## 7. Scheduling: set the timezone before you schedule

`zonedSchedule` takes a `TZDateTime`, so the timezone database must be loaded and the local location set first.
```dart
tz.initializeTimeZones();
final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone(); // flutter_timezone 4+
tz.setLocalLocation(tz.getLocation(zone.identifier));

await _plugin.zonedSchedule(
  id: reminderId,
  title: 'Time for your session',
  body: 'Ten minutes, that is all.',
  scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(hours: 8)),
  notificationDetails: const NotificationDetails(
    android: AndroidNotificationDetails(
        'high_importance_channel', 'High importance notifications',
        importance: Importance.high),
    iOS: DarwinNotificationDetails(),
  ),
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // required
  payload: 'session-reminder',
);
```
```dart
// WRONG - DateTime is timezone-naive: the reminder drifts across DST and
// fires at the wrong wall-clock time for travellers
scheduledDate: DateTime.now().add(const Duration(hours: 8)),
```
`[VERSION]` `androidScheduleMode` is a required named parameter and `uiLocalNotificationDateInterpretation` no longer exists. Valid values are `alarmClock`, `exact`, `exactAllowWhileIdle`, `inexact` and `inexactAllowWhileIdle`. Exact modes need the exact-alarm permission on Android 12+; if the app does not need precision, `inexactAllowWhileIdle` avoids the permission prompt entirely. When the permission is missing and you asked for exact timing, the plugin logs and the notification is never scheduled - recurring ones included. `matchDateTimeComponents` turns a one-off into a daily or weekly repeat. On Linux `zonedSchedule` throws `UnimplementedError`; only Windows and the mobile platforms implement it.

## 8. Route taps through the router, after it is mounted

The tap callback can fire before the first frame, so never call `router.go` from it directly.
```dart
void _onLocalTap(NotificationResponse response) {
  pendingRoute.value = response.payload;   // buffer, do not navigate
}

// After the router exists (first post-frame, or when auth settles):
WidgetsBinding.instance.addPostFrameCallback((_) {
  final route = pendingRoute.value;
  if (route == null) return;
  pendingRoute.value = null;   // consume exactly once
  router.go(route);
});
```
`onDidReceiveNotificationResponse` carries the `payload` string passed to `show`/`zonedSchedule`. `getNotificationAppLaunchDetails()` is the local-notification equivalent of `getInitialMessage()` and tells you whether a tap launched the app. Keep one `pendingRoute` slot shared by both FCM and local taps so a cold start cannot route twice.

## 9. iOS setup beyond the Dart code

- Upload an **APNs authentication key (.p8)** to Firebase (Project settings > Cloud Messaging). Without it, iOS receives nothing while Android works fine.
- In Xcode enable the **Push Notifications** capability and **Background Modes > Remote notifications**, and add `remote-notification` to `UIBackgroundModes` in `Info.plist`.
- Foreground pushes are swallowed unless you opt in: `await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);`
- iOS throttles aggressively. If messages "stopped arriving", check throttling before rewriting the integration.

## 10. Common mistakes

| Mistake | Symptom |
|---------|---------|
| Missing `@pragma('vm:entry-point')` | handler runs in debug, silent in release |
| Handler registered after `runApp` | early messages lost; a second registration throws |
| Handler is a closure or instance method | `ArgumentError: must be a top-level function` |
| No `POST_NOTIFICATIONS` request on Android 13+ | notifications never delivered, no error |
| No notification channel on Android 8+ | nothing appears, nothing logged |
| `default_notification_channel_id` not matching a real channel | no heads-up banner |
| No `deleteToken()` on logout | previous user's notifications on a shared device |
| `DateTime` instead of `tz.TZDateTime` when scheduling | reminders shift by an hour at DST |
| `getInitialMessage()` ignored | cold-start tap opens the app but not the content |
| Missing APNs key in Firebase | Android works, iOS receives nothing |
