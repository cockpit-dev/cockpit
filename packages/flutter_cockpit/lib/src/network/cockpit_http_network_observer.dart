import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cockpit_network_entry.dart';
import 'cockpit_network_endpoint_summary.dart';
import 'cockpit_network_observer.dart';
import 'cockpit_network_query.dart';
import 'cockpit_network_snapshot.dart';
import 'cockpit_web_socket_frame_decoder.dart';

typedef CockpitNetworkTickHandler = Future<void> Function(Duration duration);
typedef CockpitNetworkCaptureFilter = bool Function(String method, Uri uri);

final class CockpitHttpNetworkObserver extends HttpOverrides
    implements CockpitNetworkObserver {
  CockpitHttpNetworkObserver({
    this.maxRetainedEntries = 200,
    this.maxHeaderCount = 24,
    this.maxHeaderValueLength = 256,
    this.maxBodyBytes = 4096,
    this.captureHeaders = true,
    this.captureBodies = true,
    this.redact = true,
    this.maxWebSocketFrames = 24,
    this.maxWebSocketPreviewBytes = 1024,
    this.captureFilter,
    CockpitNetworkTickHandler? tickHandler,
  }) : _tickHandler = tickHandler ?? _defaultTickHandler;

  final int maxRetainedEntries;
  final int maxHeaderCount;
  final int maxHeaderValueLength;
  final int maxBodyBytes;
  final bool captureHeaders;
  final bool captureBodies;
  final bool redact;
  final int maxWebSocketFrames;
  final int maxWebSocketPreviewBytes;
  final CockpitNetworkCaptureFilter? captureFilter;
  final CockpitNetworkTickHandler _tickHandler;
  static const CockpitNetworkRedactor _redactor = CockpitNetworkRedactor();

  final ListQueue<CockpitNetworkEntry> _entries =
      ListQueue<CockpitNetworkEntry>();
  final LinkedHashMap<String, _CockpitPendingNetworkRecord> _pending =
      LinkedHashMap<String, _CockpitPendingNetworkRecord>();
  HttpOverrides? _parentOverrides;
  bool _parentOverridesLocked = false;
  int _requestCounter = 0;
  int _inFlightCount = 0;
  DateTime? _lastActivityAt;

  void attachParentOverrides(HttpOverrides? overrides) {
    _parentOverrides = overrides;
    _parentOverridesLocked = true;
  }

  bool get hasAttachedParentOverrides => _parentOverridesLocked;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final delegate =
        _parentOverrides?.createHttpClient(context) ??
        super.createHttpClient(context);
    return _CockpitObservedHttpClient(delegate, observer: this);
  }

  @override
  CockpitNetworkSnapshot snapshot({
    int maxEntries = 10,
    CockpitNetworkQuery query = const CockpitNetworkQuery(),
  }) {
    final allEntries = <CockpitNetworkEntry>[
      ..._entries,
      for (final pending in _pending.values) pending.buildEntry(this),
    ]..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final matchingEntries = allEntries
        .where((entry) => _matchesQuery(entry, query))
        .toList(growable: false);
    final boundedMax = maxEntries < 0 ? 0 : maxEntries;
    final startIndex = matchingEntries.length > boundedMax
        ? matchingEntries.length - boundedMax
        : 0;
    final visibleEntries = boundedMax == 0
        ? const <CockpitNetworkEntry>[]
        : matchingEntries.sublist(startIndex);
    return CockpitNetworkSnapshot(
      totalEntryCount: matchingEntries.length,
      failureCount: matchingEntries.where((entry) => entry.isFailure).length,
      entries: visibleEntries,
      endpointSummaries: _summariesFor(matchingEntries),
      capturedEntryCount: allEntries.length,
      inFlightCount: _inFlightCount,
      query: query,
      truncated: matchingEntries.length > visibleEntries.length,
    );
  }

  @override
  Future<bool> waitForIdle({
    Duration quietWindow = const Duration(milliseconds: 150),
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_isIdleFor(quietWindow)) {
        return true;
      }
      await _tickHandler(const Duration(milliseconds: 24));
    }
    return _isIdleFor(quietWindow);
  }

  @override
  void clear() {
    _entries.clear();
    _lastActivityAt = DateTime.now().toUtc();
  }

  String nextRequestId() {
    _requestCounter += 1;
    return '$_requestCounter';
  }

  bool captures(String method, Uri uri) {
    final filter = captureFilter;
    if (filter == null) return true;
    try {
      return filter(method, uri);
    } on Object {
      return true;
    }
  }

  Map<String, String> snapshotHeaders(HttpHeaders headers) {
    if (!captureHeaders) {
      return const <String, String>{};
    }

    final captured = <String, String>{};
    headers.forEach((name, values) {
      if (captured.length >= maxHeaderCount) {
        return;
      }
      final safeValue = values
          .map((value) => redact ? _redactor.headerValue(name, value) : value)
          .join(', ');
      final boundedValue = safeValue.length > maxHeaderValueLength
          ? '${safeValue.substring(0, maxHeaderValueLength)}...'
          : safeValue;
      captured[name] = boundedValue;
    });
    return Map<String, String>.unmodifiable(captured);
  }

  void _finish(_CockpitPendingNetworkRecord pending) {
    if (pending.finished) return;
    pending.finished = true;
    _pending.remove(pending.requestId);
    if (pending.countsAsInFlight) {
      pending.countsAsInFlight = false;
      _inFlightCount = ((_inFlightCount - 1).clamp(0, maxRetainedEntries * 10));
    }
    _lastActivityAt = DateTime.now().toUtc();
    _entries.add(pending.buildEntry(this));
    while (_entries.length > maxRetainedEntries) {
      _entries.removeFirst();
    }
  }

  void _markRequestStarted(_CockpitPendingNetworkRecord pending) {
    _pending[pending.requestId] = pending;
    _inFlightCount += 1;
    _lastActivityAt = DateTime.now().toUtc();
  }

  void _markActivity(_CockpitPendingNetworkRecord pending) {
    pending.updatedAt = DateTime.now().toUtc();
    _lastActivityAt = pending.updatedAt;
  }

  void _markWebSocketOpened(_CockpitPendingNetworkRecord pending) {
    if (pending.countsAsInFlight) {
      pending.countsAsInFlight = false;
      _inFlightCount = ((_inFlightCount - 1).clamp(0, maxRetainedEntries * 10));
    }
    _markActivity(pending);
  }

  String? previewBytes(
    List<int> bytes, {
    Map<String, String> headers = const <String, String>{},
  }) {
    if (!captureBodies || bytes.isEmpty) return null;
    final value = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll('\u0000', '');
    if (!redact) return value;
    return _redactor.body(value, contentType: _redactor.contentType(headers));
  }

  bool _matchesQuery(CockpitNetworkEntry entry, CockpitNetworkQuery query) {
    final id = query.id;
    if (id != null && id.isNotEmpty && entry.requestId != id) return false;
    final before = query.before;
    if (before != null && before.isNotEmpty) {
      final entrySequence = int.tryParse(entry.requestId);
      final beforeSequence = int.tryParse(before);
      if (entrySequence == null ||
          beforeSequence == null ||
          entrySequence >= beforeSequence) {
        return false;
      }
    }
    if (query.onlyFailures && !entry.isFailure) {
      return false;
    }
    final method = query.method;
    if (method != null &&
        method.isNotEmpty &&
        entry.method.toUpperCase() != method.toUpperCase()) {
      return false;
    }
    final uriContains = query.uriContains;
    if (uriContains != null &&
        uriContains.isNotEmpty &&
        !entry.uri.contains(uriContains)) {
      return false;
    }
    final statusCodeAtLeast = query.statusCodeAtLeast;
    if (statusCodeAtLeast != null) {
      final statusCode = entry.statusCode;
      if (statusCode == null || statusCode < statusCodeAtLeast) {
        return false;
      }
    }
    return true;
  }

  bool _isIdleFor(Duration quietWindow) {
    if (_inFlightCount != 0) {
      return false;
    }
    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(lastActivityAt) >= quietWindow;
  }

  List<CockpitNetworkEndpointSummary> _summariesFor(
    List<CockpitNetworkEntry> entries,
  ) {
    final buckets = <String, List<CockpitNetworkEntry>>{};
    for (final entry in entries) {
      final pattern = _uriPatternFor(entry.uri);
      final bucketKey = '${entry.method} $pattern';
      buckets.putIfAbsent(bucketKey, () => <CockpitNetworkEntry>[]).add(entry);
    }

    final summaries = buckets.entries
        .map((bucket) {
          final bucketEntries = bucket.value;
          final latestEntry = bucketEntries.reduce((left, right) {
            return left.startedAt.isAfter(right.startedAt) ? left : right;
          });
          final averageDurationMs =
              bucketEntries
                  .map((entry) => entry.durationMs)
                  .fold<int>(0, (total, duration) => total + duration) ~/
              bucketEntries.length;
          return CockpitNetworkEndpointSummary(
            method: latestEntry.method,
            uriPattern: _uriPatternFor(latestEntry.uri),
            requestCount: bucketEntries.length,
            failureCount: bucketEntries
                .where((entry) => entry.isFailure)
                .length,
            averageDurationMs: averageDurationMs,
            lastStatusCode: latestEntry.statusCode,
            latestUri: latestEntry.uri,
          );
        })
        .toList(growable: false);

    summaries.sort((left, right) {
      final failureCompare = right.failureCount.compareTo(left.failureCount);
      if (failureCompare != 0) {
        return failureCompare;
      }
      return right.requestCount.compareTo(left.requestCount);
    });
    return summaries;
  }

  String _uriPatternFor(String rawUri) {
    final uri = Uri.tryParse(rawUri);
    final path = uri?.path;
    if (path == null || path.isEmpty) {
      return rawUri;
    }
    return path;
  }

  static Future<void> _defaultTickHandler(Duration duration) {
    return Future<void>.delayed(duration);
  }
}

