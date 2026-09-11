---
description: Firebase in Flutter - one-time Firebase.initializeApp, auth state streams, Firestore read cost and typed converters, server timestamps, snapshot listener cleanup, security rules and Cloud Functions.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Firebase / FlutterFire

Target: `firebase_core` 4.x, `firebase_auth` 6.x, `cloud_firestore` 6.x on Flutter stable / Dart 3.x
(iOS 15+, macOS 10.15+, Android API 23+). Pin every FlutterFire package to an exact version and
upgrade them all in one commit: the 2026 breakages were cross-package version mismatches, not
single-package bugs.

## Initialize once, in main()

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // MUST come first
  // DefaultFirebaseOptions is generated into lib/firebase_options.dart by
  // `flutterfire configure`.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App());
}
```

```dart
// WRONG: not awaited, runs before the binding is ready, or runs inside a widget
void main() {
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App()); // intermittent "No Firebase App '[DEFAULT]' has been created"
}
// RIGHT: awaited once in main(); later reads use FirebaseAuth.instance and
// FirebaseFirestore.instance, which need the default app to exist.
```


## Which config files are secrets, and which are not

- `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) hold project ids, app ids, API
  keys and bundle ids. They are **identifiers, not secrets**: they are compiled into your binary and
  shipped to every user regardless. Gitignore them anyway, not for secrecy but because they are
  environment-specific: committing the one that points at production is how a debug build starts
  writing to the live database, and nobody notices until it costs money or data.
- `lib/firebase_options.dart` carries the same identifiers. Because they are public, protect them:
  restrict the API keys in Google Cloud console and enable App Check, so a copied key cannot be used
  from a script.
- Flavors: one Firebase project and one options file per environment, selected at startup from
  `String.fromEnvironment('FLAVOR')` in a `switch` over the generated options classes.

## Auth state for routing

```dart
StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(),
  builder: (context, snapshot) => snapshot.hasData
      ? (snapshot.data == null ? const SignInScreen() : const HomeScreen())
      : const SplashScreen(), // first frame, before the cached user arrives
)
```

- `authStateChanges()` fires on sign-in, sign-up and sign-out. Use it for routing;
  `idTokenChanges()` additionally fires on token refresh (only needed for custom claims), and
  `userChanges()` on local profile mutations (`updateProfile`, `reload`).
- None of them fires when a user is disabled or deleted from console/Admin SDK. On resume, call
  `currentUser?.reload()` and treat `user-disabled` / `user-not-found` as sign-out.

`firebase_auth` 6.0.0 removed five APIs, so pre-6.0 code and tutorials no longer compile:

| Removed | Replacement |
|---|---|
| `fetchSignInMethodsForEmail()` | None. Deleted to stop email enumeration; Firebase's own error docs are stale |
| `User.updateEmail()` | `User.verifyBeforeUpdateEmail()` |
| `FirebaseAuth.instanceFor(persistence:)` | `instanceFor(app:)` then `setPersistence(...)` |

## Firestore reads are billed per document

Every document delivered is a read: the initial query result, each document changed while a listener
is open, and each one re-fetched by a rebuild that re-subscribes. The free tier is 50k reads/day, then
about $0.03 per 100k, so a chatty `StreamBuilder` on a list screen is a bill.

- Never fetch a list and then fetch each parent in a loop (N+1): denormalize what the list needs into
  the list document, or use one batched `whereIn`. That query participates in Firestore's 30-disjunction
  limit (at most 30 values, `not-in` 10), so chunk longer id lists and run the batches concurrently.

```dart
// WRONG: .whereIn(FieldPath.documentId(), allIds) throws once the list exceeds 30
// RIGHT: chunk to 30, then restore the order the caller asked for
Future<List<Profile>> profilesByIds(List<String> ids) async {
  final byId = <String, Profile>{};
  for (var i = 0; i < ids.length; i += 30) {
    final end = i + 30 > ids.length ? ids.length : i + 30;
    final snap = await FirebaseFirestore.instance
        .collection('profiles')
        .whereIn(FieldPath.documentId(), ids.sublist(i, end))
        .orderBy(FieldPath.documentId()) // ordered by id, not by your list
        .get();
    for (final doc in snap.docs) {
      byId[doc.id] = Profile.fromMap(doc.id, doc.data());
    }
  }
  return [for (final id in ids) if (byId[id] != null) byId[id]!];
}
```

Two more limits for schema design: one `not-in` or `!=` per query, and at most 100 combined filters,
sort orders and parent document path.

## Typed collections with withConverter

Raw `Map<String, dynamic>` at every call site is how a field rename becomes a runtime cast error.

