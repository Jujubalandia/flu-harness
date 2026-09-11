---
description: dio 5.x rules for one configured client, interceptors, token refresh, cancellation, typed errors and retry in Flutter apps.
globs: ["**/*.dart", "lib/**/*.dart"]
alwaysApply: false
---

# dio 5.x

Target `dio` 5.11.x. `DioError` is a deprecated alias for `DioException`, removed in dio 6:
never write it. Cancellation is checked with `CancelToken.isCancel(error)`.

## One client per API surface

```dart
Dio buildApiDio({required TokenStore tokens, required Future<String?> Function() refresh}) {
  final dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL'), // --dart-define, never source
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 20),
  ));
  dio.interceptors.addAll([
    AuthInterceptor(dio, tokens, refresh), // QueuedInterceptor: one refresh, not N
    RetryInterceptor(dio), // idempotent methods only
    if (kDebugMode) RedactingLogInterceptor(),
  ]);
  return dio;
}

final dioProvider = Provider<Dio>((ref) => buildApiDio(...)); // one instance, injected
```

```dart
// WRONG: a new client per call: no baseUrl, no timeouts, no interceptors, no reuse.
final res = await Dio().get('/songs');

// RIGHT: inject the one configured client; a repository never builds its own.
final res = await _dio.get('/songs', cancelToken: cancelToken);
```

Symptom of the wrong version: a TLS handshake per request (2-5x latency), no token
attached, no timeout so a dead network hangs forever. Names mislead: `connectTimeout` is
the connection, `sendTimeout` the WHOLE body upload, `receiveTimeout` a gap timer BETWEEN
byte events rather than a total deadline. dio core has no total deadline: use
`Future.timeout()` or a `CancelToken`. All three default to `null`: no timeout at all.

## Interceptors

Every callback must call EXACTLY ONE of `handler.next`, `handler.resolve`,
`handler.reject`: none hangs the request forever, two throws `StateError`.

```dart
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._dio, this._tokens, this._refresh);
  final Dio _dio;
  final TokenStore _tokens;
  final Future<String?> Function() _refresh; // uses a SEPARATE bare Dio

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options); // exactly one call, on every path
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final unauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    if (!unauthorized || alreadyRetried) return handler.next(err);
    try {
      final fresh = await _refresh(); // queued: concurrent 401s trigger ONE refresh
      if (fresh == null) return handler.next(err); // refresh failed: surface the 401
      final options = err.requestOptions
        ..extra['retried'] = true
        ..headers['Authorization'] = 'Bearer $fresh';
      handler.resolve(await _dio.fetch(options));
    } on Object {
      handler.next(err); // never let a refresh error escape the interceptor
    }
  }
}
```

- `QueuedInterceptor` runs callbacks one at a time; a plain `Interceptor` runs them at
  once, so N parallel 401s start N refreshes and the losers clobber the winner.
- The refresh call must NOT go through this chain, or a failing refresh 401s forever.
  Give `_refresh` its own `Dio` with no auth interceptor.
- `extra['retried']` is the loop breaker: keep it a bool.
- `_dio.fetch(options)` re-runs the chain including `onRequest`, so logging fires twice.
- Logging: redact `authorization`, `cookie`, `x-api-key`; debug-only (`kDebugMode`).

## Cancellation

```dart
final _cancel = CancelToken();

@override
void dispose() {
  _cancel.cancel('screen disposed'); // in-flight calls fail with type cancel
  super.dispose();
}
```

Check cancellation before writing back: `on DioException catch (e)` then
`if (CancelToken.isCancel(e) || !mounted) return;`. Without a token a slow request
outlives its screen (`setState() called after dispose()`, or a write to a disposed
provider). One token per screen or logical operation; not reusable after `cancel()`.

## Typed errors, mapped once

Never let a `DioException` reach the UI. Map it at the data-layer boundary:

