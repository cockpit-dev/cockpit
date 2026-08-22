import 'package:flutter_cockpit/flutter_cockpit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses one discovered target set across a diagnostic read', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');
    var discoveryCount = 0;
    registry.discoveredTargetsProvider = () {
      discoveryCount += 1;
      return const <CockpitTarget>[
        CockpitTarget(
          registrationId: 'task',
          text: 'Open task',
          routeName: '/inbox',
        ),
      ];
    };

    final values = registry.withDiscoverySnapshot(
      () => <int>[
        registry.visibleTargets.length,
        registry.routeReadyVisibleTargets.length,
        registry.routeDiagnostics()['visibleTargetCount']! as int,
      ],
    );

    expect(values, <int>[1, 1, 1]);
    expect(discoveryCount, 1);
  });

  test('resolves registered targets without invoking discovery', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');
    var discoveryCount = 0;
    registry.discoveredTargetsProvider = () {
      discoveryCount += 1;
      return const <CockpitTarget>[];
    };
    registry.register(
      CockpitTarget(
        registrationId: 'open-task',
        keyValue: 'open-task',
        routeName: '/inbox',
        supportedCommands: const <CockpitCommandType>{CockpitCommandType.tap},
        onTap: () {},
      ),
    );

    final result = registry.resolveRegistered(
      const CockpitLocator(key: 'open-task'),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(result.isSuccess, isTrue);
    expect(result.target?.registrationId, 'open-task');
    expect(discoveryCount, 0);
  });

  test('registers visible targets with metadata and supported commands', () {
    final registry = CockpitTargetRegistry(routeName: '/checkout');

    registry.register(
      const CockpitTarget(
        registrationId: 'submit-1',
        cockpitId: 'submit_button',
        semanticId: 'checkout_submit',
        text: 'Submit order',
        routeName: '/checkout',
        supportedCommands: {
          CockpitCommandType.tap,
          CockpitCommandType.assertVisible,
        },
      ),
    );

    expect(registry.visibleTargets, hasLength(1));
    expect(registry.visibleTargets.single.cockpitId, 'submit_button');
    expect(
      registry.visibleTargets.single.supportedCommands,
      containsAll(<CockpitCommandType>[
        CockpitCommandType.tap,
        CockpitCommandType.assertVisible,
      ]),
    );
  });

  test('snapshot targets retain locator ancestor metadata', () {
    const ancestors = <CockpitSnapshotAncestor>[
      CockpitSnapshotAncestor(typeName: 'Dialog'),
      CockpitSnapshotAncestor(typeName: 'Scaffold'),
    ];
    const target = CockpitTarget(
      registrationId: 'confirm-1',
      text: 'Save',
      routeName: '/editor',
      locatorAncestors: ancestors,
    );

    expect(target.toSnapshotTarget().ancestors, ancestors);
  });

  test('resolves targets by locator priority and fallback order', () {
    final registry = CockpitTargetRegistry(routeName: '/checkout');

    registry.register(
      const CockpitTarget(
        registrationId: 'semantic-match',
        semanticId: 'checkout_submit',
        text: 'Submit order',
        routeName: '/checkout',
        supportedCommands: {CockpitCommandType.tap},
      ),
    );
    registry.register(
      const CockpitTarget(
        registrationId: 'text-match',
        text: 'Submit order',
        routeName: '/checkout',
        supportedCommands: {CockpitCommandType.tap},
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(
        cockpitId: 'missing_button',
        fallbacks: [
          CockpitLocator(semanticId: 'checkout_submit'),
          CockpitLocator(text: 'Submit order'),
        ],
      ),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'semantic-match');
    expect(
      resolution.locatorResolution,
      const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.semanticId,
        matchedValue: 'checkout_submit',
      ),
    );
  });

  test(
    'reports ambiguity when a fallback locator matches multiple targets',
    () {
      final registry = CockpitTargetRegistry(routeName: '/checkout');

      registry.register(
        const CockpitTarget(
          registrationId: 'primary',
          text: 'Continue',
          routeName: '/checkout',
          supportedCommands: {CockpitCommandType.tap},
        ),
      );
      registry.register(
        const CockpitTarget(
          registrationId: 'secondary',
          text: 'Continue',
          routeName: '/checkout',
          supportedCommands: {CockpitCommandType.tap},
        ),
      );

      final resolution = registry.resolve(
        const CockpitLocator(
          cockpitId: 'missing_button',
          fallbacks: [CockpitLocator(text: 'Continue')],
        ),
      );

      expect(resolution.isSuccess, isFalse);
      expect(resolution.error?.code, CockpitCommandError.ambiguousTargetCode);
      expect(
        resolution.matches.map((target) => target.registrationId),
        containsAll(<String>['primary', 'secondary']),
      );
      final candidateHints =
          (resolution.error?.details['candidateHints'] as List<Object?>?)
              ?.cast<Map<Object?, Object?>>()
              .map((entry) => Map<String, Object?>.from(entry))
              .toList(growable: false) ??
          const <Map<String, Object?>>[];
      expect(candidateHints, hasLength(1));
      expect(candidateHints.first['text'], 'Continue');
      expect(candidateHints.first['type'], isNull);
    },
  );

  test('caps raw ambiguous candidate ids while preserving the total count', () {
    final registry = CockpitTargetRegistry(routeName: '/checkout');

    for (var index = 0; index < 16; index += 1) {
      registry.register(
        CockpitTarget(
          registrationId: 'candidate-$index',
          text: 'Continue',
          routeName: '/checkout',
          supportedCommands: const {CockpitCommandType.tap},
        ),
      );
    }

    final resolution = registry.resolve(const CockpitLocator(text: 'Continue'));

    expect(resolution.isSuccess, isFalse);
    expect(resolution.error?.code, CockpitCommandError.ambiguousTargetCode);
    expect(resolution.error?.details['candidateCount'], 16);
    final candidates =
        (resolution.error?.details['candidates'] as List<Object?>?)
            ?.cast<String>() ??
        const <String>[];
    expect(candidates.length, CockpitTargetRegistry.candidateDetailLimit);
    expect(candidates, isNot(contains('candidate-9')));
  });

  test('resolves targets by native widget key', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');

    registry.register(
      const CockpitTarget(
        registrationId: 'task-row-42',
        keyValue: 'task-item:42',
        text: 'Review docs',
        routeName: '/inbox',
        supportedCommands: {CockpitCommandType.tap},
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(key: 'task-item:42'),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'task-row-42');
    expect(
      resolution.locatorResolution,
      const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.key,
        matchedValue: 'task-item:42',
      ),
    );
  });

  test('resolves semantic labels with explicit text matching modes', () {
    final registry = CockpitTargetRegistry(routeName: '/dashboard');
    registry.register(
      const CockpitTarget(
        registrationId: 'dashboard-navigation',
        semanticId: 'Open Dashboard navigation',
        routeName: '/dashboard',
        supportedCommands: {CockpitCommandType.tap},
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(
        semanticId: 'Dashboard navigation',
        matchMode: CockpitTextMatchMode.contains,
      ),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(resolution.isSuccess, isTrue, reason: '${resolution.error}');
    expect(resolution.target?.registrationId, 'dashboard-navigation');
    expect(
      resolution.locatorResolution?.matchedKind,
      CockpitLocatorKind.semanticId,
    );
  });

  test('caps live snapshots and prioritizes actionable keyed targets', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');

    for (
      var index = 0;
      index < CockpitTargetRegistry.liveSnapshotTargetLimit + 32;
      index += 1
    ) {
      registry.register(
        CockpitTarget(
          registrationId: 'target-$index',
          keyValue: index < 4 ? 'key-$index' : null,
          text: 'Target $index',
          routeName: '/inbox',
          supportedCommands: index < 4
              ? const {CockpitCommandType.tap}
              : const <CockpitCommandType>{},
        ),
      );
    }

    final snapshot = registry.snapshot();

    expect(
      snapshot.visibleTargets,
      hasLength(CockpitTargetRegistry.liveSnapshotTargetLimit),
    );
    expect(snapshot.truncated, isTrue);
    expect(
      snapshot.summary?.visibleTargetCount,
      greaterThan(CockpitTargetRegistry.liveSnapshotTargetLimit),
    );
    expect(
      snapshot.visibleTargets.take(4).map((target) => target.keyValue),
      <String?>['key-0', 'key-1', 'key-2', 'key-3'],
    );
  });

  test('reuses discovered targets during a single registry snapshot', () {
    var discoveryCalls = 0;
    final registry = CockpitTargetRegistry(routeName: '/inbox')
      ..discoveredTargetsProvider = () {
        discoveryCalls += 1;
        return const <CockpitTarget>[
          CockpitTarget(
            registrationId: 'new-task',
            keyValue: 'fab-add-task',
            text: 'New task',
            routeName: '/inbox',
            supportedCommands: {CockpitCommandType.tap},
          ),
        ];
      };

    final snapshot = registry.snapshot();

    expect(snapshot.visibleTargets, hasLength(1));
    expect(snapshot.summary?.visibleTargetCount, 1);
    expect(snapshot.summary?.targetsWithTextCount, 1);
    expect(discoveryCalls, 1);
  });

  test('live snapshots omit locator ancestor diagnostics', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox')
      ..register(
        const CockpitTarget(
          registrationId: 'new-task',
          keyValue: 'fab-add-task',
          text: 'New task',
          routeName: '/inbox',
          supportedCommands: {CockpitCommandType.tap},
          locatorAncestors: <CockpitSnapshotAncestor>[
            CockpitSnapshotAncestor(typeName: 'Scaffold', path: '/scaffold'),
          ],
        ),
      );

    final snapshot = registry.snapshot();

    expect(snapshot.visibleTargets.single.ancestors, isEmpty);
  });

  test('reuses discovered targets while resolving fallback locator chains', () {
    var discoveryCalls = 0;
    final registry = CockpitTargetRegistry(routeName: '/inbox')
      ..discoveredTargetsProvider = () {
        discoveryCalls += 1;
        return const <CockpitTarget>[
          CockpitTarget(
            registrationId: 'new-task',
            keyValue: 'fab-add-task',
            text: 'New task',
            routeName: '/inbox',
            supportedCommands: {CockpitCommandType.tap},
          ),
        ];
      };

    final resolution = registry.resolve(
      const CockpitLocator(
        cockpitId: 'missing',
        fallbacks: <CockpitLocator>[CockpitLocator(text: 'New task')],
      ),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'new-task');
    expect(discoveryCalls, 1);
  });

  test(
    'falls back to unresolved discovered targets when route filtering would otherwise empty the visible surface',
    () {
      final registry = CockpitTargetRegistry(routeName: '/settings')
        ..discoveredTargetsProvider = () => const <CockpitTarget>[
          CockpitTarget(
            registrationId: 'save-settings',
            text: 'Save settings',
            routeName: '',
            supportedCommands: {CockpitCommandType.tap},
          ),
        ];

      expect(registry.visibleTargets, hasLength(1));
      expect(registry.visibleTargets.single.registrationId, 'save-settings');
      expect(registry.snapshot().summary?.visibleTargetCount, 1);
    },
  );

  test(
    'falls back to discovered targets from inactive routes when no current-route targets are discoverable',
    () {
      final registry = CockpitTargetRegistry(routeName: '/editor')
        ..discoveredTargetsProvider = () => const <CockpitTarget>[
          CockpitTarget(
            registrationId: 'inbox-new-task',
            text: 'New task',
            routeName: '/inbox',
            supportedCommands: {CockpitCommandType.tap},
          ),
        ];

      expect(registry.visibleTargets, hasLength(1));
      expect(registry.visibleTargets.single.registrationId, 'inbox-new-task');
      expect(registry.snapshot().summary?.visibleTargetCount, 1);
    },
  );

  test('prefers a unique actionable keyed match over passive duplicates', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');

    registry.register(
      const CockpitTarget(
        registrationId: 'open-action',
        semanticId: 'Open task Gesture alpha',
        keyValue: 'task-open-123',
        text: 'Gesture alpha',
        routeName: '/inbox',
        supportedCommands: {CockpitCommandType.tap},
      ),
    );
    registry.register(
      const CockpitTarget(
        registrationId: 'open-passive-text',
        semanticId: 'Open task Gesture alpha',
        text: 'Gesture alpha',
        routeName: '/inbox',
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(semanticId: 'Open task Gesture alpha'),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'open-action');
  });

  test('resolves compound locators with path suffix and ancestor chain', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');

    registry.register(
      const CockpitTarget(
        registrationId: 'today-nav-label',
        text: 'Today',
        typeName: 'NavigationDestinationLabel',
        path: '/scaffold/navigationbar/navigationdestinationlabel',
        routeName: '/inbox',
        supportedCommands: {CockpitCommandType.tap},
        locatorAncestors: <CockpitSnapshotAncestor>[
          CockpitSnapshotAncestor(typeName: 'NavigationDestination'),
          CockpitSnapshotAncestor(typeName: 'NavigationBar'),
          CockpitSnapshotAncestor(typeName: 'Scaffold'),
        ],
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(
        text: 'Today',
        type: 'NavigationDestinationLabel',
        path:
            '/scaffold.body/navigation_bar/destinations/0/navigation_destination_label',
        ancestor: CockpitLocator(
          type: 'NavigationBar',
          ancestor: CockpitLocator(type: 'Scaffold'),
        ),
      ),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'today-nav-label');
    expect(
      resolution.locatorResolution,
      const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.text,
        matchedValue: 'Today',
        matchedSignals: <String, String>{
          'text': 'Today',
          'type': 'NavigationDestinationLabel',
          'path':
              '/scaffold.body/navigation_bar/destinations/0/navigation_destination_label',
        },
      ),
    );
  });

  test('treats a route-only ancestor locator as a route scope', () {
    final registry = CockpitTargetRegistry(routeName: '/editor');

    registry.register(
      const CockpitTarget(
        registrationId: 'editor-title-input',
        text: 'Task title',
        routeName: '/editor',
        supportedCommands: {CockpitCommandType.enterText},
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(
        text: 'Task title',
        ancestor: CockpitLocator(route: '/editor'),
      ),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'editor-title-input');
    expect(
      resolution.locatorResolution,
      const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.text,
        matchedValue: 'Task title',
        matchedSignals: <String, String>{'text': 'Task title'},
      ),
    );
  });

  test('resolves duplicate matches by locator index in UI order', () {
    final registry = CockpitTargetRegistry(routeName: '/inbox');

    registry.register(
      CockpitTarget(
        registrationId: 'open-first',
        text: 'Open',
        typeName: 'TextButton',
        routeName: '/inbox',
        supportedCommands: const {CockpitCommandType.tap},
        geometryProvider: () => const CockpitTargetGeometry(
          left: 12,
          top: 24,
          width: 40,
          height: 20,
          viewportLeft: 0,
          viewportTop: 0,
          viewportWidth: 320,
          viewportHeight: 640,
          viewId: 1,
        ),
      ),
    );
    registry.register(
      CockpitTarget(
        registrationId: 'open-second',
        text: 'Open',
        typeName: 'TextButton',
        routeName: '/inbox',
        supportedCommands: const {CockpitCommandType.tap},
        geometryProvider: () => const CockpitTargetGeometry(
          left: 12,
          top: 96,
          width: 40,
          height: 20,
          viewportLeft: 0,
          viewportTop: 0,
          viewportWidth: 320,
          viewportHeight: 640,
          viewId: 1,
        ),
      ),
    );

    final resolution = registry.resolve(
      const CockpitLocator(text: 'Open', type: 'TextButton', index: 1),
    );

    expect(resolution.isSuccess, isTrue);
    expect(resolution.target?.registrationId, 'open-second');
    expect(
      resolution.locatorResolution,
      const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.text,
        matchedValue: 'Open',
        matchedSignals: <String, String>{
          'text': 'Open',
          'type': 'TextButton',
          'index': '1',
        },
      ),
    );
  });

  test('uses explicit text modes and selects only a unique best match', () {
    final registry = CockpitTargetRegistry(routeName: '/editor');
    registry.register(
      const CockpitTarget(
        registrationId: 'save-exact',
        text: 'Save task',
        routeName: '/editor',
      ),
    );
    registry.register(
      const CockpitTarget(
        registrationId: 'save-longer',
        text: 'Save task permanently',
        routeName: '/editor',
      ),
    );

    expect(
      registry.resolve(const CockpitLocator(text: 'Save')).isSuccess,
      isFalse,
    );

    final resolution = registry.resolve(
      const CockpitLocator(
        text: 'Save task',
        matchMode: CockpitTextMatchMode.contains,
      ),
    );

    expect(resolution.target?.registrationId, 'save-exact');
    expect(resolution.locatorResolution?.matchedSignals, <String, String>{
      'text': 'Save task',
      'matchMode': 'contains',
    });

    final fuzzyResolution = registry.resolve(
      const CockpitLocator(
        text: 'Svae task',
        matchMode: CockpitTextMatchMode.fuzzy,
      ),
    );
    expect(fuzzyResolution.target?.registrationId, 'save-exact');
  });

  test('returns ambiguity when regex candidates share the best score', () {
    final registry = CockpitTargetRegistry(routeName: '/tasks');
    for (final entry in const <(String, String)>[
      ('task-one', 'Task 1'),
      ('task-two', 'Task 2'),
    ]) {
      registry.register(
        CockpitTarget(
          registrationId: entry.$1,
          text: entry.$2,
          routeName: '/tasks',
        ),
      );
    }

    final resolution = registry.resolve(
      const CockpitLocator(
        text: r'^Task \d$',
        matchMode: CockpitTextMatchMode.regex,
      ),
    );

    expect(resolution.error?.code, CockpitCommandError.ambiguousTargetCode);
  });
}
