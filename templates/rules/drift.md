---
description: drift - table definitions and codegen, background-isolate connections, reactive watch queries, batches and transactions, schema versioning with tested step-by-step migrations, type converters.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# drift

Target: drift 2.35.x, drift_dev 2.35.x, drift_flutter 0.3.x, build_runner 2.16.x. Do **not** add
`sqlite3_flutter_libs` directly: drift 2.32+ ships SQLite through the sqlite3 3.x build hooks, so a
transitive lockfile entry is expected while pinning it (plus `open.overrideFor(...)`) is legacy.

## Tables and generated code

```dart
// lib/data/tables.dart
import 'package:drift/drift.dart';

enum Category { work, home, other }

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()(); // seconds since epoch by default
  IntColumn get category => intEnum<Category>()();
}
```

```dart
// lib/data/database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart'; // generated, never edit by hand

@DriftDatabase(tables: [Todos])
class AppDatabase extends _$AppDatabase {
  // The optional executor is what migration tests inject. Keep it.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());
  @override
  int get schemaVersion => 3;
  static QueryExecutor _openConnection() => driftDatabase(name: 'app_db');
}
```

- `intEnum<T>()` stores the enum's `index`, so reordering members or inserting one in the middle
  silently remaps existing rows. If the enum can change, use `textEnum<T>()` (stores the name) or an
  explicit converter with values you control.
- `Value(...)` is drift's sentinel wrapper: `Value.absent()` means "do not touch", `Value(null)` means
  "write NULL".

## The database runs on a background isolate

sqlite3 is a synchronous C library, so running it on the UI isolate blocks frames; a 40 ms query at
16 ms per frame is visible stutter on every scroll.

```dart
// RIGHT, recommended: drift_flutter picks the directory and uses an isolate for you
static QueryExecutor _openConnection() => driftDatabase(name: 'app_db');
// RIGHT, explicit: same isolate behaviour, you own the path (path_provider + path)
static QueryExecutor _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(File(p.join(dir.path, 'app_db.sqlite')));
    });
```

- `NativeDatabase.createInBackground(File)` returns a `QueryExecutor` that owns a long-running isolate;
  `LazyDatabase` defers the async path lookup to first use instead of startup.
- Never use `NativeDatabase(File(...))` in app code: it runs on the calling isolate. A drift database
  also cannot cross isolates, so for heavy jobs use `computeWithDatabase` from `package:drift/isolate.dart`.

## Codegen

```bash
dart run build_runner build --delete-conflicting-outputs   # once, and after schema changes
dart run build_runner watch --delete-conflicting-outputs   # while editing tables
```

- Without it the symptoms are compile errors: "The getter 'todos' isn't defined", "Undefined name
  '_$AppDatabase'", "Target of URI doesn't exist: 'database.g.dart'".
- build_runner 2.16.x rewrites hand-edited generated files silently, so never fix a `.g.dart`: fix the
  table and regenerate. `--delete-conflicting-outputs` has been a no-op since 2.7 and is harmless.
- Commit generated files so a fresh clone compiles without a codegen step; in CI use the write-nothing
  check mode so a forgotten regeneration fails instead of shipping.

## Queries: get vs watch

```dart
Stream<List<Todo>> watchTodos() =>
    (select(todos)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
```

- One-shot reads use `.get()` (and `getSingleOrNull()` when the row may be missing); `watch()` is for
  UI that follows the data.
- `watch()` re-emits when a table in the query's dependency set changes, including writes from another
  drift instance in the same process. It cannot see writes made outside drift in another process (a
  native plugin, a raw-SQL background isolate), so the UI stays stale until restart.
- The leak is like any stream: a subscription outliving the `State` and calling `setState` after
  dispose. Use `StreamBuilder`, or `listen` with cancellation in `dispose()`.

## Writes, batches, transactions

```dart
await into(todos).insert(TodosCompanion.insert(
  title: 'buy milk',
  createdAt: DateTime.now().toUtc(),
  category: const Value(Category.home),
));

// One transaction, one notification to watchers, no partial state.
await batch((b) {
  b.insertAll(todos, newRows);
  b.deleteWhere(todos, (t) => t.done.equals(true));
});
// Multi-statement invariant: all of it or none of it.
await transaction(() async {
  await into(accounts).insert(companion);
  await (update(stats)..where((s) => s.id.equals(1))).write(const StatsCompanion(count: Value(1)));
});
```

