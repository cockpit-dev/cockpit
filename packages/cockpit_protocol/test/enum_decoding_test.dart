import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('closed command and locator enum decoding', () {
    test('direct decoders reject malformed and unknown values with paths', () {
      expect(
        () => CockpitCommandType.fromJson(1, path: r'$.command.commandType'),
        throwsA(_formatExceptionAt(r'$.command.commandType')),
      );
      expect(
        () => CockpitCommandType.fromJson(
          'futureCommand',
          path: r'$.command.commandType',
        ),
        throwsA(_formatExceptionAt(r'$.command.commandType')),
      );
      expect(
        () => CockpitLocatorKind.fromJson(
          false,
          path: r'$.resolution.matchedKind',
        ),
        throwsA(_formatExceptionAt(r'$.resolution.matchedKind')),
      );
      expect(
        () => CockpitLocatorKind.fromJson(
          'futureLocator',
          path: r'$.resolution.matchedKind',
        ),
        throwsA(_formatExceptionAt(r'$.resolution.matchedKind')),
      );
    });

    test('capabilities report indexed command and locator paths', () {
      final commandJson = _capabilities().toJson();
      (commandJson['supportedCommands']! as List<Object?>)[1] = 'futureCommand';
      expect(
        () => CockpitCapabilities.fromJson(
          commandJson,
          path: r'$.status.capabilities',
        ),
        throwsA(
          _formatExceptionAt(r'$.status.capabilities.supportedCommands[1]'),
        ),
      );

      final locatorJson = _capabilities().toJson();
      (locatorJson['supportedLocatorStrategies']! as List<Object?>)[1] =
          'futureLocator';
      expect(
        () => CockpitCapabilities.fromJson(
          locatorJson,
          path: r'$.status.capabilities',
        ),
        throwsA(
          _formatExceptionAt(
            r'$.status.capabilities.supportedLocatorStrategies[1]',
          ),
        ),
      );
    });

    test('snapshot targets preserve their nested command path', () {
      final json = CockpitSnapshot(
        routeName: '/',
        visibleTargets: <CockpitSnapshotTarget>[
          CockpitSnapshotTarget(
            registrationId: 'targetA',
            routeName: '/',
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.tap,
            ],
          ),
        ],
      ).toJson();
      final target =
          (json['visibleTargets']! as List<Object?>).single
              as Map<String, Object?>;
      (target['supportedCommands']! as List<Object?>)[0] = 'futureCommand';

      expect(
        () => CockpitSnapshot.fromJson(json, path: r'$.response.snapshot'),
        throwsA(
          _formatExceptionAt(
            r'$.response.snapshot.visibleTargets[0].supportedCommands[0]',
          ),
        ),
      );
    });

    test('widget nodes preserve their nested action path', () {
      final json = CockpitWidgetTree(
        profile: CockpitWidgetTreeProfile.minimal,
        total: 1,
        visible: 1,
        truncated: false,
        nodes: <CockpitWidgetNode>[
          CockpitWidgetNode(
            node: 1,
            depth: 0,
            type: 'TextButton',
            visible: true,
            offstage: false,
            actions: const <CockpitCommandType>[CockpitCommandType.tap],
          ),
        ],
      ).toJson();
      final node =
          (json['nodes']! as List<Object?>).single as Map<String, Object?>;
      (node['actions']! as List<Object?>)[0] = 'futureCommand';

      expect(
        () => CockpitWidgetTree.fromJson(json, path: r'$.snapshot.tree'),
        throwsA(_formatExceptionAt(r'$.snapshot.tree.nodes[0].actions[0]')),
      );
    });

    test('command results preserve locator-resolution paths', () {
      final json = CockpitCommandResult(
        success: true,
        commandId: 'tapA',
        commandType: CockpitCommandType.tap,
        locatorResolution: const CockpitLocatorResolution(
          matchedKind: CockpitLocatorKind.text,
          matchedValue: 'Save',
        ),
        durationMs: 5,
      ).toJson();
      final resolution = json['locatorResolution']! as Map<String, Object?>;
      resolution['matchedKind'] = 'futureLocator';

      expect(
        () => CockpitCommandResult.fromJson(json, path: r'$.response.result'),
        throwsA(
          _formatExceptionAt(
            r'$.response.result.locatorResolution.matchedKind',
          ),
        ),
      );
    });
  });
}

CockpitCapabilities _capabilities() => CockpitCapabilities(
  platform: 'test',
  transportType: 'inApp',
  supportsInAppControl: true,
  supportsFlutterViewCapture: true,
  supportsNativeScreenCapture: false,
  supportsHostAutomation: false,
  supportedCommands: const <CockpitCommandType>[
    CockpitCommandType.tap,
    CockpitCommandType.enterText,
  ],
  supportedLocatorStrategies: const <CockpitLocatorKind>[
    CockpitLocatorKind.text,
    CockpitLocatorKind.key,
  ],
);

Matcher _formatExceptionAt(String path) => isA<FormatException>().having(
  (error) => error.message.toString(),
  'message',
  contains(path),
);
