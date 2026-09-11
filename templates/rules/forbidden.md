---
description: Forbidden patterns in Flutter/Dart - deprecated APIs, removed widgets and calls that cause silent production bugs. Apply before writing or reviewing any widget code.
globs: ["**/*.dart"]
alwaysApply: true
---

# Forbidden patterns

Each of these is a real trap: it compiles, it usually works, and it breaks in a way
that is hard to trace. If you find one in existing code, fix it in the change you
are already making.

---

## 1. `WillPopScope` — removed

```dart
// NEVER - removed from Flutter; will not compile on recent SDKs
WillPopScope(
  onWillPop: () async => false,
  child: child,
)
```

```dart
// RIGHT
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    // handle the back gesture yourself
  },
  child: child,
)
```

`PopScope` is also what Android predictive back needs. `WillPopScope` cannot
support it at all.

---

## 2. `withOpacity` — deprecated

```dart
// NEVER - deprecated in favour of a wider-gamut-safe API
color: Colors.black.withOpacity(0.5),
```

```dart
// RIGHT
color: Colors.black.withValues(alpha: 0.5),
```

`withOpacity` quantizes to 8-bit channels and loses precision on wide-gamut
displays, so the same value renders differently across devices.

---

## 3. `MaterialStateProperty` — renamed

```dart
// NEVER - old name
MaterialStateProperty.all(Color(0xFF1D9BF0)),
MaterialState.disabled,
```

```dart
// RIGHT
WidgetStateProperty.all(Color(0xFF1D9BF0)),
WidgetState.disabled,
```

`MaterialState*` also implies Material, which is wrong now that the same property
type is used by Cupertino and the base widget layer.

---

## 4. `ColorScheme.background` / `.onBackground` — deprecated

```dart
// NEVER
Theme.of(context).colorScheme.background,
```

```dart
// RIGHT
Theme.of(context).colorScheme.surface,
```

The M3 color system removed the `background` role. Both still resolve, which is
exactly why this one survives in codebases for years.

---

## 5. `MediaQuery.of(context).size` — rebuilds too much

```dart
// WRONG - rebuilds on keyboard open, rotation, and every metrics change
final size = MediaQuery.of(context).size;
final scale = MediaQuery.of(context).textScaleFactor;   // also deprecated
```

```dart
// RIGHT - subscribes to only what you use
final size = MediaQuery.sizeOf(context);
final scale = MediaQuery.textScalerOf(context);
final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
```

`.of(context)` registers a dependency on the whole `MediaQueryData`, so a
keyboard appearing rebuilds your entire screen. The specific accessors do not.

---

## 6. `print()` in application code

```dart
// NEVER in lib/
print('user loaded: $user');
```

```dart
// RIGHT
debugPrint('user loaded: ${user.id}');       // stripped from release by the framework
// or a logger that respects the build mode
```

`print` runs in release builds, spams logcat, costs frames when called in a loop,
and leaks whatever you printed. `avoid_print` catches it.

Android also has a kernel-level limit on log line length and rate; a `print` in a
hot loop will drop the messages you actually wanted.

---

## 7. Business logic in `build()`

```dart
// WRONG - runs on every rebuild, which can be many times per second
@override
Widget build(BuildContext context) {
  final sorted = items..sort((a, b) => a.name.compareTo(b.name));  // MUTATES the list
  final total = items.fold(0.0, (s, e) => s + e.price);
  return ListView(children: sorted.map(...).toList());
}
```

```dart
// RIGHT - computed once, in the layer that owns the data
// (a provider / notifier / repository computes sorted and total)
@override
Widget build(BuildContext context) {
  final view = ref.watch(cartViewModelProvider);
  return ListView.builder(itemCount: view.items.length, ...);
}
```

Sorting inside `build()` also **mutates the source list**, which reorders state
behind the state layer's back. That is a bug that only appears once something else
reads the list.

---