```dart
// WRONG: untyped map reaches the UI; a renamed field still compiles
final doc = await FirebaseFirestore.instance.collection('notes').doc(id).get();
final title = doc.data()!['titel'] as String;
// RIGHT: one converter, typed at compile time
CollectionReference<Note> get notesRef => FirebaseFirestore.instance
    .collection('notes')
    .withConverter<Note>(
      fromFirestore: (snapshot, _) {
        final data = snapshot.data()!;
        return Note(
          id: snapshot.id, // doc.id is NOT in snapshot.data()
          title: data['title'] as String,
          createdAt: (data['createdAt'] as Timestamp).toDate(),
        );
      },
      toFirestore: (note, _) => {
        'title': note.title,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

final Note? note = (await notesRef.doc(id).get()).data(); // typed, null-safe
```

## Server timestamps, not client time

```dart
final notes = FirebaseFirestore.instance.collection('notes'); // untyped, for raw maps
// WRONG: a skewed device clock writes a row that sorts into the wrong place
await notes.add({...note.toJson(), 'createdAt': DateTime.now().toIso8601String()});
// RIGHT: the server decides, so ordering and paging stay consistent
await notes.add({...note.toJson(), 'createdAt': FieldValue.serverTimestamp()});
```

- Never sort on client time. A wrong clock puts the row in the wrong place, and a paging query then
  skips or repeats it.
- `Timestamp` has no `toJson()`, so `jsonEncode` on a model holding one throws. Convert explicitly
  with `.toDate()` / `Timestamp.fromDate(...)`, which also matters when the same model is cached in
  drift or written to disk.
- `FieldValue.serverTimestamp()` resolves server-side, and a listener first sees the write as pending
  (`metadata.hasPendingWrites`) with the field unresolved: parse defensively, never cast `!`.

## Listeners own a subscription, the widget owns the listener

```dart
// In a State that declares _sub, _notes and _error.
@override
void initState() {
  super.initState();
  _sub = notesRef.orderBy('createdAt', descending: true).limit(50).snapshots().listen(
    (snap) => setState(() => _notes = [for (final d in snap.docs) d.data()]),
    onError: (Object e, StackTrace s) => setState(() => _error = e),
  );
}
@override
void dispose() {
  _sub?.cancel(); // without this the listener keeps billing after the screen is gone
  super.dispose();
}
```

Leaking a `snapshots()` listener costs money, not just memory: it stays attached to the backend, keeps
receiving changed documents, and every one is a billed read. The classic bug is subscribing in
`build()`, or in a `StreamBuilder` whose stream expression is rebuilt, which opens a new listener per
frame. Offline persistence is on by default on Android and iOS, so `get()` can serve a cached document
and `.snapshots()` can emit from cache before the server catches up; disable it deliberately with
`FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);`, the switch that
replaced `enablePersistence()` in `cloud_firestore` 6.0.0.

## Security rules are the boundary

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /notes/{noteId} {
      allow read: if request.auth != null && request.auth.uid == resource.data.ownerId;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.ownerId;
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.ownerId;
    }
  }
}
```

- A client can call the REST API directly with your public API key. Rules are the only thing between a
  stranger and your data; never rely on the app "only showing this screen".
- `if request.auth != null` alone is not a production rule: Google labels it "not recommended for
  production applications". Scope every rule to a field, `request.auth.uid`.
- `rules_version = '2';` is the first line, and is required for collection group queries.
- Deploy with `firebase deploy --only firestore:rules`, and test in the console simulator plus the
  Local Emulator Suite. Server/Admin SDK code bypasses rules entirely, which is why every privileged
  write belongs on the server. Console-created databases deny all access by default.

Secrets (payment keys, LLM keys) live in Cloud Functions, bound from Google Cloud Secret Manager and
read server-side; the client calls `FirebaseFunctions.instance.httpsCallable('name').call(params)`.
Never put a secret in the app, in `--dart-define`, or in a Firestore document.

## Common mistakes

| Mistake | Symptom |
|---|---|
| `Firebase.initializeApp` before `ensureInitialized()` | Platform channel error at startup, or a second default app |
| `snapshots()` listener not cancelled in `dispose()` | Reads keep being billed after the screen closes; `setState` after dispose |
| `DateTime.now()` for ordering | Rows sort wrongly for skewed clocks; paging skips documents |
| `jsonEncode` of a model holding a `Timestamp` | "Converting object to an encodable object failed" |
| `whereIn` with more than 30 ids | The query throws and the screen shows nothing |
| `fetchSignInMethodsForEmail()` copied from a tutorial | Compile error: gone in `firebase_auth` 6.x |
| Committing the prod `google-services.json` | Debug builds write to the production database |