final class _CockpitObservedHttpClient implements HttpClient {
  _CockpitObservedHttpClient(this._delegate, {required this.observer});

  final HttpClient _delegate;
  final CockpitHttpNetworkObserver observer;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (!observer.captures(method, url)) {
      return _delegate.openUrl(method, url);
    }
    final pending = _CockpitPendingNetworkRecord(
      requestId: observer.nextRequestId(),
      method: method,
      uri: url,
    );
    _captureSafely(() => observer._markRequestStarted(pending));
    try {
      final request = await _delegate.openUrl(method, url);
      return _CockpitObservedHttpClientRequest(
        request,
        observer: observer,
        pending: pending,
      );
    } on Object catch (error) {
      pending.error = error.toString();
      _captureSafely(() => observer._finish(pending));
      rethrow;
    }
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  set autoUncompress(bool value) => _delegate.autoUncompress = value;

  @override
  bool get autoUncompress => _delegate.autoUncompress;

  @override
  set userAgent(String? value) => _delegate.userAgent = value;

  @override
  String? get userAgent => _delegate.userAgent;

  @override
  set idleTimeout(Duration value) => _delegate.idleTimeout = value;

  @override
  Duration get idleTimeout => _delegate.idleTimeout;

  @override
  set connectionTimeout(Duration? value) => _delegate.connectionTimeout = value;