```dart
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
}

final class NetworkFailure extends AppFailure { const NetworkFailure(super.message); }
final class TimeoutFailure extends AppFailure { const TimeoutFailure(super.message); }
final class UnauthorizedFailure extends AppFailure { const UnauthorizedFailure(super.message); }
final class CancelledFailure extends AppFailure { const CancelledFailure() : super('cancelled'); }
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, this.statusCode);
  final int? statusCode;
}

AppFailure mapDioException(DioException e) {
  final status = e.response?.statusCode;
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => TimeoutFailure(e.message ?? 'Request timed out'),
    DioExceptionType.cancel => const CancelledFailure(),
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate => const NetworkFailure('No connection'),
    DioExceptionType.badResponse when status == 401 => const UnauthorizedFailure('Session expired'),
    DioExceptionType.badResponse when status != null && status >= 500 =>
      ServerFailure('Server error', status),
    DioExceptionType.badResponse => ServerFailure('Request failed', status),
    // transformTimeout exists in dio >= 5.11; drop this arm on an older minor.
    DioExceptionType.unknown ||
    DioExceptionType.transformTimeout => NetworkFailure(e.message ?? 'Unknown error'),
  };
}
```

The switch is exhaustive over `DioExceptionType`, so an upgrade that adds a case breaks the
build instead of collapsing to `unknown`. Two defaults bite everyone: `validateStatus`
accepts 2xx only, so any 3xx/4xx/5xx throws `badResponse` (pass
`Options(validateStatus: (s) => s != null && s < 500)` when the API treats 409 as success),
and `receiveDataWhenStatusError` defaults to true, so on an HTTP error `e.response?.data`
IS populated: read the server's message or validation map instead of assuming null.

## Repository boundary

```dart
Future<Result<List<Song>, AppFailure>> fetchAll({CancelToken? cancelToken}) async {
  try {
    final res = await _dio.get<List<dynamic>>('/songs', cancelToken: cancelToken);
    return Ok(res.data!.map(Song.fromJson).toList(growable: false));
  } on DioException catch (e) {
    return Err(mapDioException(e)); // the UI never sees a DioException
  }
}
```

- Catch `DioException`, never bare `Exception`: a bare catch swallows `StateError` and
  `TypeError`, so your own bugs ship as "network error".
- The widget consumes the `Result` and never catches: `case Ok(:final value)` renders,
  `case Err(:final error)` shows `error.message`.
- A dio call in `build()` fires on every rebuild (every keystroke, theme change, hot
  reload) and cannot be cancelled. Repository plus state holder, always.

## Retry with backoff

Retry is not in dio core; `dio_smart_retry` is dormant and re-runs `onRequest`. Roll it
yourself, idempotent methods only:

```dart
final attempt = (err.requestOptions.extra['attempt'] as int?) ?? 0;
final status = err.response?.statusCode;
final retryable = _idempotent.contains(err.requestOptions.method) &&
    (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (status != null && status >= 500));
if (!retryable || attempt >= maxAttempts) return handler.next(err);
await Future<void>.delayed(Duration(milliseconds: 200 * (1 << attempt)));
handler.resolve(await _dio.fetch(err.requestOptions..extra['attempt'] = attempt + 1));
```

Never retry a non-idempotent POST blindly (double charges, duplicate rows), and never
retry 401 here: that is the auth interceptor's job, and both retrying one request at once
is how you get a storm.

## Uploads

```dart
final form = FormData.fromMap({
  'title': title,
  'file': await MultipartFile.fromFile(filePath, filename: p.basename(filePath)),
});
await dio.post<void>('/uploads', data: form, cancelToken: cancelToken,
    onSendProgress: (sent, total) => onProgress(total == 0 ? 0 : sent / total));
```

Do not set `Content-Type` by hand for multipart: dio adds the boundary, and a manual
`application/json` header produces "malformed multipart body" on the server.

## Common mistakes

| Mistake | Symptom |
|---|---|
| `Dio()` created per call | no connection reuse, extra TLS handshakes, interceptors and timeouts silently absent |
| An interceptor path that never calls the handler | the request hangs forever (default timeouts are null) |
| Refresh call routed through the refresh interceptor | infinite 401 loop, request storm, battery drain, log spam |
| No `cancelToken` | `setState() called after dispose()`, writes to a disposed provider |
| Assuming `e.response?.data` is null on 4xx | server validation messages thrown away, generic "something went wrong" |

