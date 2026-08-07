import 'package:cockpit_console/src/ui/screens/runs_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRunInputs', () {
    test('accepts an empty value as no inputs', () {
      expect(parseRunInputs('  '), isEmpty);
    });

    test('accepts a JSON object without changing nested values', () {
      expect(
        parseRunInputs('{"user":"alice","flags":[true,2]}'),
        <String, Object?>{
          'user': 'alice',
          'flags': <Object?>[true, 2],
        },
      );
    });

    test('rejects non-object JSON', () {
      expect(() => parseRunInputs('[1,2]'), throwsFormatException);
    });

    test('rejects malformed JSON', () {
      expect(() => parseRunInputs('{'), throwsFormatException);
    });
  });

  group('parseRunTimeout', () {
    test('uses the server default when empty', () {
      expect(parseRunTimeout('', isSuite: false), isNull);
    });

    test('accepts case and suite maximums', () {
      expect(parseRunTimeout('21600000', isSuite: false), 21600000);
      expect(parseRunTimeout('6h', isSuite: false), 21600000);
      expect(parseRunTimeout('24h', isSuite: true), 86400000);
    });

    test('accepts human-readable duration units', () {
      expect(parseRunTimeout('30s', isSuite: false), 30000);
      expect(parseRunTimeout('5m', isSuite: false), 300000);
      expect(parseRunTimeout('1500ms', isSuite: false), 1500);
    });

    test('rejects non-positive and out-of-policy values', () {
      expect(() => parseRunTimeout('0', isSuite: false), throwsFormatException);
      expect(
        () => parseRunTimeout('7h', isSuite: false),
        throwsFormatException,
      );
      expect(
        () => parseRunTimeout('6h1m', isSuite: false),
        throwsFormatException,
      );
    });
  });

  group('formatRunEventMessage', () {
    test('removes duplicated protocol tokens', () {
      expect(
        formatRunEventMessage(
          kind: 'run.queued',
          entityKind: 'run',
          lifecycle: 'queued',
        ),
        'Run queued',
      );
      expect(
        formatRunEventMessage(
          kind: 'case.completed',
          entityKind: 'case',
          lifecycle: 'completed',
          outcome: 'passed',
        ),
        'Case passed',
      );
    });
  });
}
