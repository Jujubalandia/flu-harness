---
description: freezed and json_serializable - part directives, const factory models, defaults, nested JSON wiring, enum fallbacks, copyWith null semantics and the sentinel pattern, sealed unions, codegen and generated-file policy.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# freezed + json_serializable

Target: freezed 4.0.x with `freezed_annotation` 3.1.x (pinned exactly by freezed 4), json_serializable
6.x, build_runner 2.16.x, Dart 3.13+. freezed 4 needs Dart 3.13, where `final` is no longer legal in an
ordinary constructor parameter list, so write `required String id`, not `required final String id`.
freezed generates `==`, `hashCode`, `toString`, `copyWith` and the JSON plumbing; json_serializable
generates the JSON body. Two builders over one file: hence two `part` files.

## The shape of a model

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String name,
    @Default(0) int score,
    DateTime? deletedAt,
  }) = _User;
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

- Both `part` directives are required; freezed does not merge its output into `.g.dart`. Use
  `abstract class` for a single-constructor model and `sealed class` for several (see unions). `_User`
  is the generated implementation: private, never referenced by hand. `const factory` is what freezed
  replaces, so do not also write a normal constructor.
- Required fields are `required` and non-nullable; anything the server may omit is nullable or has
  `@Default(...)`. A `@Default` on a nullable field is a smell: `null` and "missing" become
  indistinguishable. Defaults must be compile-time constants, so `@Default(DateTime.now())` fails.
- One model per file: freezed emits one `.freezed.dart` per source, so a 500-line `models.dart` turns
  into a generated file nobody can review.

## Codegen

```bash
dart run build_runner build --delete-conflicting-outputs   # after every model edit
dart run build_runner watch --delete-conflicting-outputs   # while editing
```

- Missing codegen reads as "Target of URI doesn't exist: 'user.freezed.dart'", "The method
  '_$UserFromJson' isn't defined", or as a new field that is always null.
- Never edit `*.freezed.dart` or `*.g.dart`: build_runner 2.16.x silently rewrites hand edits, so a
  manual fix works until the next build and then disappears. `--delete-conflicting-outputs` is a no-op
  since build_runner 2.7; in CI use the write-nothing check mode instead.
- Commit the generated files: a fresh clone must compile before anyone runs build_runner.

## Nested models and JSON keys

A nested model is emitted as a Dart object unless json_serializable is told to recurse: `toJson()`
returns `{'address': Instance of 'Address'}`, which survives `jsonEncode` only by accident.

```yaml
# build.yaml - applies to every @freezed model that has a fromJson
targets: {$default: {builders: {json_serializable: {options: {explicit_to_json: true}}}}}
```

```dart
@freezed
abstract class Order with _$Order {
  const factory Order({
    required String id,
    required Address address,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Order;
  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
}
```

- Pin wire names with `@JsonKey(name: 'created_at')` rather than renaming Dart fields to a database
  convention. `@JsonKey(ignore: true)` is deprecated: use `includeFromJson: false` and
  `includeToJson: false`.
- For a transform use `@JsonKey(fromJson:, toJson:)` and make the two round-trip. Never put an SDK
  object (a Firestore `Timestamp`, a Supabase map) in a model field: convert inside `fromJson`.

## Enums: the fallback member is mandatory

An unknown value from the server is normal: your v1.2 client is talking to a v1.3 backend. Without a
fallback `$enumDecode` throws `ArgumentError` in `fromJson`, so one new status kills the screen.

```dart
// WRONG: enum ItemStatus { draft, live } - a new server value throws while parsing
// RIGHT: explicit wire values plus a fallback member
enum ItemStatus {
  @JsonValue('draft') draft,
  @JsonValue('live') live,
  @JsonValue('unknown') unknown,
}

@freezed
abstract class Item with _$Item {
  const factory Item({
    required String id,
    @JsonKey(unknownEnumValue: ItemStatus.unknown) required ItemStatus status,
  }) = _Item;
  factory Item.fromJson(Map<String, dynamic> json) => _$ItemFromJson(json);
}
```

- `@JsonValue('...')` pins the wire value (String or int). Without it the Dart member name is used, so
  renaming a member is a breaking API change.
- `@JsonKey(unknownEnumValue: ...)` is what makes the fallback work; the enum member alone does not. For
  a nullable field, `JsonKey.nullForUndefinedEnumValue` is the alternative; `@JsonEnum(valueField:
  'wire')` fits an enum that already carries its wire value in a field. Render `unknown` as a real
  state, not a blank chip: it tells you a rollout is half-finished.

