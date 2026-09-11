---
description: Flutter animation rules covering implicit vs explicit animations, controller lifecycle and disposal, rebuild scoping, hero and route transitions, staggered and package-based effects, reduced-motion accessibility and jank diagnosis. Load before adding or changing any animation.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# Animation

Target: Flutter 3.3x-3.47 / Dart 3.9-3.13. Every rule here exists to protect one number: 16 ms per frame on the UI thread and on the raster thread. An animation that misses it is worse than no animation at all.
## 1. Reach for implicit animations first

If the change is "this property goes from A to B when state changes", you want an implicit animation, not a controller. `AnimatedContainer`, `AnimatedOpacity`, `AnimatedPadding`, `AnimatedAlign`, `AnimatedSwitcher` and `TweenAnimationBuilder` rebuild only their own subtree, own their own controller, and dispose it for you.
```dart
// RIGHT - no controller, no vsync, no dispose, no leak
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOutCubic,
  width: _expanded ? 240 : 120,
  color: _expanded ? Colors.indigo : Colors.grey,
  child: const Text('Plan'),
)
```
```dart
// RIGHT - for one interpolated value with no State class at all
TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: _progress),
  duration: const Duration(milliseconds: 400),
  builder: (context, value, child) => LinearProgressIndicator(value: value),
)
```
Only move to an explicit `AnimationController` when you need something implicit animations cannot express: play/reverse/stop control, a repeating or ping-pong loop, staggered sub-animations across one timeline, driving several widgets from one value, or reading animation state in a callback.

## 2. Explicit controllers: create in initState, always dispose
```dart
// WRONG - a new controller and Ticker on every rebuild: the animation restarts
// each frame, never advances, and leaks one ticker per build
@override
Widget build(BuildContext context) => FadeTransition(
      opacity: AnimationController(vsync: this, duration: kFast), child: child);
```
```dart
// RIGHT - one controller per State, created once, disposed once
class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();    // without this: "AnimationController was not disposed" in
    super.dispose(); // debug, and a leaked Ticker in release
  }
  // build(): FadeTransition(opacity: _c, child: widget.child)
}
```
`SingleTickerProviderStateMixin` for exactly one controller, `TickerProviderStateMixin` for two or more. Using `SingleTickerProviderStateMixin` with a second controller throws an assertion at runtime, and `TickerProviderStateMixin` costs nothing extra when you only need one, so when in doubt use the plural mixin.

Never call `setState` from an animation listener unless the layout genuinely depends on the value; see section 4.

## 3. Tickers do not stop just because a widget is invisible

A controller keeps ticking as long as its ticker is enabled, even when the subtree paints nothing. The framework mutes tickers through `TickerMode`: `Overlay` mutes routes hidden under an opaque route, `Hero` mutes during flight, `AnimatedCrossFade` and `Visibility` mute the hidden child. Widgets you keep alive yourself do not get that for free.
```dart
// RIGHT - an off-screen but kept-alive subtree stops animating
TickerMode(enabled: _isVisible,
    child: const HeavyAnimatedPanel())  // its controllers keep their state
```
```dart
// WRONG - both panels are always "on stage", so both loop forever and you
// pay for two animations while showing one
IndexedStack(index: _index, children: [Panel(), Panel()]),
```
`Visibility(visible: false, maintainState: true, maintainAnimation: false, child: ...)` is the declarative version: it wraps the child in `TickerMode` for you. If you keep tabs or pages alive for state, wrap them in `TickerMode` and drive `enabled` from the selection.

## 4. Scope the rebuild: AnimatedBuilder around the smallest subtree

