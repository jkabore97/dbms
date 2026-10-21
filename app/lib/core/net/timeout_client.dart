import 'dart:async';

import 'package:http/http.dart' as http;

/// One time limit for every call the app makes to Supabase — PostgREST
/// reads and RPCs, auth, the rare storage or functions call — given to
/// `Supabase.initialize(httpClient: …)` in main.dart.
///
/// On a market's line a request can go out and no answer ever come back.
/// Before this, every action that needs the server (an invoice, a credit
/// repayment, a stock receipt, a harvest, a herd event, filing a receipt
/// photo) waited on such a request for as long as the socket lived — the
/// button spun with nothing the person could do but close the app. Bounded
/// here, the call fails with a [RequestTimedOut], which `describeError`
/// already reads as « Pas de connexion. Réessayez quand le réseau revient. »
/// and `isOffline` as the transport failing (the till's outbox keeps the
/// sale).
///
/// The bound is how long the line may stay silent, not how long a whole
/// exchange may take: [timeout] for the answer's first byte, then again
/// between any two pieces of the answer, so a long list arriving slowly
/// is never cut while it is still arriving. A request carrying a large
/// body (an upload) gets [uploadTimeout] for its answer instead, because
/// sending the body is part of that wait. Photographs do not come through
/// here at all — they go to the upload Worker on CaptureRepository's own
/// client — and the realtime websocket is not an http request; neither is
/// touched.
///
/// Screens that already stop waiting sooner (the till's 20 s, the homes'
/// 12 s, sign-in's 8 s) keep doing so: their own `.timeout` fires first.
///
/// A read whose line failed is not tried again ([LineDown]). PostgREST
/// retries a failed GET three times with 1 + 2 + 4 s between, so with no
/// signal at all every `.select()` — the till's shelf, an association's
/// members, a farm's day, the bell, a profile — took seven seconds to say
/// so, and a stalled one more than a minute, before the screen fell back on
/// the phone's own copy. Measured: an offline read failed after 7020 ms in
/// 4 tries; now at once, in 1. (Its `retryEnabled` option cannot say this:
/// supabase 2.16's `from()` builds its query without the client's retry
/// options.) PostgREST still asks a read again when the server answers
/// « busy » (503, 520): that is an answer, not a dead line.
///
/// [bounded] is this policy for the clients that talk to the Workers
/// (photos, Wave, the account Worker, a courier's files, push): before it
/// they used a bare `http.Client()` with no bound at all, so a stalled
/// upload or payment kept its button spinning for as long as the socket
/// lived.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(
    this._inner, {
    this.timeout = defaultTimeout,
    this.uploadTimeout = defaultUploadTimeout,
    this.retryTimeout = defaultRetryTimeout,
  });

  /// A plain client under the app's one time limit: the default for every
  /// repository that makes its own requests (the Workers).
  static http.Client bounded() => TimeoutClient(http.Client());

  final http.Client _inner;

  /// Silence allowed before the answer starts, and between its pieces.
  final Duration timeout;

  /// The wait for the answer to a request with a large body.
  final Duration uploadTimeout;

  /// The wait for PostgREST's own second, third and fourth try at a read
  /// (it retries a GET that failed, marking it `X-Retry-Count`): a line
  /// that just stayed silent for [timeout] is not given that long again,
  /// so a stalled read ends in about a minute rather than two.
  final Duration retryTimeout;

  /// Supabase's own statement timeout is 8 s for a signed-in caller; 30 s
  /// is well past any honest answer and short enough that somebody is
  /// still holding the phone when the sentence appears.
  static const defaultTimeout = Duration(seconds: 30);
  static const defaultUploadTimeout = Duration(minutes: 3);
  static const defaultRetryTimeout = Duration(seconds: 10);

  /// A body larger than this is an upload: its sending counts in the wait.
  static const largeBody = 256 * 1024;

  /// The wait allowed for [request]'s answer to start.
  Duration boundFor(http.BaseRequest request) {
    final length = request.contentLength ??
        (request is http.Request ? request.bodyBytes.length : null);
    final upload = request is http.MultipartRequest ||
        (request is http.StreamedRequest && length == null) ||
        (length ?? 0) > largeBody;
    if (upload) return uploadTimeout;
    if (request.headers.containsKey('X-Retry-Count') && retryTimeout < timeout) {
      return retryTimeout;
    }
    return timeout;
  }

  /// Whether a failure of [request]'s line is said as a [LineDown]: a read,
  /// the only kind PostgREST asks again.
  static bool _read(http.BaseRequest request) =>
      request.method == 'GET' || request.method == 'HEAD';

  /// [error] as it leaves here: for a read, a line that failed (no signal,
  /// a stall past the bound) becomes a [LineDown], which PostgREST does not
  /// retry. A caller's own abort, and anything that is not the line, stay
  /// as they are.
  static Object _outgoing(http.BaseRequest request, Object error) =>
      _read(request) && error is Exception && error is! http.RequestAbortedException
          ? LineDown(error, request.url)
          : error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _send(request);
    } catch (error, stack) {
      Error.throwWithStackTrace(_outgoing(request, error), stack);
    }
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    final bound = boundFor(request);
    final stalled = Completer<void>();
    Timer? timer;
    var timedOut = false;
    void arm(Duration d) {
      timer?.cancel();
      timer = Timer(d, () {
        timedOut = true;
        if (!stalled.isCompleted) stalled.complete();
      });
    }

    RequestTimedOut timedOutError() => RequestTimedOut(request.url, bound);

    arm(bound);
    final outgoing = _abortable(request, stalled.future);
    final answered = Completer<http.StreamedResponse>();
    _inner.send(outgoing).then((response) {
      if (answered.isCompleted) {
        // Too late: nobody is waiting any more. Let the connection go.
        unawaited(response.stream.listen(null).cancel());
      } else {
        answered.complete(response);
      }
    }, onError: (Object error, StackTrace stack) {
      if (answered.isCompleted) return;
      if (timedOut && error is http.RequestAbortedException) {
        answered.completeError(timedOutError(), stack);
      } else {
        answered.completeError(error, stack);
      }
    });
    // A client that cannot abort (or is slow to) still gives up on time.
    unawaited(stalled.future.then((_) {
      if (!answered.isCompleted) answered.completeError(timedOutError());
    }));

    final http.StreamedResponse response;
    try {
      response = await answered.future;
    } catch (_) {
      timer?.cancel();
      rethrow;
    }

    // The answer has started: from here the bound is silence between its
    // pieces.
    arm(timeout);
    late final StreamController<List<int>> body;
    StreamSubscription<List<int>>? sub;
    var closed = false;
    void fail(Object error, [StackTrace? stack]) {
      if (closed) return;
      closed = true;
      timer?.cancel();
      body.addError(_outgoing(request, error), stack);
      unawaited(body.close());
      unawaited(sub?.cancel());
    }

    unawaited(stalled.future.then((_) => fail(RequestTimedOut(request.url, timeout))));
    body = StreamController<List<int>>(
      onListen: () {
        sub = response.stream.listen(
          (chunk) {
            if (closed) return;
            arm(timeout);
            body.add(chunk);
          },
          onError: (Object error, StackTrace stack) => fail(
              timedOut && error is http.RequestAbortedException
                  ? RequestTimedOut(request.url, timeout)
                  : error,
              stack),
          onDone: () {
            if (closed) return;
            closed = true;
            timer?.cancel();
            unawaited(body.close());
          },
          cancelOnError: true,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        closed = true;
        timer?.cancel();
        return sub?.cancel();
      },
    );

    return http.StreamedResponse(
      body.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// [request], as one the inner client stops when [stalled] completes, so
  /// a stalled socket (or the browser's fetch) is actually let go rather
  /// than left open. Only a plain [http.Request] — what PostgREST, auth and
  /// functions send — can be copied; anything else is sent as it is and
  /// the wait still ends on time.
  http.BaseRequest _abortable(http.BaseRequest request, Future<void> stalled) {
    if (request is! http.Request || request.finalized) return request;
    final own = request is http.Abortable
        ? (request as http.Abortable).abortTrigger
        : null;
    final copy = http.AbortableRequest(
      request.method,
      request.url,
      abortTrigger: own == null ? stalled : Future.any([own, stalled]),
    )
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    final bytes = request.bodyBytes;
    if (bytes.isNotEmpty) copy.bodyBytes = bytes;
    return copy;
  }

  @override
  void close() => _inner.close();
}

/// A read whose line failed — [cause] is what failed: no signal (a
/// SocketException, the browser's ClientException) or a [RequestTimedOut].
///
/// A [http.RequestAbortedException], on purpose: it is the one failure
/// PostgREST gives back at once instead of asking again (1 + 2 + 4 s of
/// waiting on a line that is not there). It reads as its cause, so
/// `describeError` and `isOffline` say « Pas de connexion » as before.
class LineDown extends http.RequestAbortedException {
  LineDown(this.cause, [Uri? uri]) : super(uri);

  final Object cause;

  @override
  String toString() => '$cause';
}

/// The line stayed silent past the bound. A [TimeoutException], so
/// `describeError` and `isOffline` (core/errors.dart) read it as the
/// transport failing — « Pas de connexion » — like every other timeout.
class RequestTimedOut extends TimeoutException {
  RequestTimedOut(this.url, Duration bound)
      : super('No answer from the server', bound);

  final Uri url;
}
