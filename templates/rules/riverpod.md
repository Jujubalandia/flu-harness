---
description: Riverpod 3 rules for provider design, ref usage, async state, families, disposal and testing in Flutter apps.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Riverpod 3 (flutter_riverpod + riverpod_annotation)

Target: `flutter_riverpod` 3.x, `riverpod_annotation` 4.x, `riverpod_generator` 4.x.
Riverpod 3 changed runtime behaviour, not only APIs: read "Riverpod 3 behaviour traps"
before debugging "the spinner never stops" or "the error screen never appears".

## Non-negotiables

- One `ProviderScope` at the root, above `MaterialApp`. A second one builds a second
  container and silently splits state in two.
- `ref.watch` only inside `build`. `ref.read` only inside callbacks and handlers.
  `ref.listen` for side effects that must not rebuild.
- Providers never import `package:flutter/material.dart`. No `BuildContext`, no
  `Navigator`, no `ScaffoldMessenger` inside a provider. Return data; let the widget act.
- Codegen (`@riverpod`) is the house style. Raw providers are for trivial values only.
- Anything parameterised is a family. Anything screen-scoped is auto-dispose.

## Declaration: codegen first

```dart
// lib/features/songs/song_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'song_providers.g.dart'; // mandatory; a missing part file breaks every name below

@riverpod // function provider: read-only async value
Future<List<Song>> songList(Ref ref) async {
  final repo = ref.watch(songRepositoryProvider);
  return repo.fetchAll();
}

@riverpod // family: one state per argument, codegen auto-disposes by default
Future<Song> song(Ref ref, String id) => ref.watch(songRepositoryProvider).fetchById(id);

@Riverpod(keepAlive: true) // keepAlive opts OUT of auto-dispose (sessions, caches)
class Auth extends _$Auth {
  @override
  AuthState build() => const SignedOut();

  Future<void> signIn(String email, String password) async {
    state = const SigningIn();
    try {
      final user = await ref.read(authRepositoryProvider).signIn(email, password);
      if (!ref.mounted) return; // Riverpod 3: touching a disposed Ref THROWS
      state = SignedIn(user.id);
    } on AppFailure catch (e) {
      if (!ref.mounted) return;
      state = AuthFailure(e.message);
    }
  }
}

@riverpod // async notifier: async initial state plus mutations
class SongEditor extends _$SongEditor {
  @override
  Future<SongDraft> build(String songId) =>
      ref.watch(songRepositoryProvider).draft(songId);

  Future<void> rename(String title) async {
    final next = await ref.read(songRepositoryProvider).rename(songId, title);
    if (!ref.mounted) return;
    state = AsyncData(next);
  }
}
```

Consumer side: `ref.watch(songProvider('42'))` is the generated family call, and
`ref.read(authProvider.notifier).signIn(...)` is an action, never a watch in `build`.

### Raw form, for comparison

```dart
final authProvider = NotifierProvider<Auth, AuthState>(Auth.new);
final editorProvider = AsyncNotifierProvider<SongEditor, SongDraft>(SongEditor.new);
final songListProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(songRepositoryProvider).fetchAll(),
  isAutoDispose: true, // non-codegen auto-dispose is OPT-IN (constructor default false)
);
final songProvider = FutureProvider.family<Song, String>(
  (ref, id) => ref.watch(songRepositoryProvider).fetchById(id), isAutoDispose: true);
```

Codegen is preferred because it removes the `Ref` type churn of v3, gives families for
free, and lets `riverpod_lint` prove scoping. (Note: `riverpod_lint` 3.1.9 is installed
via `analysis_options.yaml` `plugins:`, not via `custom_lint` in `dev_dependencies`.)

## watch / read / listen

| Use | Where | Why |
|---|---|---|
| `ref.watch(p)` | `build` of a widget or provider | subscribes; rebuilds on change |
| `ref.read(p)` | callbacks, `onPressed`, async handlers | no subscription, one-shot |
| `ref.listen(p, cb)` | `build` only | side effect, no rebuild of this widget |

```dart
// WRONG: read in build (never rebuilds), watch in a callback (nothing subscribes).
final count = ref.read(counterProvider); // frozen at the first frame

// RIGHT: watch in build, read in callbacks.
final count = ref.watch(counterProvider);
onPressed: () => ref.read(counterProvider.notifier).increment();
```

```dart
class SongScreen extends ConsumerWidget {
  const SongScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songListProvider); // subscribe in build
    ref.listen(authProvider, (previous, next) { // side effect, no rebuild
      if (next is AuthFailure) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });
    return Scaffold(body: _body(songs, ref));
  }

  Widget _body(AsyncValue<List<Song>> songs, WidgetRef ref) => songs.when(
        skipLoadingOnRefresh: false, // default true: shows stale data, not a spinner
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorView(error: error),
        data: (value) => SongList(songs: value),
      );
}
```

