---
description: Flutter rendering performance, rebuild discipline, list performance, app size and startup. Applies to any widget or state code.
globs: ["**/*.dart"]
alwaysApply: true
---

# Performance

Flutter performance work is almost entirely about **not rebuilding things that did
not change**, and about keeping work off the UI thread. Everything below follows
from those two.

## `const` is the cheapest optimization there is

```dart
// WRONG - a new instance every build, so the subtree is rebuilt every build
Widget build(BuildContext context) {
  return Column(children: [
    Icon(Icons.star, size: 24),
    Text('Hello'),
  ]);
}
```

```dart
// RIGHT - identical instances, so Flutter skips the whole subtree
Widget build(BuildContext context) {
  return const Column(children: [
    Icon(Icons.star, size: 24),
    Text('Hello'),
  ]);
}
```

A `const` widget is canonicalized at compile time. Two builds produce the *same*
object, so `Element.updateChild` sees no change and stops walking. Turning one
`const` on can remove hundreds of rebuilds per frame.

`prefer_const_constructors` in `analysis_options.yaml` catches this mechanically.
Leave it on.

## Scope rebuilds to the thing that changed

```dart
// WRONG - one counter tick rebuilds the whole screen, including the heavy list
class _ScreenState extends State<Screen> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      HeavyChart(data: chartData),     // rebuilt for nothing
      Text('$count'),
      ElevatedButton(
        onPressed: () => setState(() => count++),
        child: const Text('+'),
      ),
    ]);
  }
}
```

```dart
// RIGHT - only the leaf subscribes, so only the leaf rebuilds
class CounterLabel extends ConsumerWidget {
  const CounterLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text('${ref.watch(counterProvider)}');
  }
}
```

Three tools, in order of preference:

1. **State-management scoping** — `ref.watch` inside the leaf widget that needs
   the value (Riverpod), or `BlocBuilder` around the leaf (Bloc). Not at the top.
2. **`ValueListenableBuilder` / `AnimatedBuilder`** — when the value is a
   `ValueNotifier` or an animation. These rebuild only their `builder`, not the
   enclosing widget.
3. **`context.select`** — subscribe to one field of a big object:
   ```dart
   final name = context.select((User u) => u.name);   // only rebuilds when name changes
   ```

## Lists

```dart
// WRONG - builds every row up front; 10k rows means 10k widgets
SingleChildScrollView(
  child: Column(
    children: items.map((e) => RowTile(item: e)).toList(),
  ),
)
```

```dart
// RIGHT - builds only what is visible, and recycles as you scroll
ListView.builder(
  itemCount: items.length,
  itemExtent: 72,                                  // fixed height lets Flutter skip layout math
  itemBuilder: (context, i) => RowTile(item: items[i]),
)
```

- `itemExtent` (or `prototypeItem`) is a large win for long lists: without it,
  Flutter must lay out items to know how far to scroll.
- Never nest a `ListView` inside a `Column` without `shrinkWrap: true` **and** a
  bounded height. `shrinkWrap` disables lazy building, so it is a fix for small
  lists only.
- Give `ListView.builder` a `key` on items when the list reorders.

## Images

```dart
// RIGHT - decode at the size you will draw, and cache
CachedNetworkImage(
  imageUrl: url,
  cacheWidth: (400 * MediaQuery.devicePixelRatioOf(context)).round(),
  placeholder: (_, __) => const Shimmer(),
  errorWidget: (_, __, ___) => const BrokenImage(),
)
```

A 4000px photo rendered into a 60px avatar is decoded at 4000px and costs ~64MB
of RAM. `cacheWidth` / `cacheHeight` are the fix, and forgetting them is the
single most common cause of OOM crashes in image-heavy Flutter apps.

Bundle assets at the size you need. Use `flutter pub run flutter_launcher_icons`
rather than shipping a 2MB source PNG.

## Keep the UI thread free

The UI thread builds and paints. Anything expensive there drops frames.

```dart
// WRONG - JSON parsing of a large payload on the UI thread
final data = jsonDecode(response.body) as List<dynamic>;
```

```dart
// RIGHT - parse off the UI thread
final data = await compute(_parseItems, response.body);
```

- `compute()` / `Isolate.run()` for parsing, image processing, crypto, and
  anything over a few milliseconds.
- `jank` from a synchronous `await` chain is still jank — `await` yields the
  microtask queue, it does not move work off the thread.
- Use `--profile` builds to measure. **Debug mode is 10-100x slower and its
  numbers mean nothing.**

## Startup

- `main()` should do the minimum: `WidgetsFlutterBinding.ensureInitialized()`,
  framework init, `runApp`.
- Move plugin initialization behind the splash, or into a lazily-resolved
  provider. Splash → blank screen → content is worse than splash → content.
- Defer the heavy first screen behind a `FutureBuilder` with a real loading state.
- Dart VM startup and the first frame are on the critical path; every plugin you
  initialize in `main()` is added to it.

## App size

| Lever | Typical saving |
|-------|----------------|
| `--split-per-abi` instead of a fat APK | ~40% per ABI |
| Remove unused icon fonts / use `--tree-shake-icons` (on by default in release) | 0.5-1MB |
| Drop unused dependencies | varies; check `flutter pub deps` |
| `--analyze-size` to find the actual offenders | — |

```bash
flutter build apk --analyze-size --target-platform=android-arm64
# then open the generated JSON in DevTools
```

Never guess where the size went. Measure.

## RepaintBoundary

Wrap a subtree that animates independently of its surroundings:

```dart
RepaintBoundary(
  child: AnimatedLogo(),   // repaints alone instead of forcing the parent to
)
```

Add it where the profiler shows a repaint. Adding it everywhere adds layers and
makes things worse.

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| Missing `const` | smooth at 5 items, janky at 50 |
| `ref.watch` at the screen root | whole screen rebuilds on every keystroke |
| `ListView` with `.map(...).toList()` children | first frame takes seconds on a long list |
| No `cacheWidth` on network images | memory climbs until the OS kills the app |
| `jsonDecode` on a big payload in `build` | visible stutter on every rebuild |
| Measuring in debug mode | "it's slow" that cannot be reproduced in release |
| `setState` inside a scroll listener | rebuild per frame while scrolling |
| `Opacity` widget instead of `AnimatedOpacity`/`FadeTransition` | offscreen compositing of the whole subtree |
