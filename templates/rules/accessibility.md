---
description: Accessibility in Flutter - semantics labels, tap target sizes, contrast, screen reader flow, text scaling and reduced motion. Applies to every widget file.
globs: ["**/*.dart"]
alwaysApply: true
---

# Accessibility

Accessibility is not a polish task at the end. It is a set of defaults you either
build in or retrofit across every screen. Retrofitting costs a full pass; building
it in costs a minute per widget.

It also finds real bugs. A button a screen reader cannot reach is usually a button
with a broken hit area or an invisible overlay.

## Tap targets

```dart
// WRONG - a 24px icon is a 24px tap target, and thumbs are not that precise
IconButton(
  icon: const Icon(Icons.close, size: 24),
  onPressed: onClose,
)
```

```dart
// RIGHT - constrain to at least 48dp, the visual can stay small
IconButton(
  icon: const Icon(Icons.close, size: 24),
  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
  onPressed: onClose,
)

// or, for a custom widget
InkWell(
  onTap: onTap,
  child: const SizedBox(
    width: 48,
    height: 48,
    child: Center(child: Icon(Icons.close)),
  ),
)
```

- **48dp** minimum on Android, **44pt** on iOS. Use 48 everywhere; it satisfies
  both.
- `ElevatedButton`, `TextButton`, `IconButton`, `ListTile` and `Checkbox` already
  meet this. Custom `GestureDetector` widgets do not.
- Space targets at least 8dp apart. Two small targets next to each other produce
  mis-taps that look like app bugs.

## Semantics labels

```dart
// WRONG - a screen reader announces "button" and nothing else
IconButton(icon: const Icon(Icons.share), onPressed: onShare)
```

```dart
// RIGHT - localized, like every other user-facing string
IconButton(
  icon: const Icon(Icons.share),
  tooltip: l10n.shareAction,
  onPressed: onShare,
)
```

For a custom widget, wrap it:

```dart
Semantics(
  label: l10n.itemCount(items.length),
  button: true,
  enabled: !isLoading,
  child: GestureDetector(onTap: onTap, child: const CardContent()),
)
```

- Every interactive element needs a label. If it has a visible text child, the
  framework derives the label — do not duplicate it, or the reader says it twice.
- **Labels are user-facing strings.** They are localized like everything else.
  A hardcoded English label is a bug in an app shipping three languages.
- `tooltip:` gives a label *and* a long-press affordance on desktop. Prefer it for
  icon-only buttons.

### Images

```dart
// Decorative: exclude it, or the reader announces nothing useful
Image.network(url, excludeFromSemantics: true)

// Meaningful: describe it
Image.network(url, semanticLabel: l10n.productPhotoOf(product.name))
```

An avatar with no label is announced as "image". An avatar with a label of
"image" is the same bug with more code.

### Grouping

```dart
// A list row is one thing to a user, not four things
Semantics(
  container: true,
  label: l10n.orderSummary(order.id, order.totalFormatted),
  child: ExcludeSemantics(
    child: Row(children: [Text(order.id), Text(order.status), Text(order.totalFormatted)]),
  ),
)
```

Without grouping, a reader walks every `Text` in the row separately and the list
becomes unusable.

## Text scaling

Users who set a larger system font size expect the app to honour it.

```dart
// WRONG - ignores the user's setting and can clip
Text('Total', style: const TextStyle(fontSize: 14))
```

```dart
// RIGHT - scales with the user's setting, within a sane bound
MediaQuery.withClampedTextScaling(
  minScaleFactor: 1.0,
  maxScaleFactor: 1.6,
  child: Text(l10n.totalLabel, style: Theme.of(context).textTheme.bodyMedium),
)
```

- Never set `textScaleFactor: 1.0` to "fix" a layout. That is refusing the user's
  setting. Fix the layout: use `Flexible`/`Expanded`, `maxLines` with ellipsis,
  and layouts that wrap.
- Test at 200% text scale. If a screen breaks there, real users hit it.
- Clamping to ~1.6 is a reasonable compromise when a design genuinely cannot
  stretch further. Clamping to 1.0 is not.

## Contrast

- Body text: **4.5:1** against its background. Large text and icons: **3:1**.
- Check both themes. A palette that passes in light mode often fails in dark.
- Never convey meaning by color alone: an error field needs an icon or text
  alongside the red border. Roughly one in twelve men has some color vision
  deficiency.
- Disabled states at low opacity frequently fail contrast. That is acceptable
  for disabled controls, but make sure the *enabled* state passes.

## Reduced motion

```dart
// Respect the OS setting
final reduceMotion = MediaQuery.disableAnimationsOf(context);
final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 300);
```

Vestibular disorders make large motion genuinely nauseating. Honor the setting for
page transitions, parallax and spin, and keep opacity fades — those are safe.

## Focus and keyboard

Relevant for tablets with keyboards, desktop, and TV:

- `FocusTraversalGroup` / `FocusTraversalOrder` to control tab order when visual
  order and widget order disagree.
- `autofocus: true` on the first field of a form.
- `Shortcuts` + `Actions` for keyboard shortcuts, not a raw `RawKeyboardListener`.
- Every focusable element must show a visible focus indicator.

## Testing it

**TalkBack (Android)**
```
Settings > Accessibility > TalkBack > on
```
Then close your eyes and complete the main flow. This is the only test that finds
the real problems.

**VoiceOver (iOS)**: Settings > Accessibility > VoiceOver, or triple-click the
side button.

**Flutter's own tooling**
```bash
# in a debug session, from the terminal running your app:
#   press 'S' to dump the semantics tree
```
The semantics tree dump shows exactly what a screen reader will announce, in
order. Anything missing from it is invisible to assistive technology.

**Automated**
```dart
testWidgets('meets tap target guidance', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(const MyApp());
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
});
```

Four built-in guidelines, one test. Add it to the widget test suite on D12.

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| Icon-only button with no label | screen reader says "button" |
| Hardcoded English semantics label | reader switches language mid-sentence |
| Tap target under 48dp | mis-taps reported as "the app is buggy" |
| `textScaleFactor: 1.0` | user's font setting ignored |
| Color as the only error signal | invisible to color-blind users |
| Row not grouped | list announced one field at a time |
| Decorative image not excluded | reader announces "image" between every item |
| Animations ignore reduced-motion | unusable for users with vestibular disorders |