Pattern matching (preferred for non-trivial states, and exhaustive because
`AsyncValue` is `sealed`). Note that a *refresh* keeps the previous value inside an
`AsyncLoading`, so `AsyncData(:final value)` does NOT match mid-refresh:

```dart
Widget build(BuildContext context, WidgetRef ref) {
  final songs = ref.watch(songListProvider);
  return switch (songs) {
    AsyncValue(hasError: true, :final error) => ErrorView(error: error!),
    AsyncValue(hasValue: true, :final value) => SongList(songs: value!),
    _ => const Center(child: CircularProgressIndicator()),
  };
}
```

`ConsumerStatefulWidget` when you own a controller or need `initState`; `ref` is on the `State`:

```dart
class _SearchBarState extends ConsumerState<SearchBar> { // ConsumerStatefulWidget above
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchProvider.notifier).reset(); // writing during initState throws
    });
  }
}
```

## Disposal, families, invalidation

- Codegen: auto-dispose is the default; `@Riverpod(keepAlive: true)` for anything that
  must survive navigation or hold a cache. Non-codegen: `isAutoDispose: true`.
- Do NOT auto-dispose: auth session, an app-wide cache you paid a network call for,
  an audio player, anything a `keepAlive` sibling still reads.
- Riverpod 3 pauses providers whose consumers are out of view. There is no global
  off-switch; opt out per consumer with `TickerMode(enabled: true, child: Consumer(...))`.
  Symptom: a timer, stream, or animation stops updating on a background tab.
- Family arguments are compared with `==`. `[1, 2] != [1, 2]`, so a new `List` or an
  unserialised object on every `build` creates a NEW provider state every frame: leaked
  state, repeated network calls, dropped scroll position.
- `ref.invalidate(p)` marks the provider stale and returns `void`; callers rebuild.
  Use it in `build`, `ref.listen`, and callbacks. `ref.refresh(p)` returns the new value
  and is invalidate + read; safe outside `build`, risky inside it.
- `ref.watch(p.future)` returns a `Future` you can await; on failure v3 rethrows a
  `ProviderException` that WRAPS the original error, so `on AppFailure` will not catch it.

## Testing

```dart
test('signIn stores the signed-in state', () async {
  final container = ProviderContainer.test( // v3: disposes itself after the test
    overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository())]);
  await container.read(authProvider.notifier).signIn('a@b.c', 'pw');
  expect(container.read(authProvider), isA<SignedIn>());
});
```

- Portable form: `ProviderContainer(overrides: [...])` + `addTearDown(container.dispose)`.
- Notifier override `authProvider.overrideWith(() => FakeAuth())`; one-shot value
  `songListProvider.overrideWithValue(const AsyncData(<Song>[]))`.

## Riverpod 3 behaviour traps

1. Automatic retry is ON by default (up to 10 retries, 200 ms to 6.4 s backoff). A
   failing provider retries instead of surfacing an error, so error UIs never render.
   Disable globally: `ProviderScope(retry: (retryCount, error) => null, child: ...)`,
   or per provider with the `retry:` argument.
2. Providers filter updates with `==`. A `Notifier` holding the same value does not
   notify; override `updateShouldNotify` when that is wrong.
3. `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider` are legacy and
   now live in `package:flutter_riverpod/legacy.dart`. Do not use them in new code.
4. `Ref` has no type parameter any more: generated signatures take bare `Ref`
   (`ExampleRef` is gone). `AutoDisposeNotifier` and `AutoDisposeRef` were removed.

## Common mistakes

| Mistake | Symptom |
|---|---|
| `ref.watch` inside a callback or `initState` | the widget never rebuilds from that dependency; move it into `build` |
| `ref.read(p)` in `build` | value never updates; only the first frame is correct |
| Writing a provider in `initState` (`ref.read(p.notifier).load()`) | throws during the build phase; defer with `addPostFrameCallback` |
| `await` then `context` (`Navigator.pop`, `showDialog`) | `use_build_context_synchronously` lint, then a crash on the popped route; guard with `if (!context.mounted) return;` |
| `await` then `ref` use | Riverpod 3 throws `UnmountedRefException`; guard with `if (!ref.mounted) return;` |
| Watching a whole state object for one field | every unrelated field change rebuilds the screen; use `ref.watch(p.select((s) => s.count))` |
| Building a family argument inline in `build` | new state per frame, repeated API calls, flicker, memory growth |