  @override
  Duration? get connectionTimeout => _delegate.connectionTimeout;

  @override
  set maxConnectionsPerHost(int? value) =>
      _delegate.maxConnectionsPerHost = value;

  @override
  int? get maxConnectionsPerHost => _delegate.maxConnectionsPerHost;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _delegate.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _delegate.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _delegate.badCertificateCallback = callback;

  @override
  set findProxy(String Function(Uri url)? f) => _delegate.findProxy = f;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _delegate.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _delegate.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CockpitObservedHttpClientRequest implements HttpClientRequest {
  _CockpitObservedHttpClientRequest(
    this._delegate, {
    required this.observer,
    required this.pending,
  });

  final HttpClientRequest _delegate;
  final CockpitHttpNetworkObserver observer;
  final _CockpitPendingNetworkRecord pending;

  @override
  HttpHeaders get headers => _delegate.headers;

  @override
  String get method => _delegate.method;

  @override
  Uri get uri => _delegate.uri;

  @override
  Encoding get encoding => _delegate.encoding;

  @override
  set encoding(Encoding value) => _delegate.encoding = value;

  @override
  bool get followRedirects => _delegate.followRedirects;

  @override
  set followRedirects(bool value) => _delegate.followRedirects = value;

  @override
  int get maxRedirects => _delegate.maxRedirects;

  @override
  set maxRedirects(int value) => _delegate.maxRedirects = value;

  @override
  bool get persistentConnection => _delegate.persistentConnection;

  @override
  set persistentConnection(bool value) =>
      _delegate.persistentConnection = value;

  @override
  int get contentLength => _delegate.contentLength;

  @override
  set contentLength(int value) => _delegate.contentLength = value;

  @override
  List<Cookie> get cookies => _delegate.cookies;

  @override
  Future<HttpClientResponse> get done => _delegate.done;

  @override
  void add(List<int> data) {
    _delegate.add(data);
    _captureSafely(() => pending.captureRequestBytes(data, observer));
  }

  @override
  void write(Object? object) {
    final value = '${object ?? ''}';
    _delegate.write(value);
    _captureSafely(
      () => pending.captureRequestBytes(encoding.encode(value), observer),
    );
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var isFirst = true;
    _delegate.writeAll(
      objects.map((object) {
        final value = '${object ?? ''}';
        _captureSafely(
          () => pending.captureRequestBytes(
            encoding.encode('${isFirst ? '' : separator}$value'),
            observer,
          ),
        );
        isFirst = false;
        return value;
      }),
      separator,
    );
  }

  @override
  void writeCharCode(int charCode) {
    _delegate.writeCharCode(charCode);
    _captureSafely(
      () => pending.captureRequestBytes(
        encoding.encode(String.fromCharCode(charCode)),
        observer,
      ),
    );
  }

  @override
  void writeln([Object? object = '']) {
    final value = '${object ?? ''}';
    _delegate.writeln(value);
    _captureSafely(
      () => pending.captureRequestBytes(encoding.encode('$value\n'), observer),
    );
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _delegate.addStream(
      stream.map((chunk) {
        _captureSafely(() => pending.captureRequestBytes(chunk, observer));
        return chunk;
      }),
    );
  }

  @override
  Future<void> flush() => _delegate.flush();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _captureSafely(() {
      pending.error = exception?.toString() ?? 'Request aborted.';
      pending.captureRequestHeaders(
        observer.snapshotHeaders(_delegate.headers),
      );
      observer._markActivity(pending);
      observer._finish(pending);
    });
    _delegate.abort(exception, stackTrace);
  }

