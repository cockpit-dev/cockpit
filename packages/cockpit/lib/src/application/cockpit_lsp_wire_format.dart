import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

import '../worker/cockpit_worker_value_reader.dart';

/// Upper bound on the accumulated header bytes while scanning for the
/// `\r\n\r\n` terminator. A peer that never terminates the header would
/// otherwise grow the buffer without limit.
const int _lspHeaderMaximumBytes = 8192;

StreamChannel<String> cockpitLspChannel(
  Stream<List<int>> stream,
  StreamSink<List<int>> sink,
) {
  final parser = _CockpitLspParser(stream);
  final output = _CockpitLspOutputSink(sink: sink, onClose: parser.close);
  return StreamChannel.withGuarantees(parser.stream, output);
}

void _serializeLspMessage(String data, EventSink<List<int>> sink) {
  final message = utf8.encode(data);
  final header = 'Content-Length: ${message.length}\r\n\r\n';
  sink.add(ascii.encode(header));
  sink.add(message);
}

final class _CockpitLspParser {
  _CockpitLspParser(Stream<List<int>> input)
    : _subscription = input.expand((chunk) => chunk).listen(null) {
    _subscription
      ..onData(_handleByte)
      ..onDone(_controller.close);
  }

  final _controller = StreamController<String>();
  final List<int> _buffer = <int>[];
  late final StreamSubscription<int> _subscription;
  bool _readingHeader = true;
  int _contentLength = -1;

  Stream<String> get stream => _controller.stream;

  Future<void> close() => _subscription.cancel();

  void _handleByte(int byte) {
    _buffer.add(byte);
    if (_readingHeader) {
      if (_headerComplete) {
        final contentLength = _parseContentLength();
        if (contentLength == null) {
          return;
        }
        if (contentLength < 0 ||
            contentLength > cockpitWorkerMaximumPayloadBytes) {
          _failFrame(
            'LSP Content-Length $contentLength exceeds the worker maximum '
            'of $cockpitWorkerMaximumPayloadBytes bytes.',
          );
          return;
        }
        _contentLength = contentLength;
        _buffer.clear();
        _readingHeader = false;
        return;
      }
      if (_buffer.length > _lspHeaderMaximumBytes) {
        _failFrame(
          'LSP header exceeded $_lspHeaderMaximumBytes bytes without a '
          'terminator.',
        );
        return;
      }
      return;
    }
    if (_buffer.length >= _contentLength) {
      _controller.add(utf8.decode(_buffer));
      _buffer.clear();
      _readingHeader = true;
      _contentLength = -1;
    }
  }

  void _failFrame(String message) {
    _buffer.clear();
    _contentLength = -1;
    _controller.addError(FormatException(message));
    _subscription.cancel();
  }

  bool get _headerComplete {
    final length = _buffer.length;
    return length >= 4 &&
        _buffer[length - 4] == 13 &&
        _buffer[length - 3] == 10 &&
        _buffer[length - 2] == 13 &&
        _buffer[length - 1] == 10;
  }

  int? _parseContentLength() {
    String header;
    try {
      header = ascii.decode(_buffer);
    } on FormatException {
      _failFrame('LSP header is not valid ASCII.');
      return null;
    }
    final lines = header.split('\r\n');
    final lengthLine = lines.firstWhere(
      (line) => line.startsWith('Content-Length:'),
      orElse: () => '',
    );
    if (lengthLine.isEmpty) {
      _failFrame('Missing Content-Length header.');
      return null;
    }
    try {
      return int.parse(lengthLine.split(':').last.trim());
    } on FormatException {
      _failFrame('Unparseable Content-Length header.');
      return null;
    }
  }
}

final class _CockpitLspOutputSink implements StreamSink<String> {
  _CockpitLspOutputSink({
    required StreamSink<List<int>> sink,
    required Future<void> Function() onClose,
  }) : _sink = sink,
       _onClose = onClose;

  final StreamSink<List<int>> _sink;
  final Future<void> Function() _onClose;

  @override
  void add(String data) => _serializeLspMessage(data, _sink);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<String> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close() async {
    await _sink.close();
    await _onClose();
  }

  @override
  Future<void> get done => _sink.done;
}
