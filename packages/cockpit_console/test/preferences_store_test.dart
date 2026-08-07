import 'dart:io';

import 'package:cockpit_console/src/providers/preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  group('PreferencesStore', () {
    late Directory directory;
    late PreferencesStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'cockpit-console-preferences-',
      );
      store = await PreferencesStore.initialize(storagePath: directory.path);
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('persists supported values across reads', () async {
      await store.setSelectedWorkspaceId('workspace-1');
      await store.setFontScale(1.2);
      await store.setCustomAgentArgs(<String>['--mode', 'acp']);

      expect(store.selectedWorkspaceId, 'workspace-1');
      expect(store.fontScale, 1.2);
      expect(store.customAgentArgs, <String>['--mode', 'acp']);
    });

    test('recovers safe defaults from corrupt persisted values', () async {
      final box = Hive.box<Object?>('cockpit_console');
      await box.put('selectedWorkspaceId', 42);
      await box.put('sidebarCollapsed', 'yes');
      await box.put('fontScale', 'large');
      await box.put('lastAgentId', false);
      await box.put('customAgentArgs', <Object?>['--valid', 7]);
      await box.put('chatHistory', <Object?>[
        <Object?, Object?>{'role': 'user', 3: 'discarded'},
        'discarded',
      ]);

      expect(store.selectedWorkspaceId, isNull);
      expect(store.sidebarCollapsed, isFalse);
      expect(store.fontScale, 1.0);
      expect(store.lastAgentId, isNull);
      expect(store.customAgentArgs, <String>['--valid']);
      expect(store.chatHistory, <Map<String, Object?>>[
        <String, Object?>{'role': 'user'},
      ]);
      expect(
        () => store.chatHistory.single['later'] = true,
        throwsUnsupportedError,
      );
    });

    test('clamps persisted font scale at the read boundary', () async {
      final box = Hive.box<Object?>('cockpit_console');
      await box.put('fontScale', 100);
      expect(store.fontScale, 1.3);
      await box.put('fontScale', 0.1);
      expect(store.fontScale, 0.85);
    });
  });

  group('resolveConsoleStorageDirectory', () {
    test('uses XDG data home on Linux', () {
      expect(
        PreferencesStore.resolveConsoleStorageDirectory(
          environment: const <String, String>{
            'HOME': '/home/tester',
            'XDG_DATA_HOME': '/data/tester',
          },
          operatingSystem: 'linux',
        ),
        '/data/tester/cockpit-console',
      );
    });

    test('requires a home directory when no platform location exists', () {
      expect(
        () => PreferencesStore.resolveConsoleStorageDirectory(
          environment: const <String, String>{},
          operatingSystem: 'linux',
        ),
        throwsStateError,
      );
    });
  });
}