  @override
  Future<HttpClientResponse> close() async {
    _captureSafely(
      () => pending.captureRequestHeaders(
        observer.snapshotHeaders(_delegate.headers),
      ),
    );
    pending.requestClosed = true;
    _captureSafely(() => observer._markActivity(pending));
    try {
      final response = await _delegate.close();
      pending.statusCode = response.statusCode;
      pending.responseStarted = true;
      _captureSafely(
        () => pending.captureResponseHeaders(
          observer.snapshotHeaders(response.headers),
        ),
      );
      _captureSafely(() => observer._markActivity(pending));
      if (response.statusCode != HttpStatus.switchingProtocols &&
          (response.contentLength == 0 || method == 'HEAD')) {
        _captureSafely(() => observer._finish(pending));
        return _CockpitObservedHttpClientResponse(
          response,
          observer: observer,
          pending: pending,
          alreadyCompleted: true,
        );
      }
      return _CockpitObservedHttpClientResponse(
        response,
        observer: observer,
        pending: pending,
      );
    } on Object catch (error) {
      pending.error = error.toString();
      _captureSafely(() => observer._finish(pending));
      rethrow;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CockpitObservedHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _CockpitObservedHttpClientResponse(
    this._delegate, {
    required this.observer,
    required this.pending,
    bool alreadyCompleted = false,
  }) : _completed = alreadyCompleted;

  final HttpClientResponse _delegate;
  final CockpitHttpNetworkObserver observer;
  final _CockpitPendingNetworkRecord pending;
  bool _completed;

  @override
  X509Certificate? get certificate => _delegate.certificate;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _delegate.compressionState;

  @override
  int get contentLength => _delegate.contentLength;

  @override
  List<Cookie> get cookies => _delegate.cookies;

  @override
  HttpHeaders get headers => _delegate.headers;

  @override
  bool get isRedirect => _delegate.isRedirect;

  @override
  bool get persistentConnection => _delegate.persistentConnection;

  @override
  String get reasonPhrase => _delegate.reasonPhrase;

  @override
  List<RedirectInfo> get redirects => _delegate.redirects;

  @override
  int get statusCode => _delegate.statusCode;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => _delegate.redirect(method, url, followLoops ?? false);

  @override
  Future<Socket> detachSocket() async {
    try {
      pending.statusCode = _delegate.statusCode;
      pending.responseStarted = true;
      pending.webSocketOpened = true;
      _captureSafely(
        () => pending.captureResponseHeaders(
          observer.snapshotHeaders(_delegate.headers),
        ),
      );
      _captureSafely(() => observer._markWebSocketOpened(pending));
      final socket = await _delegate.detachSocket();
      return _CockpitObservedWebSocket(
        socket,
        observer: observer,
        pending: pending,
      );
    } on Object catch (error) {
      pending.error = error.toString();
      _captureSafely(() => observer._finish(pending));
      rethrow;
    }
  }

  @override
  HttpConnectionInfo? get connectionInfo => _delegate.connectionInfo;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final observed = _delegate.transform<List<int>>(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          _captureSafely(() => pending.captureResponseBytes(chunk, observer));
          sink.add(chunk);
        },
        handleError: (error, stackTrace, sink) {
          if (!_completed) {
            _completed = true;
            pending.statusCode = _delegate.statusCode;
            _captureSafely(
              () => pending.captureResponseHeaders(
                observer.snapshotHeaders(_delegate.headers),
              ),
            );
            pending.error = error.toString();
            _captureSafely(() {
              observer._markActivity(pending);
              observer._finish(pending);
            });
          }
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          if (!_completed) {
            _completed = true;
            pending.statusCode = _delegate.statusCode;
            _captureSafely(
              () => pending.captureResponseHeaders(
                observer.snapshotHeaders(_delegate.headers),
              ),
            );
            _captureSafely(() => observer._finish(pending));
          }
          sink.close();
        },
      ),
    );
    final subscription = observed.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _CockpitObservedStreamSubscription<List<int>>(
      subscription,
      onCancel: () {
        if (_completed) return;
        _completed = true;
        pending.statusCode = _delegate.statusCode;
        pending.responseCancelled = true;
        _captureSafely(
          () => pending.captureResponseHeaders(
            observer.snapshotHeaders(_delegate.headers),
          ),
        );
        _captureSafely(() {
          observer._markActivity(pending);
          observer._finish(pending);
        });
      },
    );
  }

  @override
  Future<E> drain<E>([E? futureValue]) async {
    await listen(null).asFuture<void>();
    return futureValue as E;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CockpitObservedStreamSubscription<T>
    implements StreamSubscription<T> {
  _CockpitObservedStreamSubscription(this._delegate, {required this.onCancel});

  final StreamSubscription<T> _delegate;
  final void Function() onCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _captureSafely(onCancel);
    }
    return _delegate.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture(futureValue);
}