`AnimatedBuilder` rebuilds its `builder` on every tick. Put a whole screen inside it and you rebuild the whole screen 60 times a second - the classic "I animate one box and the list stutters".
```dart
// WRONG - everything in the builder rebuilds on every frame
AnimatedBuilder(
  animation: _c,
  builder: (context, child) => Column(children: [
    const HeavyHeader(), const HeavyList(),
    Transform.scale(scale: _c.value, child: const Box())]),
)
```
```dart
// RIGHT - only the Transform rebuilds; the child is built once and reused
AnimatedBuilder(
  animation: _c,
  child: const Box(),   // built once, passed through
  builder: (context, child) => Transform.scale(scale: _c.value, child: child))
```
Better still, when a widget already accepts an `Animation`, hand it the animation and let it listen internally: `FadeTransition`, `ScaleTransition`, `SlideTransition`, `RotationTransition`, `SizeTransition`, `AlignTransition`, `AnimatedBuilder` and the `Transition` family all avoid rebuilding their child. Prefer `AnimatedBuilder` only when no transition widget expresses the effect.

If a value is only consumed by `paint`, changing it should not trigger a rebuild at all - a `CustomPainter` with a `repaint: Listenable` (pass the controller as `super(repaint: controller)`) repaints without rebuilding any widget.

## 5. Heroes: unique tags, and only one flight at a time

`Hero` animates a widget from one route to another by matching `tag` values. Two heroes with the same tag inside one subtree trip `There are multiple heroes that share the same tag within a subtree`, and the flight is skipped or the frame throws.
```dart
// RIGHT - the tag is derived from the item, so it is unique per screen
Hero(tag: 'avatar-${user.id}',
    child: CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl)))
```
```dart
// WRONG - two list items with the same tag on one route
ListView(children: users.map((u) => Hero(tag: 'avatar', child: Avatar(u))).toList())
```
Rules that save time: a tag must be unique per route, not per app; both routes must build a hero with the same tag or the transition silently does not happen; wrap image heroes so the destination size is not zero on first layout; use `flightShuttleBuilder` when the pushed and popped children differ. On the destination, `Hero` also works inside a `PageRoute` only - it does not animate across a `dialog`-less overlay you drew yourself.

## 6. Route transitions: PageRouteBuilder for one, PageTransitionsTheme for all
```dart
// One route with a bespoke transition
Navigator.of(context).push(PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 250),
  pageBuilder: (_, __, ___) => const DetailsScreen(),
  transitionsBuilder: (_, animation, __, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
));
```
```dart
// Every route on a platform, declared once in the theme
MaterialApp(
  theme: ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder()})),
)
```
Available builders in current Flutter: `ZoomPageTransitionsBuilder` (Android default), `CupertinoPageTransitionsBuilder`, `FadeForwardsPageTransitionsBuilder`, `FadeUpwardsPageTransitionsBuilder`, `OpenUpwardsPageTransitionsBuilder` and `PredictiveBackPageTransitionsBuilder` (Android predictive back). Prefer the theme over per-route builders: inconsistent transitions across an app read as bugs. Keep route transitions under ~300 ms; anything slower feels broken on repeat use.

## 7. Staggered animations: one controller, many Intervals

Do not create one controller per element in a list. Use one controller and slice it with `Interval`, so the whole sequence stays in sync and costs one ticker.
```dart
late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900))..forward();

Animation<double> _step(double a, double b) => CurvedAnimation(
    parent: _c, curve: Interval(a, b, curve: Curves.easeOutCubic));

// usage: FadeTransition(opacity: _step(0.0, 0.3), child: ...)
//        SlideTransition(position: _step(0.2, 0.6).drive(Tween(begin: ..., end: ...)))
```
`Interval(begin, end)` maps the parent's 0..1 into a sub-range, and the child animation is flat outside that range. Use `CurvedAnimation` per step rather than one curve on the controller, or every step shares the same easing and the stagger looks wrong.

## 8. flutter_animate for declarative, fire-and-forget effects

`flutter_animate` (4.x) wraps the same machinery in an effect list. It is the right tool for entrance animations, shimmer and one-shot emphasis, and the wrong tool for gesture-driven or continuously interactive animation.
```dart
import 'package:flutter_animate/flutter_animate.dart';

// RIGHT - fade in, then scale; `then(delay:)` rebases the timeline
Text('Welcome')
    .animate().fadeIn(duration: 300.ms).then(delay: 200.ms).scale()

// RIGHT - a staggered list without writing a controller
Column(children: AnimateList(
  interval: 200.ms, effects: [FadeEffect(duration: 300.ms)],
  children: const [Text('One'), Text('Two'), Text('Three')]))
```
`AnimateList` applies the same effects to each child with an interval offset. `.animate(interval: 200.ms).fade()` is the shorthand for a plain `List<Widget>`. Effects animate on build, so an `Animate` inside a rebuilding parent restarts unless the widget keeps its identity - give list children stable keys.