## copyWith and null: the truth, and the sentinel

freezed's generated `copyWith` differs by nullability. For
`const factory User({required String name, DateTime? deletedAt}) = _User;` it is equivalent to:

```dart
_$UserImpl copyWith({Object? name = null, Object? deletedAt = freezed}) {
  return _$UserImpl(
    name: null == name ? this.name : name as String,
    deletedAt: freezed == deletedAt ? this.deletedAt : deletedAt as DateTime?,
  );
}
```

- **Nullable field: clearing works.** `user.copyWith(deletedAt: null)` sets it to null, because the
  default is the library-private `freezed` sentinel and an explicit `null` is not equal to it. The
  often-repeated "freezed's copyWith cannot set null" is wrong for freezed 2.3 and later.
- **Non-nullable field: passing null silently does nothing.** Its parameter is `Object?` defaulting to
  `null`, and the body tests `null == name`, so `copyWith(name: null)` compiles, changes nothing and
  returns an equal object: the archetypal "my copyWith is not applied" bug, where the null came from a
  nullable variable nobody checked.
- When "absent" and "explicitly null" must differ in your own API (a PATCH payload, a filter builder, a
  hand-written `copyWith`), the sentinel is your job:

```dart
const Object _unset = Object();

class ProfilePatch {
  const ProfilePatch({Object? name = _unset, Object? bio = _unset})
      : _name = name,
        _bio = bio;
  final Object? _name;
  final Object? _bio;

  Map<String, dynamic> toJson() => {
        if (!identical(_name, _unset)) 'name': _name,
        if (!identical(_bio, _unset)) 'bio': _bio, // present and null vs absent
      };
}
```

- Collections are wrapped in unmodifiable views, so `user.copyWith(tags: [...user.tags, 'new'])` is how
  you add. Never mutate in place. `@Freezed(copyWith: false)` disables copyWith generation.

## Equality and toString

`==`, `hashCode` and `toString` are generated and compare structurally, including nested freezed models
and collections: two separately built `User(id: '1', name: 'a')` are equal, and writing your own `==`
breaks `Set`, `Map` keys and every provider that compares previous state. `toString()` prints every
field, so never log a model that carries a session token.

## Unions and sealed classes

```dart
// WRONG: nullable flags pretending to be a state machine (data + loading + error)
// RIGHT: a sealed union, exhaustive at compile time
@freezed
sealed class LoadState with _$LoadState {
  const factory LoadState.loading() = LoadStateLoading;
  const factory LoadState.data(List<Item> items) = LoadStateData;
  const factory LoadState.error(String message) = LoadStateError;
}
```

```dart
final label = switch (state) {
  LoadStateLoading() => 'loading',
  LoadStateData(:final items) => '${items.length} items',
  LoadStateError(:final message) => message,
};
```

With `sealed`, adding a case turns every non-exhaustive `switch` into a compile error: an impossible
state becomes unrepresentable. `when` and `map` still exist in freezed 4 (removed in 3.0.0, restored in
3.1.0) but are documented as legacy, so use Dart 3 `switch` expressions in new code. Use unions for
state, not for JSON polymorphism: deserializing a union needs a discriminator and an explicit factory.

## The invalid_annotation_target warning

json_serializable's analyzer sees `@JsonKey`/`@Default` on parameters it does not consider annotation
targets and reports `invalid_annotation_target`: a false positive in every freezed model.

```yaml
# analysis_options.yaml
analyzer:
  errors:
    invalid_annotation_target: ignore
```

Do not silence it per use site with `// ignore:`; the project-level switch is the prescribed fix.

## Common mistakes

| Mistake | Symptom |
|---|---|
| Editing `*.freezed.dart` by hand | The change works until the next build, then silently reverts |
| Not running build_runner / no `--delete-conflicting-outputs` | "isn't defined" errors on `_$ModelFromJson`, or new fields always null |
| `copyWith(field: null)` on a non-nullable field | Nothing happens and no error: an unchecked null was passed |
| Building a PATCH body with `copyWith` | Cleared fields are omitted, or stale values are sent |
| Missing `explicitToJson: true` with a nested model | `toJson()` returns `Instance of 'Address'`; encoding fails or sends `{}` |
| Enum without `unknownEnumValue` | `ArgumentError` in `fromJson` the first time the server adds a value |
| `@Default(DateTime.now())` | Compile error: defaults must be constant |
| Hand-written `==` on a freezed class | Duplicate set/map entries, missed or spurious state notifications |
