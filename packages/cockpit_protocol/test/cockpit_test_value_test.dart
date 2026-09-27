import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitTestTemplateValue', () {
    test('plain strings containing interpolation markers remain literal', () {
      const source = r'Hello ${name}';

      final value = CockpitTestTemplateValue.fromJson(
        source,
        expectedType: CockpitTestValueType.string,
        path: r'$.text',
      );

      expect(value.kind, CockpitTestTemplateValueKind.literal);
      expect(value.value, source);
      expect(value.toJson(), source);
      expect(
        CockpitTestTemplateValue.fromJson(
          value.toJson(),
          expectedType: CockpitTestValueType.string,
          path: r'$.text',
        ),
        value,
      );
    });

    test('explicit template objects round-trip without losing their kind', () {
      const source = r'Hello ${name}';

      final value = CockpitTestTemplateValue.fromJson(
        const <String, Object?>{r'$template': source},
        expectedType: CockpitTestValueType.string,
        path: r'$.text',
      );

      expect(value.kind, CockpitTestTemplateValueKind.stringTemplate);
      expect(value.value, source);
      expect(value.toJson(), const <String, Object?>{r'$template': source});
      expect(
        CockpitTestTemplateValue.fromJson(
          value.toJson(),
          expectedType: CockpitTestValueType.string,
          path: r'$.text',
        ),
        value,
      );
    });

    test('template-shaped JSON remains literal for JSON-valued fields', () {
      const source = <String, Object?>{r'$template': r'Hello ${name}'};

      final value = CockpitTestTemplateValue.fromJson(
        source,
        expectedType: CockpitTestValueType.json,
        path: r'$.payload',
      );

      expect(value.kind, CockpitTestTemplateValueKind.literal);
      expect(value.toJson(), source);
    });

    test('explicit template objects reject malformed payloads and fields', () {
      expect(
        () => CockpitTestTemplateValue.fromJson(
          const <String, Object?>{r'$template': 1},
          expectedType: CockpitTestValueType.string,
          path: r'$.text',
        ),
        throwsA(_formatExceptionAt(r'$.text.$template')),
      );
      expect(
        () => CockpitTestTemplateValue.fromJson(
          const <String, Object?>{
            r'$template': r'Hello ${name}',
            'extra': true,
          },
          expectedType: CockpitTestValueType.string,
          path: r'$.text',
        ),
        throwsA(_formatExceptionAt(r'$.text.extra')),
      );
    });
  });
}

Matcher _formatExceptionAt(String path) => isA<FormatException>().having(
  (error) => error.message.toString(),
  'message',
  contains(path),
);