final class _CockpitObservedWebSocket extends Stream<Uint8List>
    implements Socket {
  _CockpitObservedWebSocket(
    this._delegate, {
    required this.observer,
    required this.pending,
  }) : _sent = CockpitWebSocketFrameDecoder(
         maxPreviewBytes: observer.maxWebSocketPreviewBytes,
         onFrame: (frame) => pending.captureWebSocketFrame(
           frame,
           CockpitWebSocketDirection.sent,
           observer,
         ),
       ),
       _received = CockpitWebSocketFrameDecoder(
         maxPreviewBytes: observer.maxWebSocketPreviewBytes,
         onFrame: (frame) => pending.captureWebSocketFrame(
           frame,
           CockpitWebSocketDirection.received,
           observer,
         ),
       );

  final Socket _delegate;
  final CockpitHttpNetworkObserver observer;
  final _CockpitPendingNetworkRecord pending;
  final CockpitWebSocketFrameDecoder _sent;
  final CockpitWebSocketFrameDecoder _received;

  @override
  InternetAddress get address => _delegate.address;

  @override
  InternetAddress get remoteAddress => _delegate.remoteAddress;

  @override
  int get port => _delegate.port;

  @override
  int get remotePort => _delegate.remotePort;

  @override
  Encoding get encoding => _delegate.encoding;

  @override
  set encoding(Encoding value) => _delegate.encoding = value;

  @override
  Future<dynamic> get done => _delegate.done;

  @override
  void add(List<int> data) {
    _delegate.add(data);
    _captureSafely(() => _sent.add(data));
  }

  @override
  void write(Object? object) {
    final value = '${object ?? ''}';
    _delegate.write(value);
    _captureSafely(() => _sent.add(encoding.encode(value)));
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    _delegate.writeAll(
      objects.map((object) {
        final value = '${object ?? ''}';
        _captureSafely(
          () => _sent.add(encoding.encode('${first ? '' : separator}$value')),
        );
        first = false;
        return value;
      }),
      separator,
    );
  }

  @override
  void writeCharCode(int charCode) {
    _delegate.writeCharCode(charCode);
    _captureSafely(
      () => _sent.add(encoding.encode(String.fromCharCode(charCode))),
    );
  }

  @override
  void writeln([Object? object = '']) {
    final value = '${object ?? ''}';
    _delegate.writeln(value);
    _captureSafely(() => _sent.add(encoding.encode('$value\n')));
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return _delegate.addStream(
      stream.map((chunk) {
        _captureSafely(() => _sent.add(chunk));
        return chunk;
      }),
    );
  }

  @override
  Future<void> flush() => _delegate.flush();

  @override
  Future<dynamic> close() => _delegate.close();

  @override
  void destroy() {
    _delegate.destroy();
    _captureSafely(_complete);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _delegate.addError(error, stackTrace);
  }

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _delegate.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _delegate.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _delegate.setRawOption(option);

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final observed = _delegate.transform<Uint8List>(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          _captureSafely(() => _received.add(chunk));
          sink.add(chunk);
        },
        handleError: (error, stackTrace, sink) {
          _captureSafely(() => _complete(error: error));
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          _captureSafely(_complete);
          sink.close();
        },
      ),
    );
    return observed.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  void _complete({Object? error}) {
    if (pending.finished) return;
    pending.webSocketClosed = true;
    if (error != null) pending.error = error.toString();
    observer._markActivity(pending);
    observer._finish(pending);
  }
}

