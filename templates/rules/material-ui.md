---
description: Flutter 3.47+ standalone design systems (material_ui / cupertino_ui) - the decoupling, the migration, the compatibility bridge and the unbundled localizations. Check this before adding or changing any Material/Cupertino import.
globs: ["**/*.dart", "pubspec.yaml", "l10n.yaml"]
alwaysApply: false
---

# Standalone design systems: material_ui and cupertino_ui

Since Flutter 3.47, Material and Cupertino live in standalone packages on pub.dev
instead of inside the SDK:

| In-framework (old) | Standalone (new) |
|--------------------|------------------|
| `package:flutter/material.dart` | `package:material_ui/material_ui.dart` |
| `package:flutter/cupertino.dart` | `package:cupertino_ui/cupertino_ui.dart` |
| `package:flutter_localizations/flutter_localizations.dart` | bundled into the two packages above |

Contributions to the in-framework libraries were **frozen in Flutter 3.44**, and
they are scheduled for formal deprecation in an upcoming stable release. The 1.0
releases of the packages are byte-for-byte the frozen framework code, so
migrating changes imports and nothing else — at first.

## Which one is this project on?

Check `pubspec.yaml` before writing any widget code. Getting this wrong produces a
wall of "The argument type 'ColorScheme' can't be assigned to the parameter type
'ColorScheme'" errors, because Dart enforces nominal typing across the two
libraries: the class names are identical, the types are not.

```yaml
# migrated project - use the standalone imports
dependencies:
  material_ui: ^1.0.0
  cupertino_ui: ^1.0.0
```

```dart
// migrated
import 'package:material_ui/material_ui.dart';

// not migrated
import 'package:flutter/material.dart';
```

Do not mix them in one file. A file that imports both gets two distinct
`ThemeData` types and confusing errors.

## Migrating

```bash
dart fix --apply --code=migrate_design_widgets
```

That rewrites the imports. It may not add the dependencies, so:

```bash
flutter pub add material_ui cupertino_ui
dart fix --apply          # again, for the follow-on lint fixes (import sorting etc.)
flutter analyze
```

## The compatibility bridge

Third-party packages still importing `package:flutter/material.dart` will fight
you during the transition. The packages ship a bridge for exactly this:

```dart
import 'package:material_ui/material_ui.dart';

MaterialApp(
  builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
  home: const HomeScreen(),
)
```

The bridge injects theme and localization data downward, so an unmigrated child
widget that calls `Theme.of(context)` or `MaterialLocalizations.of(context)`
keeps working.

**What it cannot fix:** type mismatches in public API signatures. If a dependency
exposes, accepts or returns an in-framework type — `FloatingActionButtonLocation`,
`ColorScheme`, `TextTheme` — you cannot pass a standalone-package value to it. No
bridge can help, because the two types are genuinely different. Those packages
must migrate before you can use modern types across that boundary.

Practical consequence: check your dependency list before committing to the
migration. If a key package (a navigation library, a UI kit) has not migrated,
either stay on the in-framework imports or wrap the boundary and accept that you
cannot pass design-system types across it.

## Unbundled localizations

This is the part that breaks an app in a non-obvious way — no compile error, just
untranslated framework strings.

```dart
// BEFORE - three delegates from flutter_localizations
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
)
```

```dart
// AFTER - one delegate list from the design system package
import 'package:material_ui/material_ui.dart';

MaterialApp(
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
)
```

`GlobalMaterialLocalizations.delegates` includes the Cupertino and Widgets
delegates. Add `flutter_localizations` back only if you still need something from
it — with the standalone packages, you usually do not.

Symptom if you get this wrong: your own strings translate, but date pickers, the
back-button tooltip and dialog buttons stay English.

## Guidance for package authors

If you maintain a package, moving to `material_ui` / `cupertino_ui` is a breaking
change for consumers even though every symbol keeps its name — it is a different
library. Treat it as a major version bump.

## Should you migrate now?

| Situation | Do this |
|-----------|---------|
| New project, on Flutter 3.47+ | Use the standalone packages from the start |
| Existing project, dependencies all migrated | Migrate with `dart fix`, then run the full gate plan |
| Existing project, a key dependency has not migrated | Stay on the in-framework imports; the freeze means nothing new is landing there, but nothing is being removed either |
| Mid-sprint, shipping in days | Do not migrate. The in-framework libraries still work and the deprecation is not yet in a stable release. |

Migrating changes every widget file's imports, so it will collide with any branch
in flight. Do it before a feature, never during one.

## Common mistakes

| Mistake | Symptom |
|---------|---------|
| Importing both libraries in one file | two `ThemeData` types; assignment errors that look impossible |
| Migrating without `flutter pub add` | `Target of URI doesn't exist: package:material_ui/...` |
| Passing a standalone `ColorScheme` to an unmigrated dependency | "argument type can't be assigned" that the bridge cannot fix |
| Leaving the three old localization delegates | your strings translate, framework strings stay English |
| Migrating mid-sprint | every file in the diff, every open branch conflicts |
| Assuming the classes changed | they did not - 1.0 matches the frozen framework code exactly |
