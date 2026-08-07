import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_catalog.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_schema.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

void main() {
  test('every advertised operation schema reference resolves', () {
    final document = CockpitSupervisorOperationSchema.document();
    final definitions = Map<String, Object?>.from(
      document[r'$defs']! as Map<Object?, Object?>,
    );

    for (final descriptor in CockpitSupervisorOperationCatalog.allOperations) {
      expect(
        definitions,
        contains('${descriptor.kind}.request'),
        reason: descriptor.requestSchemaRef,
      );
      expect(
        definitions,
        contains('${descriptor.kind}.response'),
        reason: descriptor.responseSchemaRef,
      );
    }
  });

  test('Flutter viewport schema exposes and enforces exact bounds', () {
    final document = CockpitSupervisorOperationSchema.document();
    final definitions = Map<String, Object?>.from(
      document[r'$defs']! as Map<Object?, Object?>,
    );
    final schema = Map<String, Object?>.from(
      definitions['viewport.set.request']! as Map<Object?, Object?>,
    );
    final compiled = JsonSchema.create(schema);

    expect(schema['x-cockpit-precision'], 'exact');
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 800,
        'height': 600,
      }).isValid,
      isTrue,
    );
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 199,
        'height': 600,
      }).isValid,
      isFalse,
    );
    expect(
      compiled.validate(<String, Object?>{
        'sessionId': 'session-1',
        'width': 800,
        'height': 600,
        'guessedField': true,
      }).isValid,
      isFalse,
    );
  });

  test('network schemas accept numeric IDs and every bounded query field', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    final read = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['network.read.request']! as Map<Object?, Object?>,
      ),
    );
    final body = JsonSchema.create(
      Map<String, Object?>.from(
        definitions['network.body.request']! as Map<Object?, Object?>,
      ),
    );

    expect(
      read.validate(<String, Object?>{
        'sessionId': 'session-1',
        'id': '37',
        'includeEntries': true,
        'maxEntries': 12,
        'maxEndpointSummaries': 8,
      }).isValid,
      isTrue,
    );
    expect(
      body.validate(<String, Object?>{
        'sessionId': 'session-1',
        'requestId': '37',
        'body': 'both',
        'raw': false,
      }).isValid,
      isTrue,
    );
    expect(
      read.validate(<String, Object?>{
        'sessionId': 'session-1',
        'id': 'request-37',
      }).isValid,
      isFalse,
    );
  });

  test('wait idle schema matches the task command timeout contract', () {
    final definitions = Map<String, Object?>.from(
      CockpitSupervisorOperationSchema.document()[r'$defs']!
          as Map<Object?, Object?>,
    );
    for (final kind in <String>['ui.waitIdle', 'ui.remote.waitIdle']) {
      final descriptor = CockpitSupervisorOperationCatalog.allOperations
          .singleWhere((item) => item.kind == kind);
      final schema = Map<String, Object?>.from(
        definitions['$kind.request']! as Map<Object?, Object?>,
      );
      final properties = Map<String, Object?>.from(
        schema['properties']! as Map<Object?, Object?>,
      );
      final timeout = Map<String, Object?>.from(
        properties['timeoutMs']! as Map<Object?, Object?>,
      );
      final quiet = Map<String, Object?>.from(
        properties['quietWindowMs']! as Map<Object?, Object?>,
      );

      expect(descriptor.defaultTimeoutMs, 30000, reason: kind);
      expect(descriptor.maximumTimeoutMs, 300000, reason: kind);
      expect(timeout['default'], 30000, reason: kind);
      expect(timeout['maximum'], 300000, reason: kind);
      expect(quiet['default'], 500, reason: kind);
      expect(quiet['minimum'], 50, reason: kind);
      expect(quiet['maximum'], 60000, reason: kind);
      expect(
        JsonSchema.create(schema).validate(<String, Object?>{
          'sessionId': 'session-1',
          'quietWindowMs': 60000,
          'timeoutMs': 120000,
          'includeNetworkIdle': false,
        }).isValid,
        isTrue,
        reason: kind,
      );
      expect(
        JsonSchema.create(schema).validate(<String, Object?>{
          'sessionId': 'session-1',
          'timeoutMs': 300001,
        }).isValid,
        isFalse,
        reason: kind,
      );
    }
  });
}
