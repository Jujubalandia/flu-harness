---
description: Supabase in Flutter - one-time init, secure session storage, auth-gated routing, PostgREST cardinality, RLS policies, realtime channel lifecycle, Edge Functions and forward-only migrations.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Supabase (supabase_flutter 2.x)

Target: `supabase_flutter` 2.17.x on Flutter stable / Dart 3.x. Behaviour below was read from the
published 2.17.2 source, not from blog posts. Two rules drive everything else: the publishable key
ships inside your binary, so **RLS is the security boundary** (a table with RLS off is a public
table); and the session token is a bearer credential, so `shared_preferences`, which is plaintext on
disk, is not an acceptable place for it.

## Initialize once, in main()

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(),
      pkceAsyncStorage: SecurePkceStorage(),
    ),
  );
  runApp(const App());
}
```

```dart
// WRONG: init inside a widget, unawaited, re-run on every rebuild
Widget build(BuildContext context) {
  Supabase.initialize(url: url, publishableKey: key); // silently ignored
  return const MaterialApp(home: Home());
}
// RIGHT: await it in main(), then read Supabase.instance.client anywhere.
```

- `anonKey` is deprecated in favour of `publishableKey`. The `service_role`/secret key must never
  appear in the app, in any file. Credentials come from `--dart-define`, never a committed constant.
- `Supabase.initialize` is idempotent in 2.17.2: a second call logs "already initialized" and returns
  the first instance. That is worse than a crash when the second call carries different credentials
  (flavor switch, test bootstrap), because you keep talking to the first project while believing you
  switched. Reading `Supabase.instance` too early trips an assert instead.

## Session storage: the default is not secure

With no `localStorage`, `Supabase.initialize` picks `SharedPreferencesLocalStorage`, keyed
`sb-<project-ref>-auth-token`: an XML file in app-private storage on Android and a plist on iOS,
readable with root/JB, from a backup, or from an emulator image. A stolen session is full account
access with no second factor. There is **no built-in secure implementation**
(`FlutterSecureStorageLocalStorage` does not exist in 2.17.x), so you write the `LocalStorage`
subclass yourself. The contract has exactly five members: `initialize()`, `hasAccessToken()`,
`accessToken()`, `removePersistedSession()`, `persistSession(String)`.

```dart
// lib/data/secure_session_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  static const _storage = FlutterSecureStorage();
  // Same key the default store uses, or every logged-in user is signed out.
  static const _key = 'sb-<project-ref>-auth-token';

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
```

Do not copy the package README example verbatim: it uses `supabasePersistSessionKey`, whose own doc
comment says "Only used for migration from Hive to SharedPreferences. Not actually in use." Copying it
into a shipped app makes every existing session invisible and silently logs out every user. Adopt
secure storage before the first release, or migrate the old key.

The PKCE code verifier is separate: `pkceAsyncStorage` defaults to
`SharedPreferencesGotrueAsyncStorage`, so securing only `localStorage` leaves the verifier in
`shared_preferences`. Implement `GotrueAsyncStorage` as well (`getItem`, `setItem`, `removeItem`).

## Auth state for routing

```dart
final sub = Supabase.instance.client.auth.onAuthStateChange.listen(
  (AuthState state) {
    // state.event: initialSession, signedIn, signedOut, tokenRefreshed, ...
    router.refresh();
  },
  // Required: token-refresh failures would otherwise be unhandled zone errors.
  onError: (Object error, StackTrace stack) => logAuthError(error, stack),
);
```

- The stream emits `AuthChangeEvent.initialSession` at startup even with no session, so a router that
  only listens still gets a first event and does not hang.
- `currentUser` is `User?`, `currentSession` is `Session?`. Both are null after sign-out and until
  session restore finishes, so `auth.currentUser!.id` in `build()` is the standard crash on cold start
  and after sign-out. Branch on `currentUser == null`, and cancel the subscription in `dispose()`. For
  a simple guard, `StreamBuilder<AuthState>` plus a splash until `snapshot.hasData` is enough.

## PostgREST: select / single / maybeSingle

```dart
final List<Map<String, dynamic>> rows = await client.from('notes').select();
final Map<String, dynamic> row = await client.from('notes').select().eq('id', id).single();
final Map<String, dynamic>? maybe = await client.from('notes').select().eq('id', id).maybeSingle();
```

`.single()` sends `Accept: application/vnd.pgrst.object+json`. When the result is 0 rows **or** more
than 1 row, PostgREST answers HTTP 406 with code `PGRST116` ("JSON object requested, multiple (or no)
rows returned") and the client throws `PostgrestException`. `.maybeSingle()` returns `null` for 0 rows
and still throws for more than one, so it is the right call for "fetch by id or fall back".

```dart
// WRONG: crashes when the row is missing (new user, deleted note, lost race)
final p = await client.from('profiles').select().eq('id', user.id).single();
// RIGHT: absence is a normal outcome
final p = await client.from('profiles').select().eq('id', user.id).maybeSingle();
return p == null ? const OnboardingScreen() : Profile.fromJson(p);
```

`PostgrestException` carries `message`, `code`, `details`, `hint`. Branch on `code`, never on message
text: `23505` unique violation, `42501` permission denied, `PGRST116` cardinality.

## RLS is the security boundary, not the client

A table in an exposed schema with RLS disabled is fully readable and writable by anyone holding the
publishable key, which is in your binary. Enable RLS on every table, then add explicit policies.

```sql
alter table public.notes enable row level security;
create policy "read own notes" on public.notes
  for select to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);