## 8. `setState` after `await` without a liveness check

```dart
// WRONG - throws if the widget was disposed while awaiting
Future<void> load() async {
  final data = await repo.fetch();
  setState(() => _data = data);
  Navigator.of(context).push(...);
}
```

```dart
// RIGHT
Future<void> load() async {
  final data = await repo.fetch();
  if (!mounted) return;
  setState(() => _data = data);
  if (!context.mounted) return;
  Navigator.of(context).push(...);
}
```

Symptom: "setState() called after dispose()" in debug, and in release a silent
no-op or a crash depending on the frame. `use_build_context_synchronously` flags
the context half; the `mounted` half is on you.

---

## 9. Creating controllers or subscriptions in `build()`

```dart
// NEVER
@override
Widget build(BuildContext context) {
  final controller = AnimationController(vsync: this, duration: ...);  // new one per frame
  final sub = stream.listen(...);                                      // leaks one per frame
  ...
}
```

```dart
// RIGHT
late final AnimationController _controller;

@override
void initState() {
  super.initState();
  _controller = AnimationController(vsync: this, duration: ...);
}

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

The memory graph grows until the app is killed. Nothing logs. Nothing throws.

---

## 10. `dynamic` to make the analyzer stop complaining

```dart
// WRONG - the error is now a runtime crash three frames later
final data = response.data as dynamic;
return data['user']['name'];
```

```dart
// RIGHT - model the shape once, validate at the boundary
final data = User.fromJson(response.data as Map<String, dynamic>);
return data.name;
```

`avoid_dynamic_calls` and `strict-casts: true` exist precisely to stop this.
Silencing them with `// ignore:` converts a compile error into a production
incident.

---

## 11. `// ignore:` with no explanation

```dart
// NEVER
// ignore: avoid_print
print('debug');

// ACCEPTABLE - the rule is wrong here, and here is why
// ignore: invalid_annotation_target  -- freezed + json_serializable false positive, see issue #1234
```

An unexplained ignore is indistinguishable from an accident. Either fix the code
or say why the rule does not apply.

---

## 12. Hardcoded user-facing strings

```dart
// WRONG once the app ships in more than one language
Text('Save changes')
Semantics(label: 'Close', child: ...)
TextButton(child: Text('Cancel'))
```

```dart
// RIGHT
Text(l10n.saveChanges)
Semantics(label: l10n.closeAction, child: ...)
TextButton(child: Text(l10n.cancel))
```

This includes `Semantics` labels, `tooltip`, `hintText`, `errorText`, `AppBar`
titles, and the strings in `showDialog`. The ones in dialogs are always missed.

---

## 13. Raw color and spacing literals in widgets

```dart
// WRONG - the design system is now in forty files
Container(color: const Color(0xFF1D9BF0), padding: const EdgeInsets.all(13.7))
```

```dart
// RIGHT - one place to change it, and dark mode works
Container(
  color: Theme.of(context).colorScheme.primary,
  padding: EdgeInsets.all(AppSpacing.md),
)
```

Dark mode is the forcing function: every hardcoded color is a screen you have to
find again when you add dark theme.

---

## Audit checklist

Before committing, confirm none of these appear in the diff:

- [ ] `WillPopScope`
- [ ] `withOpacity(`
- [ ] `MaterialState`
- [ ] `colorScheme.background` / `onBackground`
- [ ] `MediaQuery.of(context).size` / `.textScaleFactor`
- [ ] `print(` in `lib/`
- [ ] a `.sort(`, `.map(` or fold directly inside `build()`
- [ ] `setState` after an `await` with no `mounted` check
- [ ] a controller or `listen(` inside `build()`
- [ ] `as dynamic`
- [ ] an `// ignore:` without a reason on the same line
- [ ] `Text('...literal...')` for user-facing copy
- [ ] `Color(0x...)` or a raw `EdgeInsets` constant in a widget
