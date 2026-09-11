---
description: go_router rules for route tables, nested shells, auth redirects, typed routes, deep links and back-stack behaviour in Flutter.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# go_router

Target: `go_router` 17.5.x with `package:flutter/material.dart`. Do NOT move to 18.x
until the app migrates to `material_ui` / `cupertino_ui`: 18.0.0 exists mainly to make
that switch and hard-depends on both packages. `go_router_builder` 4.5.x is the matching
codegen package; typed routes need `build_runner` and `build_verify`.

## Router setup: exactly one instance

```dart
// lib/app/router.dart
final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/songs',
  debugLogDiagnostics: kDebugMode,
  redirectLimit: 5, // default; exceeding it renders the error screen
  refreshListenable: authRefresh, // a Listenable, see "Auth guards"
  redirect: authRedirect,
  errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
  onException: (context, state, router) => log('nav error: ${state.error}'),
  routes: [signInRoute, songListRoute, songDetailRoute, profileRoute], // see below
);

// lib/main.dart: MaterialApp.router(routerConfig: appRouter)
```

```dart
// WRONG: a new router per rebuild; every theme or locale change resets the stack.
Widget build(BuildContext context) =>
    MaterialApp.router(routerConfig: GoRouter(routes: routes));

// RIGHT: one router for the process lifetime: a top-level final or keepAlive provider.
```

## builder vs pageBuilder

`builder` wraps your widget in the default platform page and is fine for most screens.
`pageBuilder` returns a `Page` and is required for custom transitions, named pages, a page
`key` (`state.pageKey`), and for `StatefulShellRoute` state restoration. `errorBuilder`
renders the widget for an unmatched or failed location (`errorPageBuilder` for a page), and
`onException` observes the same failures, with `state.error` typed as `GoException?`.

## Path, query, extra

- Path parameters are the identity of a resource: required, always present after a deep
  link or a browser refresh. `state.pathParameters['id']`.
- Query parameters are optional/shareable filters: `state.uri.queryParameters['q']`.
  Preserve them when redirecting or the back button loses the user's filters.
- `extra` is `Object?` and lives in memory only. It is LOST on a deep link, on browser
  refresh, and after process death. `extraCodec` can encode it into the URL, but the
  default does not.

```dart
// WRONG: the object is gone after the OS kills the app and restores the link.
context.push('/songs/42', extra: song);

// RIGHT: the URL carries identity; the screen loads data from a provider or cache.
context.push('/songs/${song.id}');
final id = int.tryParse(state.pathParameters['id'] ?? ''); // links are untrusted input
if (id == null) return const NotFoundScreen(location: '/songs');
```

## Nested routes and shells

- Child paths are relative: `':id'`, never `'/songs/:id'`. A leading slash makes the
  route absolute and it stops matching under its parent.
- `parentNavigatorKey: _rootKey` pushes a route above the shell (a full-screen checkout
  over the bottom bar) instead of inside the current tab.
- `ShellRoute` shares ONE inner `Navigator`, so tab state and scroll position are lost on
  every switch. Use `StatefulShellRoute.indexedStack` when tabs must keep their stacks.
- Each `StatefulShellBranch` needs its OWN `navigatorKey`, and tabs are switched with
  `navigationShell.goBranch`, never with `context.go`.

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      ScaffoldWithNavBar(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(navigatorKey: _songsTabKey, routes: [
      GoRoute(path: '/songs', builder: (context, state) => const SongListScreen()),
    ]),
    StatefulShellBranch(navigatorKey: _profileTabKey, routes: [
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
    ]),
  ],
)