- Anything that writes two tables and must stay consistent belongs in `transaction`. Drift starts them
  with `BEGIN IMMEDIATE`, so read-then-write inside one is free of upgrade deadlocks.
- `batch` is also a single transaction, and emits one stream update instead of one per statement.
- Never fake a transaction with `Future.wait` over writes: partial writes and a corrupted local cache.

## Migrations

Bump `schemaVersion` in the same commit as the schema change. Bumping it without an `onUpgrade` step is
how users get "no such column: category" on launch, because an installed app still has the old table.

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) async => m.createAll(),
      onUpgrade: stepByStep(
        from1To2: (m, schema) async => m.addColumn(schema.todos, schema.todos.category),
        from2To3: (m, schema) async => m.createTable(schema.tags),
      ),
    );
```

`stepByStep` comes from the generated `schema_versions.dart`. Each callback receives the schema *at the
version it migrates to*, which is the only way to migrate a column that no longer exists in the current
table class.

```bash
dart run drift_dev schema dump lib/data/database.dart drift_schemas/   # once per schema change
dart run drift_dev schema steps drift_schemas/ lib/data/schema_versions.dart
dart run drift_dev make-migrations   # does both, plus a migration test scaffold
```

Never test a migration by reinstalling the app: a fresh install runs `onCreate` and ignores every
`onUpgrade` branch, so the broken path is exactly the one you did not exercise.

```dart
// test/migration_test.dart. Generate the helper with:
// dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
late SchemaVerifier verifier;
setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

test('upgrade from v1 to v3 keeps data', () async {
  await verifier.migrateAndValidate(AppDatabase(await verifier.startAt(1)), 3);
});
```

## Converters, enums and dates

`DateTime` is stored as seconds since the epoch unless you configure otherwise. The instant survives;
the time zone you read back is yours to handle, so normalize at the boundary (write
`DateTime.now().toUtc()`, convert for display with the active locale).

```yaml
# build.yaml - ISO-8601 text instead of unix seconds (pick one; changing later rewrites rows)
targets: {$default: {builders: {drift_dev: {options: {store_date_time_values_as_text: true}}}}}
```

```dart
// WRONG: a stringly typed date column nobody can sort or constrain
final bad = '${now.year}-${now.month}-${now.day}'; // "2026-9-1" sorts after "2026-10-1"

// RIGHT: an explicit converter when the stored form must be stable
class DurationConverter extends TypeConverter<Duration, int> {
  const DurationConverter();
  @override
  int toSql(Duration value) => value.inMilliseconds;
  @override
  Duration fromSql(int fromDb) => Duration(milliseconds: fromDb);
}
// on the table: IntColumn get timeout => integer().map(const DurationConverter())();
```

- `TypeConverter<D, S>` maps Dart `D` to stored `S` via `toSql` / `fromSql`: use it for enums with names
  you control, `Duration`, and dates that must stay readable in a SQL browser. Never store money in a
  `REAL` column (integers in minor units), and remember a converter is not applied to a generated data
  class's `toJson`, so wire conversion stays explicit.

## Tests

`NativeDatabase.memory()` is the standard test executor: no files, no path_provider, no platform
channel. Always `close()` in `tearDown` or the next test inherits its state. In a `watch()` test,
subscribe first, write, then `await pumpEventQueue()` before asserting.

```dart
setUp(() => db = AppDatabase(NativeDatabase.memory()));
tearDown(() => db.close());
```

## Common mistakes

| Mistake | Symptom |
|---|---|
| Editing `database.g.dart` | Changes vanish on the next build; the fix belongs in the table class |
| Forgetting `build_runner watch` | "The getter 'x' isn't defined" and missing `database.g.dart` errors |
| Bumping `schemaVersion` with no `onUpgrade` | "no such column" on launch, for existing installs only |
| Testing migrations by reinstalling | `onCreate` runs and `onUpgrade` never does, so the bug ships |
| Queries on the UI isolate (`NativeDatabase(...)` in app code) | Frame drops proportional to query size |
| Storing dates as formatted strings | Wrong sort order, no range queries, unparseable rows |
