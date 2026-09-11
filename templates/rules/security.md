---
description: Secrets handling, secure storage, keystore and signing hygiene, network security, and what is safe to ship inside a Flutter binary.
globs: ["**/*.dart", "android/**", "ios/**", "**/*.gradle", "**/*.gradle.kts", "**/*.plist"]
alwaysApply: true
---

# Security

## The rule that matters most

**A Flutter app is a client. Anything inside it can be read by whoever installs
it.**

```bash
# Both of these are in the shipped binary and recoverable in minutes:
strings app-release.apk | grep -i "api_key"
# and, for a compiled Flutter app, the Dart snapshot is readable too
```

So:

```dart
// WRONG - in the repo, in the clone, in the APK, forever
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIs...';
const stripeSecret = 'sk_live_51H8xQ2eZvKYlo2C';
```

```dart
// RIGHT for public configuration (project URL, publishable key)
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// RIGHT for anything secret: it does not live in the app at all.
// Put it behind your backend and call the backend.
```

`--dart-define` and `--dart-define-from-file` keep values out of git. They do
**not** hide them from a user with a debugger. That is the correct behaviour for
a URL and an anon key, and the wrong behaviour for a service key.

### What is safe to embed

| Safe in the app | Never in the app |
|-----------------|------------------|
| backend URL | service-role / secret keys |
| anon / publishable key (protected by access rules) | database passwords |
| Firebase config values | private API keys |
| AdMob app and unit ids | signing keystores |
| analytics write key | OAuth client secrets |
| feature flags | anything that bypasses access rules |

The test: *if this leaked, would I lose money or user data?* If yes, backend.

## Secure storage

```dart
// WRONG - shared_preferences is plain text in a file the user can read
final prefs = await SharedPreferences.getInstance();
await prefs.setString('auth_token', token);
```

```dart
// RIGHT - Keychain on iOS, EncryptedSharedPreferences / Keystore on Android
final storage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);
await storage.write(key: 'auth_token', value: token);
```

- Tokens, refresh tokens, session ids, API keys the user supplies: secure storage.
- Preferences, theme choice, onboarding-seen flags: `shared_preferences` is fine.
- On Android, set `encryptedSharedPreferences: true`. The default is weaker.
- On iOS, choose the `KeychainAccessibility` deliberately. `first_unlock` lets
  background work read the token after a reboot; `unlocked` does not.
- Secure storage is **not** available on web. If you ship web, that data cannot be
  protected the same way — design for it rather than discovering it.

`flutter-doctor` check 19 will not catch a token in `shared_preferences`; that is
a test to write, not a lint to run.

## Signing material

```gitignore
# .gitignore - all of these, always
android/key.properties
*.keystore
*.jks
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
.env*
!.env.example
```

```properties
# android/key.properties - read by build.gradle, never committed
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

- A committed `*.keystore` is a release-key compromise. Anyone with it and the
  password can sign an update to your app.
- Losing the upload key costs days with Play support. Losing the app-signing key
  can cost you the listing. Back both up offline, in two places.
- `google-services.json` is identifiers rather than a secret, but committing it
  is how a dev build ends up writing to the production Firebase project. Gitignore
  it and inject per flavor.

## Transport

- Android 9+ blocks cleartext HTTP by default. Do not "fix" that by enabling
  `usesCleartextTraffic` in release — that is how tokens end up on the wire in
  plain text on a coffee shop network.
- Certificate pinning (`dio` + a custom `HttpClientAdapter`) is worth it for
  finance and health apps. It also creates an operational burden: a missed
  certificate rotation bricks every installed copy. Decide deliberately.
- Validate deep link parameters before using them. A deep link is attacker
  controlled input that can reach a route directly, bypassing your UI.

## Access rules are the boundary

- Supabase: **row-level security on every table**, no exceptions. An anon key
  with RLS disabled is a public database.
- Firebase: security rules on Firestore and Storage. Default rules are
  test-mode-open and expire with an email nobody reads.
- Never trust a client-supplied `user_id`. Derive the user from the verified
  session on the server side.

## Logging

```dart
// WRONG - tokens in logcat, and in whatever aggregates logcat
debugPrint('auth response: $response');
```

```dart
// RIGHT - log the shape, not the payload
debugPrint('auth ok for user=${user.id} expiresIn=${session.expiresIn}');
```

Crash reporters ship logs off-device. Scrub before you log, not after.

## Dependencies

Every package runs with your app's permissions and ships inside your binary.

- Before adding one: check the publisher, the last publish date, and whether it is
  discontinued.
- `flutter pub outdated` and `flutter pub deps` are the cheap checks.
- `flutter-doctor` check 15 flags known-discontinued packages.
- Prefer a package with one job over a framework that does everything.

## Checklist before a release build

- [ ] No secrets in source — search for `key`, `secret`, `token`, `password`
- [ ] `key.properties`, `*.keystore`, `*.jks` gitignored **and** not tracked
      (`git ls-files | grep -E 'keystore|key.properties'` returns nothing)
- [ ] Tokens in secure storage, not `shared_preferences`
- [ ] RLS / security rules enabled and tested with a second account
- [ ] No `print()` of anything user-identifying
- [ ] Release build has no cleartext traffic exception
- [ ] Privacy policy matches what you actually collect

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| Service key in the app | someone finds it and reads every row |
| Token in `shared_preferences` | recoverable from a rooted device or a backup |
| `usesCleartextTraffic=true` | credentials in plain text on any network |
| RLS enabled but no policies | table silently returns zero rows, or everything |
| Trusting a client `user_id` | any user can read any other user's data |
| Logging a full auth response | live tokens in your crash reporter |
| Committing `google-services.json` | dev builds writing to production |