// NavigationBar: navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex)
```

```dart
// WRONG: does not restore the target branch's history and poisons the back stack.
context.go('/profile');
```

`indexedStack` builds every branch eagerly. For an expensive tab use a custom
`navigatorContainerBuilder` so it stays lazy. Tab state is in memory only: surviving
process death needs all four of router `restorationScopeId`, `MaterialApp.router`
`restorationScopeId`, a `pageBuilder` whose page has a `restorationId`, and a
`restorationScopeId` per branch.

## Auth guards

The guard belongs in ONE place. Read auth state with `ref.read` inside the redirect
(never `ref.watch` in the widget that builds the router), and let a `Listenable` tell the
router when to re-evaluate.

```dart
class AuthRefresh extends ChangeNotifier {
  AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if ((previous is SignedIn) != (next is SignedIn)) notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(authProvider) is SignedIn; // read, never watch
      final atSignIn = state.matchedLocation == '/sign-in';
      if (!signedIn) return atSignIn ? null : '/sign-in'; // null = allow
      return atSignIn ? '/songs' : null; // returning the current location loops
    },
    routes: routes,
  );
});
```

- Async redirects are supported (`GoRouterRedirect` returns `FutureOr<String?>`), but keep
  them short and never call `context`-dependent APIs without the Zone support added in
  16.2.5. Prefer reading from the DI container.
- `redirectLimit` defaults to 5; a loop ends on the error screen, not in a crash, so the
  symptom is "the app opens on a blank error page".
- go_router 16.3+ adds top-level `onEnter`, evaluated once per navigation BEFORE the
  legacy `redirect`: return `const Allow()` or `const Block.stop()` (a hard stop that
  resets redirect history). Use `Block.then(...)` only when you want the callback to run
  after the navigation commits. `BlockedInitialNavigationException` (17.4+) is a
  `GoException` subtype you can match in `onException`.
- While auth state is unknown (cold start, token refresh in flight), render a splash from
  the guard instead of redirecting to `/sign-in`: otherwise every launch flashes the
  sign-in screen and then bounces.

## Reading state, and typed routes

`GoRouterState.of(context)` still exists in a screen; `state` from the builder is
preferable. Public fields: `uri`, `matchedLocation`, `name`, `path`, `fullPath`,
`pathParameters`, `extra`, `error`, `pageKey`.

```dart
@TypedGoRoute<SongRoute>(path: '/songs/:id')
class SongRoute extends GoRouteData with $SongRoute { // $SongRoute, NOT _$SongRoute
  const SongRoute({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, GoRouterState state) => SongScreen(id: id);
}

final $appRoutes = <RouteBase>[SongRoute()]; // referenced by `routes: $appRoutes`
const SongRoute(id: '42').go(context); // or .push<String>(context)
```

Requires `go_router_builder`, `part 'song_routes.g.dart';`, and `dart run build_runner
build`. The mixin has been public (`$SongRoute`) since builder 4.0.0; the older `_$Route`
form in some docs is stale. Path parameters become typed constructor fields (int, enum,
extension types); `extra` stays untyped and still breaks deep links.

## Navigation verbs

| Call | Effect |
|---|---|
| `context.go(loc)` | replaces the stack with what `loc` matches; tabs, deep links, post-logout |
| `context.push<T>(loc)` | pushes on top, back stack intact; returns `Future<T?>` |
| `context.pushReplacement(loc)` | replaces the top route; back returns to the one below |
| `context.pop<T>(result)` | pops the current route (the branch navigator inside a shell) |

```dart
// Caller: a pushed route returns a value through pop(). null = user backed out.
final picked = await context.push<Song>('/songs/pick');
if (!context.mounted || picked == null) return;
setState(() => _selected = picked);
// Picker: context.pop(_selected);
```

## Deep links

- Android: `autoVerify="true"` on an https intent filter plus `/.well-known/assetlinks.json`
  whose SHA-256 fingerprint comes from Play Console -> App integrity. Play App Signing
  re-signs, so a local upload-key fingerprint is the top broken-deep-link cause.
- iOS: `apple-app-site-association` as `application/json`, no redirects, no auth, plus the
  Associated Domains capability (`applinks:example.com`).
- `flutter_deeplinking_enabled` defaults to true since Flutter 3.27: leave it unset with
  go_router; set it false only when another plugin owns the link.
- `initialLocation` is the fallback for a normal launch only: make it a route the guard
  allows, or the first frame lands somewhere that immediately redirects.

## Common mistakes

| Mistake | Symptom |
|---|---|
| `redirect` returns the location it is already on | redirect loop, error page after 5 hops, blank screen on launch |
| Guard reads auth via `ref.watch` in the widget that builds the router | new router on every auth change: stack reset, mid-navigation jumps |
| Data passed via `extra` that must survive a cold start | `state.extra` is null after backgrounding/refresh, then `!` throws |
| Router built inside `build()` | navigation resets on theme, locale, or keyboard changes |
| `context.go` used for tab switches | tab history lost, Android back exits the app or jumps tabs |
| `ShellRoute` used where tab state must persist | tabs rebuild and scroll position resets |
| Child route path starts with `/` | route never matches under its parent, unexpected 404 page |
| `Navigator.pop(context)` instead of `context.pop()` inside a shell | pops the wrong navigator, or does nothing |

