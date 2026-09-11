---
description: Folder structure, widget decomposition, naming and error handling conventions for Flutter/Dart source. Applies to every .dart file.
globs: ["**/*.dart"]
alwaysApply: true
---

# Patterns

## Folder structure

Organize by **feature**, not by layer. A feature folder holds everything that
feature needs; a `screens/` folder holding forty unrelated files is where
navigation goes to die.

```
lib/
  main.dart                 # runApp, ProviderScope, error zone
  app.dart                  # MaterialApp.router, theme, localization delegates
  core/
    theme/                  # tokens, ThemeData, text styles
    router/                 # route table, guards
    errors/                 # failure types, error mapping
    utils/                  # pure helpers, no Flutter imports
  features/
    auth/
      data/                 # repositories, remote/local sources
      domain/               # models, entities
      providers/            # state notifiers / blocs
      widgets/              # widgets used only by this feature
      auth_screen.dart
    paywall/
      ...
  shared/
    widgets/                # genuinely reusable widgets
    extensions/             # BuildContext, String, DateTime extensions
```

Rules:
- `core/` must not import from `features/`.
- A feature must not import another feature's `widgets/` or `providers/`. If two
  features need the same thing, it belongs in `shared/` or `core/`.
- `utils/` and `domain/` files should have no `package:flutter` import. If they
  do, the logic is in the wrong place and cannot be unit tested cheaply.

## Widgets

```dart
// WRONG - the whole screen rebuilds on every counter tick
class CounterScreen extends StatefulWidget {
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const HeavyHeader(),          // rebuilds for no reason
          Text('$count'),               // only this needed to change
          ElevatedButton(
            onPressed: () => setState(() => count++),
            child: const Text('+'),
          ),
        ],
      ),
    );
  }
}
```

```dart
// RIGHT - only the counter subtree rebuilds
class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(counterProvider);
    return Column(
      children: [
        const HeavyHeader(),
        Text('$count'),
        ElevatedButton(
          onPressed: () => ref.read(counterProvider.notifier).increment(),
          child: const Text('+'),
        ),
      ],
    );
  }
}
```

- `const` wherever the fields allow it. This is not a micro-optimization: a
  `const` widget is identical across rebuilds, so Flutter skips the subtree
  entirely. `flutter analyze` with `prefer_const_constructors` enforces it.
- A `build()` over ~80 lines wants to be two or three widgets. Extract them.
- Never create a `Ticker`, `AnimationController`, `TextEditingController` or
  `StreamSubscription` in `build()`. Create in `initState`/`late final`, dispose
  in `dispose`.
- Widgets take data in and callbacks out. A widget that reaches into a global
  provider has no reuse and no test.

## Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| File | `snake_case.dart` | `paywall_screen.dart` |
| Widget class | `PascalCase`, noun | `PaywallScreen`, `PriceCard` |
| State notifier | `<Feature>Notifier` | `PaywallNotifier` |
| Provider | `<feature>Provider` | `paywallProvider` |
| Repository | `<Entity>Repository` | `SubscriptionRepository` |
| Private member | leading `_` | `_controller` |
| Boolean | `is` / `has` / `can` prefix | `isLoading`, `hasAccess` |
| Callback param | `on<Thing>` | `onPressed`, `onPurchaseComplete` |

Do not abbreviate. `btn`, `ctx`, `usr`, `cfg` cost more reading time than they
save typing.

## Async and errors

```dart
// WRONG - three nullable flags that can contradict each other,
// and a BuildContext used after an await
Future<void> load() async {
  setState(() => loading = true);
  final data = await repo.fetch();
  setState(() {
    loading = false;
    this.data = data;
  });
  ScaffoldMessenger.of(context).showSnackBar(...); // context may be dead
}
```

```dart
// RIGHT - one state object that cannot be in two states at once,
// and the context is checked after every await
Future<void> load() async {
  state = const Loading();
  final result = await repo.fetch();
  if (!ref.mounted) return;              // or `if (!mounted) return;` in a State
  state = result.fold(
    (failure) => Error(failure.message),
    (data) => Ready(data),
  );
}
```

- Model async state as a sealed class or `AsyncValue`, not as
  `bool isLoading` + `Object? error` + `T? data`.
- After **every** `await` in a widget or notifier, check that the object is still
  alive before touching `context` or `state`. `use_build_context_synchronously`
  flags this; do not silence it.
- Map exceptions to a domain failure type at the data layer boundary. Do not let
  `DioException`, `PostgrestException` or `PlatformException` reach a widget.
- `catch (e)` and then doing nothing is a bug that will cost you a day later.
  At minimum log it.

## Streams and listeners

```dart
// RIGHT - subscription created once, cancelled on dispose
late final StreamSubscription<AuthState> _sub;

@override
void initState() {
  super.initState();
  _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
    if (mounted) setState(() {});
  });
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

A subscription that is not cancelled keeps the widget's closure alive, keeps the
stream alive, and in Firebase's case keeps billing you.

## Error boundaries

Wrap `runApp` in a zone that reports uncaught errors, and give the widget tree a
top-level `ErrorWidget.builder` that renders something a user can act on in
release builds:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crashReporter.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashReporter.recordError(error, stack, fatal: true);
    return true;
  };
  runApp(const ProviderScope(child: App()));
}
```

Without this, a release-mode exception shows a grey box and tells you nothing.

## Imports

- Prefer `package:` imports for anything crossing a folder boundary; relative
  imports only within the same feature folder.
- Never use a barrel `index.dart` that re-exports a whole feature. It hides
  dependency cycles and slows the analyzer.
- Keep import order: `dart:`, `package:flutter`, other `package:`, then relative.
  `dart format` does not sort this; `directives_ordering` does.

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| `setState(() {})` with no change | whole screen rebuilds, 60fps becomes 30fps |
| Controller created in `build()` | animation restarts every frame, memory grows |
| Not disposing a controller | "AnimationController was not disposed" in debug |
| `context` used after `await` | "Looking up a deactivated widget's ancestor" |
| Logic in `build()` | runs on every rebuild, sometimes many times per second |
| Feature importing another feature | circular imports, then a mystery compile error |
| `catch (e) {}` | the bug is now invisible instead of loud |