create policy "insert own notes" on public.notes
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
```

- `using` filters visible rows (select/update/delete); `with check` validates the row being written
  (insert and update). Omitting `with check` on insert lets a user create rows owned by somebody else.
- `auth.uid()` returns null when unauthenticated, so a bare `auth.uid() = user_id` does not error, it
  matches nothing. Add the null check and scope the policy with `to authenticated`.
- Wrap the call as `(select auth.uid())`: the unwrapped form is re-evaluated per row and is flagged by
  Supabase's advisor as `auth rls initplan`.
- Error `42501` is raised before any policy runs: fix the grants
  (`grant select on public.notes to authenticated`), not the policy. Verify signed out and as a second
  user; testing as yourself proves nothing. Run the dashboard Advisors before shipping.

Anything that needs a secret (payment provider, LLM key, admin write, webhook signature) belongs in an
Edge Function invoked with `client.functions.invoke('name', body: {...})`, which holds the secret in
the function environment: not in the client, and not behind RLS.

## Realtime: unsubscribe with the widget

```dart
// In a StatefulWidget that owns the channel (widget.roomId is its own field).
@override
void initState() {
  super.initState();
  _channel = Supabase.instance.client
      .channel('room:${widget.roomId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: widget.roomId,
        ),
        callback: (payload) => setState(() => _apply(payload)),
      )
      .subscribe();
}

@override
void dispose() {
  Supabase.instance.client.removeChannel(_channel); // not optional
  super.dispose();
}
```
- Forgetting `removeChannel` leaves a live socket subscription per navigation: callbacks firing on a
  disposed State (`setState() called after dispose`), duplicate events, a growing websocket count.
- Postgres Changes must be enabled per table in the Realtime publication, or `subscribe` succeeds and
  no event ever arrives. RLS does not filter DELETE events, so a delete payload can reveal that a row
  existed. For a self-updating list, `client.from('notes').stream(primaryKey: ['id'])` is less code.

## Migrations

- SQL lives in `supabase/migrations/` as timestamped files (`supabase migration new <name>`), applied
  with `supabase db push`. Dashboard SQL edits are prototyping only: if it is not in a migration file,
  it does not exist in the next environment.
- Migrations are applied forward only. Never edit a migration that has run anywhere; write a new one.
- Enable RLS in the same migration that creates the table, in the same commit. Add a new column as
  nullable (or with a default) first, ship code that tolerates both, then add the constraint: a
  published app is always one version behind your database.

## Common mistakes

| Mistake | Symptom |
|---|---|
| Calling `Supabase.initialize` again with a different project | Silent no-op; queries hit the old backend and the new key is "ignored" |
| `.single()` on a query that can return 0 rows | `PostgrestException` code `PGRST116` / HTTP 406 on the "new user has no profile" path |
| `.single()` where two rows match | Same `PGRST116`, usually a missing unique index |
| `service_role` key in `lib/` or in a `--dart-define` | RLS bypassed for anyone who extracts it; total data compromise |
| RLS never enabled on a new table | Table is world-readable with the publishable key, and nothing errors |
| `using` written but no `with check` on insert | Users can create rows owned by other users |
| `removeChannel` missing in `dispose()` | Duplicate events, `setState` after dispose, websocket growth |
| Secure storage added after release with the README's key | Every user silently signed out on upgrade |
