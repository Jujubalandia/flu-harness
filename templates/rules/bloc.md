---
description: flutter_bloc rules for Cubit vs Bloc choice, immutable events, emit safety, provider ownership, rebuild scope and blocTest.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# flutter_bloc (bloc 9.x)

Target `bloc` 9.x, `flutter_bloc` 9.x, `bloc_test` 10.x. The `bloc` core moves faster than
`flutter_bloc`; check the core changelog first when behaviour surprises you.

## Cubit or Bloc

| | `Cubit` | `Bloc` |
|---|---|---|
| API | public methods that `emit` | events plus `on<Event>` handlers |
| Best for | form fields, toggles, a single async load | many triggers, audit trails, concurrency control |

Choose a `Cubit` when a screen has one obvious entry point per state change. Choose a
`Bloc` when the same state is reachable from many places, when you need to know "what
happened" for analytics, or when you need per-event concurrency control. A `Bloc` with one
`on<Started>` that calls a single method is a `Cubit` in disguise: convert it.

## Events are immutable data

```dart
sealed class SongEvent {
  const SongEvent();
}

final class SongRequested extends SongEvent {
  const SongRequested(this.id);
  final String id;
}
```

Events must be immutable and carry only data: primitives, ids, immutable models. Never a
`BuildContext`, `Widget`, controller, `Future`, or closure. Symptom of passing a controller
instead of a value: a handler touches a screen that no longer exists and the event log
becomes unreadable.

## Handlers, `emit` and `emit.isDone`

```dart
class SongBloc extends Bloc<SongEvent, SongState> {
  SongBloc(this._repo) : super(const SongState()) {
    on<SongRequested>(_onRequested); // one handler per event TYPE, or StateError
  }

  final SongRepository _repo;

  Future<void> _onRequested(SongRequested event, Emitter<SongState> emit) async {
    emit(state.copyWith(status: Status.loading));
    try {
      final song = await _repo.fetchById(event.id);
      if (emit.isDone) return; // bloc closed, or this handler was cancelled
      emit(state.copyWith(status: Status.ready, song: song));
    } on AppFailure catch (e) {
      if (emit.isDone) return;
      emit(state.copyWith(status: Status.failure, message: e.message));
    }
  }
}
```

Rules the source enforces:

- **Events are processed CONCURRENTLY by default.** Two `SongRequested` events race and
  the slower response can overwrite the newer one. Fix with a transformer on that handler,
  or by ignoring a result whose id no longer matches `state`.
- `on<E>` registered twice throws `StateError('on<E> was called multiple times...')` while
  the bloc is constructed.
- `emit` does nothing when the new state is `==` to the current one (only the first emit of
  an instance may repeat the initial state). With value-equal states (freezed, `Equatable`,
  records) a repeated "refresh" produces no rebuild: change a field or drop the emit.
- `BlocBase.emit` throws `StateError('Cannot emit new states after calling close')` on a
  closed bloc. Inside a handler the emitter checks first, so a post-close emit is dropped
  silently instead: the symptom is a final state that never arrives.
- `emit.isDone` is true once the handler completed or was cancelled. Every path after an
  `await` needs it.
- Do not swallow errors: an uncaught handler error reaches `BlocObserver.onError` and is
  rethrown. Catch the domain failure, emit a failure state, let real bugs crash in dev.

Concurrency is the `transformer:` argument of `on<E>`:
`on<SearchChanged>(_onSearchChanged, transformer: restartable())` cancels the previous
request and `sequential()` queues them (both from `package:bloc_concurrency`; the
hand-written sequential form is `(events, mapper) => events.asyncExpand(mapper)`).
Without one, a search field fires a request per keystroke and the UI shows whichever
response lands last.

## Ownership: `BlocProvider` vs `BlocProvider.value`

- `BlocProvider(create: ...)` creates the bloc and CLOSES it when the provider leaves the
  tree. This is the normal case, at the top of a feature.
- `BlocProvider.value(value: ...)` does NOT close it. Use it to hand an existing bloc to a
  new route (dialog, pushed page). Ownership stays with the creator.
- Exactly one owner per bloc. `RepositoryProvider` (a plain `provider`) for services and
  repositories, `MultiBlocProvider` when a feature needs several.

```dart
// WRONG: a new bloc per rebuild, closed by nobody, state resets on parent rebuilds.
class SongPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = SongBloc(context.read<SongRepository>());
    return BlocProvider.value(value: bloc, child: const SongView());
  }
}

// RIGHT: created once, owned by the provider.
BlocProvider(create: (c) => SongBloc(c.read<SongRepository>()), child: const SongView())

// RIGHT: the same instance handed to a pushed route; the parent keeps ownership.
Navigator.of(context).push(MaterialPageRoute<void>(
  builder: (_) => BlocProvider.value(value: context.read<SongBloc>(), child: const SongDetail()),
));
```

