import 'dart:async';
import 'dart:convert';

import 'package:cockpit/src/application/cockpit_lsp_wire_format.dart';
import 'package:test/test.dart';

void main() {
  group('cockpitLspChannel', () {
    test('decodes a well-formed LSP frame', () async {
      final input = StreamController<List<int>>();
      final sink = _CollectingSink();
      final channel = cockpitLspChannel(input.stream, sink);

      const payload = '{"jsonrpc":"2.0","method":"ping"}';
      final body = utf8.encode(payload);
      input.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
      input.add(body);
      await input.close();

      expect(await channel.stream.toList(), <String>[payload]);
    });

    test('rejects a header that never terminates', () async {
      final input = StreamController<List<int>>();
      final sink = _CollectingSink();
      final channel = cockpitLspChannel(input.stream, sink);

      // Feed header bytes without the \r\n\r\n terminator, past the 8 KiB
      // bound — the parser must abort the frame instead of buffering it.
      final garbage = List<int>.filled(9000, 65 /* 'A' */);
      input.add(garbage);

      await expectLater(
        channel.stream.toList(),
        throwsA(isA<FormatException>()),
      );
      await input.close();
    });

    test('rejects a Content-Length above the worker maximum', () async {
      final input = StreamController<List<int>>();
      final sink = _CollectingSink();
      final channel = cockpitLspChannel(input.stream, sink);

      input.add(ascii.encode('Content-Length: 2000000\r\n\r\n'));

      await expectLater(
        channel.stream.toList(),
        throwsA(isA<FormatException>()),
      );
      await input.close();
    });
  });
}

final class _CollectingSink implements StreamSink<List<int>> {
  final List<List<int>> chunks = <List<int>>[];
  final _done = Completer<void>();

  @override
  void add(List<int> data) => chunks.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}