void _captureSafely(void Function() capture) {
  try {
    capture();
  } on Object {
    // Diagnostics are strictly passive and must not enter the user data path.
  }
}

final class _CockpitPendingNetworkRecord {
  _CockpitPendingNetworkRecord({
    required this.requestId,
    required this.method,
    required this.uri,
  }) : startedAt = DateTime.now().toUtc();

  final String requestId;
  final String method;
  final Uri uri;
  final DateTime startedAt;
  DateTime updatedAt = DateTime.now().toUtc();
  final BytesBuilder _requestBytes = BytesBuilder(copy: false);
  final BytesBuilder _responseBytes = BytesBuilder(copy: false);
  final ListQueue<CockpitWebSocketFrame> _webSocketFrames =
      ListQueue<CockpitWebSocketFrame>();
  Map<String, String> requestHeaders = const <String, String>{};
  Map<String, String> responseHeaders = const <String, String>{};
  int? statusCode;
  String? error;
  bool requestTruncated = false;
  bool responseTruncated = false;
  bool requestClosed = false;
  bool responseStarted = false;
  bool responseCancelled = false;
  bool webSocketOpened = false;
  bool webSocketClosing = false;
  bool webSocketClosed = false;
  bool finished = false;
  bool countsAsInFlight = true;
  int requestBodyBytes = 0;
  int responseBodyBytes = 0;
  int sentWebSocketFrames = 0;
  int receivedWebSocketFrames = 0;
  int sentWebSocketBytes = 0;
  int receivedWebSocketBytes = 0;
  int _webSocketSequence = 0;

  void captureRequestHeaders(Map<String, String> headers) {
    requestHeaders = headers;
  }

  void captureResponseHeaders(Map<String, String> headers) {
    responseHeaders = headers;
  }

  void captureRequestBytes(
    List<int> bytes,
    CockpitHttpNetworkObserver observer,
  ) {
    requestBodyBytes += bytes.length;
    observer._markActivity(this);
    if (!observer.captureBodies || requestTruncated) {
      return;
    }
    final remaining = observer.maxBodyBytes - _requestBytes.length;
    if (remaining <= 0) {
      requestTruncated = true;
      return;
    }
    if (bytes.length > remaining) {
      _requestBytes.add(bytes.take(remaining).toList(growable: false));
      requestTruncated = true;
      return;
    }
    _requestBytes.add(bytes);
  }

  void captureResponseBytes(
    List<int> bytes,
    CockpitHttpNetworkObserver observer,
  ) {
    responseBodyBytes += bytes.length;
    observer._markActivity(this);
    if (!observer.captureBodies || responseTruncated) {
      return;
    }
    final remaining = observer.maxBodyBytes - _responseBytes.length;
    if (remaining <= 0) {
      responseTruncated = true;
      return;
    }
    if (bytes.length > remaining) {
      _responseBytes.add(bytes.take(remaining).toList(growable: false));
      responseTruncated = true;
      return;
    }
    _responseBytes.add(bytes);
  }