Symptoms of breaking ownership: `BlocProvider.of() called with a context that does not
contain a Bloc of type X` after a pop or hot reload (the provider sits below the reader);
`Cannot emit new states after calling close` when an in-flight handler outlives its bloc;
state resetting to initial on unrelated rebuilds when the bloc is recreated in `build()`.

## Builders: rebuild scope

| Widget | Rebuilds | Use for |
|---|---|---|
| `BlocBuilder` | every state change passing `buildWhen` | rendering state |
| `BlocListener` | never (callback only) | navigation, snackbars, dialogs, analytics |
| `BlocConsumer` | like builder | only when one subtree needs both |
| `BlocSelector` / `context.select` | only when the selected value changes | one field of a big state |

```dart
// WRONG: widest subscription, and a side effect in build.
class SongView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<SongBloc>().state; // rebuilds on ANY state change
    if (state.status == Status.failure) _snack(context, state.message!); // repeats
    return Text(state.title);
  }
}

// RIGHT: narrow rebuild, filtered side effect.
BlocListener<SongBloc, SongState>(
  listenWhen: (previous, current) => previous.status != current.status,
  listener: (context, state) { /* showSnackBar once per status change */ },
  child: BlocBuilder<SongBloc, SongState>(
    buildWhen: (previous, current) => previous.title != current.title,
    builder: (context, state) => Text(state.title),
  ),
)
```

- `context.select((SongBloc bloc) => bloc.state.title)` rebuilds only when `title`
  changes: cheaper than `context.watch`, no extra widget.
- A `BlocBuilder` above `Scaffold` rebuilds the app bar, body and bottom bar on every
  state change: wrap the leaf that consumes the state instead.
- Never navigate, show a dialog, or log analytics in `build`: it repeats on every rebuild,
  and navigating during build throws "setState() or markNeedsBuild() called during build".
- Never `add()` an event in `build`; use `initState` or a post-frame callback.

## BlocObserver

```dart
class AppBlocObserver extends BlocObserver {
  @override
  void onCreate(BlocBase<dynamic> bloc) => log('+ ${bloc.runtimeType}');

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('! ${bloc.runtimeType}: $error'); // route to crash reporting here
    super.onError(bloc, error, stackTrace);
  }
}

// main(): Bloc.observer = AppBlocObserver(); -- older docs show BlocOverrides.runZoned.
```

Also overridable: `onEvent(Bloc, Object?)`, `onChange(BlocBase, Change)`,
`onClose(BlocBase)`; `MultiBlocObserver` composes several. Keep them cheap: they run on
every transition.

## Testing with blocTest

```dart
blocTest<SongBloc, SongState>(
  'emits [loading, ready] when SongRequested succeeds',
  build: () => SongBloc(FakeSongRepository(song: song)),
  act: (bloc) => bloc.add(const SongRequested('42')),
  expect: () => [
    isA<SongState>().having((s) => s.status, 'status', Status.loading),
    isA<SongState>().having((s) => s.song, 'song', song),
  ],
);
```

Parameters: `build`, `setUp`, `seed`, `act`, `wait`, `skip`, `expect`, `verify`, `errors`,
`tearDown`, `tags`.

- `expect` asserts the COMPLETE ordered list of states: `blocTest` closes the bloc at the
  end, so one extra state fails the test. That is the feature, not a nuisance.
- `seed: () => state` starts from a non-initial state; `wait:` covers debounce; `errors:`
  asserts thrown errors. Concurrent handlers make multi-event tests non-deterministic:
  use a sequential transformer on the handler under test, or pass `wait:`.

## Common mistakes

| Mistake | Symptom |
|---|---|
| Emitting after the bloc closed (in-flight handler) | dropped state, or `StateError: Cannot emit new states after calling close` |
| Missing `emit.isDone` after `await` | the final state never arrives; intermittent lost updates |
| Non-serializable object in an event | crash after navigation, leaked controllers, unloggable events |
| One giant `AppBloc` for the whole app | every screen rebuilds on unrelated changes; a state file nobody dares edit |
| Side effects in `build()` | snackbars and dialogs repeat on every rebuild; "setState during build" errors |
| `BlocProvider.value` with a bloc created in `build()` | state resets on unrelated rebuilds, old bloc never closed |
| Providing the bloc inside the route that reads it | `BlocProvider.of() called with a context that does not contain a Bloc of type X` |
| `BlocBuilder` above `Scaffold` | whole-screen rebuilds, jank on every keystroke |
| Two `on<SameEvent>` registrations | `StateError` at bloc construction |