## 9. Lottie and Rive: asset-driven animation, and what it costs

Both packages ship a runtime and render an authored asset, which is why they beat hand-written Flutter code for character animation and why they are a poor fit for a subtle 200 ms transition.
```dart
// Lottie (lottie 3.x) - After Effects exports, JSON
Lottie.asset('assets/animations/success.json',
    width: 160, height: 160, fit: BoxFit.contain, repeat: false)
```
Lottie JSON is text and compresses well, but a complex composition costs real parse time on first use: preload with `LottieComposition.fromAsset` (or hoist the asset) rather than decoding on the frame that shows it.

Rive (`rive` 0.14+) plays `.riv` binaries with state machines and can be driven from Dart. `[VERSION]` the current API is `RiveWidget` with a `RiveWidgetController`; older tutorials use a removed `RiveAnimation` widget, so check the installed version's README before copying a snippet. Both runtimes add native code to the binary: budget a few MB per platform, include it in your app size check, and never ship both if one will do.

## 10. RepaintBoundary: isolate what repaints every frame

A repaint in a subtree repaints its whole layer. Wrap a continuously animating widget in a `RepaintBoundary` so its frames do not drag the rest of the screen's painting with them.
```dart
// RIGHT - the looping shimmer gets its own layer
RepaintBoundary(
  child: AnimatedBuilder(
    animation: _c,
    builder: (context, child) => ShaderMask(/* ... */ child: child),
    child: const PriceCard()),
)
```
Do not sprinkle `RepaintBoundary` everywhere: each one allocates a layer and costs memory, and a boundary around a static widget buys nothing. Add one where DevTools shows a large repaint region moving every frame, and remove it if the profile does not improve.

## 11. Reduced motion is an obligation, not a nicety

Respect the OS setting. A user who enabled "reduce motion" for vestibular reasons gets a scaling, parallaxing interface unless you check.
```dart
// RIGHT - honour the platform setting
final reduce = MediaQuery.disableAnimationsOf(context);
return AnimatedSwitcher(
    duration: reduce ? Duration.zero : const Duration(milliseconds: 300), child: page);
```
`MediaQuery.disableAnimationsOf(context)` is the accessor to use (it subscribes only to that field). `MediaQuery.of(context).disableAnimations` is the same value, and `accessibleNavigation` tells you when a screen reader is active - animations that move content under a reader's focus are hostile. Zero-duration is not the only answer: cross-fades are usually acceptable where slides are not, so prefer removing movement over removing feedback.

## 12. Diagnosing jank: profile mode, then DevTools
```bash
flutter run --profile   # never judge performance in debug
```
```dart
MaterialApp(showPerformanceOverlay: true, home: const App()) // profile builds
```
Debug builds are not representative: assertions, `debugPrint`, unoptimized AOT-less code and the service protocol together make everything look slow. Measure in `--profile` on a real device, watch the UI and raster thread bars in the DevTools Performance page, and look for frames over 16 ms (or over 8 ms if the device runs at 120 Hz). A spike on the raster thread means painting or shader work - look for `saveLayer`, opacity, clipping and blur, and for a first-run shader compile. A spike on the UI thread means build or layout work - look for the rebuild scoping problems in section 4.

## 13. Common mistakes

| Mistake | Symptom |
|---------|---------|
| Controller created in `build()` | animation never advances, one leaked Ticker per frame |
| `dispose()` not overridden | "AnimationController was not disposed", memory growth |
| `setState` in an animation listener | the whole screen rebuilds at 60 fps, jank everywhere |
| `AnimatedBuilder` wrapping a screen | one box animates, everything else rebuilds |
| One controller per list item | dozens of tickers, dropped frames on scroll |
| Ignoring `disableAnimations` | accessibility complaint, motion sickness |
| Measuring performance in debug mode | "jank" that disappears in a release build |