  void captureWebSocketFrame(
    CockpitDecodedWebSocketFrame decoded,
    CockpitWebSocketDirection direction,
    CockpitHttpNetworkObserver observer,
  ) {
    _webSocketSequence += 1;
    if (direction == CockpitWebSocketDirection.sent) {
      sentWebSocketFrames += 1;
      sentWebSocketBytes += decoded.payloadBytes;
    } else {
      receivedWebSocketFrames += 1;
      receivedWebSocketBytes += decoded.payloadBytes;
    }
    final preview =
        decoded.previewBytes.isEmpty ||
            !decoded.textPayload ||
            decoded.compressed
        ? null
        : utf8
              .decode(decoded.previewBytes, allowMalformed: true)
              .replaceAll('\u0000', '');
    _webSocketFrames.add(
      CockpitWebSocketFrame(
        sequence: _webSocketSequence,
        direction: direction,
        kind: _webSocketFrameKind(decoded.opcode),
        at: DateTime.now().toUtc(),
        payloadBytes: decoded.payloadBytes,
        finalFragment: decoded.finalFragment,
        compressed: decoded.compressed,
        preview: preview == null || !observer.redact
            ? preview
            : CockpitHttpNetworkObserver._redactor.text(preview),
      ),
    );
    final frameLimit = observer.maxWebSocketFrames < 0
        ? 0
        : observer.maxWebSocketFrames;
    while (_webSocketFrames.length > frameLimit) {
      _webSocketFrames.removeFirst();
    }
    if (decoded.opcode == 8) {
      if (direction == CockpitWebSocketDirection.received) {
        webSocketClosed = true;
        scheduleMicrotask(() => _captureSafely(() => observer._finish(this)));
      } else {
        webSocketClosing = true;
      }
    }
    observer._markActivity(this);
  }

  CockpitNetworkEntry buildEntry(CockpitHttpNetworkObserver observer) {
    final state = error != null
        ? CockpitNetworkState.failed
        : webSocketOpened
        ? (webSocketClosed
              ? CockpitNetworkState.closed
              : webSocketClosing
              ? CockpitNetworkState.closing
              : CockpitNetworkState.open)
        : responseCancelled
        ? CockpitNetworkState.cancelled
        : finished
        ? CockpitNetworkState.complete
        : responseStarted
        ? CockpitNetworkState.receiving
        : requestClosed
        ? CockpitNetworkState.waiting
        : CockpitNetworkState.sending;
    return CockpitNetworkEntry(
      requestId: requestId,
      method: method,
      uri: observer.redact
          ? CockpitHttpNetworkObserver._redactor.uri(uri).toString()
          : uri.toString(),
      startedAt: startedAt,
      durationMs: DateTime.now().toUtc().difference(startedAt).inMilliseconds,
      protocol: webSocketOpened
          ? CockpitNetworkProtocol.webSocket
          : CockpitNetworkProtocol.http,
      state: state,
      updatedAt: updatedAt,
      statusCode: statusCode,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestBodyPreview: observer.previewBytes(
        _requestBytes.toBytes(),
        headers: requestHeaders,
      ),
      responseBodyPreview: observer.previewBytes(
        _responseBytes.toBytes(),
        headers: responseHeaders,
      ),
      requestBodyBytes: requestBodyBytes,
      responseBodyBytes: responseBodyBytes,
      requestBodyTruncated: requestTruncated,
      responseBodyTruncated: responseTruncated,
      webSocket: webSocketOpened
          ? CockpitWebSocketActivity(
              sentFrames: sentWebSocketFrames,
              receivedFrames: receivedWebSocketFrames,
              sentBytes: sentWebSocketBytes,
              receivedBytes: receivedWebSocketBytes,
              recentFrames: List<CockpitWebSocketFrame>.unmodifiable(
                _webSocketFrames,
              ),
              framesTruncated:
                  sentWebSocketFrames + receivedWebSocketFrames >
                  _webSocketFrames.length,
            )
          : null,
      error: error == null || !observer.redact
          ? error
          : CockpitHttpNetworkObserver._redactor.text(error!),
    );
  }
}

CockpitWebSocketFrameKind _webSocketFrameKind(int opcode) => switch (opcode) {
  0 => CockpitWebSocketFrameKind.continuation,
  1 => CockpitWebSocketFrameKind.text,
  2 => CockpitWebSocketFrameKind.binary,
  8 => CockpitWebSocketFrameKind.close,
  9 => CockpitWebSocketFrameKind.ping,
  10 => CockpitWebSocketFrameKind.pong,
  _ => throw StateError('Unsupported WebSocket opcode $opcode.'),
};
