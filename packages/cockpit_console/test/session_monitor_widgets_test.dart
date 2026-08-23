import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_detail.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_runtime_views.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_session_list.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  setUpAll(initializeConsoleLocalization);
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('session list keeps multiple projects and sessions distinct', (
    tester,
  ) async {
    final sessions = [
      _session(workspace: 'ws-a', session: 'session-a', project: 'alpha'),
      _session(
        workspace: 'ws-a',
        session: 'session-b',
        project: 'alpha',
        platform: 'android',
      ),
      _session(workspace: 'ws-b', session: 'session-c', project: 'beta'),
    ];
    SessionMonitorKey? selected;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SessionMonitorSessionList(
                sessions: sessions,
                selected: sessions.first.key,
                onSelect: (key) => selected = key,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('macos · session-a'), findsOneWidget);
    expect(find.text('android · session-b'), findsOneWidget);
    expect(find.text('macos · session-c'), findsOneWidget);

    await tester.tap(find.text('android · session-b'));
    expect(selected, sessions[1].key);
  });

  testWidgets('compact picker switches the exact session identity', (
    tester,
  ) async {
    final sessions = [
      _session(workspace: 'ws-a', session: 'session-a', project: 'alpha'),
      _session(workspace: 'ws-b', session: 'session-b', project: 'beta'),
    ];
    SessionMonitorKey? selected;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: Scaffold(
            body: SessionMonitorCompactPicker(
              sessions: sessions,
              selected: sessions.first.key,
              onSelect: (key) => selected = key,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();

    expect(selected, sessions[1].key);
  });

  testWidgets('activity timeline is newest first, filtered, and progressive', (
    tester,
  ) async {
    final detail = SessionMonitorDetail(
      activity: <SessionMonitorActivity>[
        SessionMonitorActivity(
          at: DateTime.utc(2026, 8, 22, 12),
          kind: SessionMonitorActivityKind.discovered,
          severity: SessionMonitorSeverity.success,
          platform: 'macos',
          device: 'Mac',
        ),
        SessionMonitorActivity(
          at: DateTime.utc(2026, 8, 22, 13),
          kind: SessionMonitorActivityKind.routeChanged,
          severity: SessionMonitorSeverity.info,
          from: '/projects',
          to: '/sessions',
        ),
        SessionMonitorActivity(
          at: DateTime.utc(2026, 8, 22, 14),
          kind: SessionMonitorActivityKind.runtimeError,
          severity: SessionMonitorSeverity.error,
          count: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              height: 520,
              child: SessionActivityView(detail: detail),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('Runtime error captured')).dy,
      lessThan(tester.getTopLeft(find.text('Route changed')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Route changed')).dy,
      lessThan(tester.getTopLeft(find.text('Session discovered')).dy),
    );
    expect(find.textContaining('Runtime · Error'), findsNothing);

    await tester.tap(find.text('Runtime error captured'));
    await tester.pump();
    expect(find.textContaining('Runtime · Error'), findsOneWidget);

    await tester.tap(find.text('Route changed'));
    await tester.pump();
    expect(find.textContaining('Runtime · Error'), findsNothing);
    expect(find.textContaining('Routes · Info'), findsOneWidget);

    await tester.tap(find.text('Routes'));
    await tester.pump();
    expect(find.text('Route changed'), findsOneWidget);
    expect(find.text('Runtime error captured'), findsNothing);
    expect(find.text('Session discovered'), findsNothing);
    expect(find.textContaining('1 / 3'), findsOneWidget);
  });

  testWidgets('activity timeline lazily builds visible rows', (tester) async {
    final activity = List<SessionMonitorActivity>.generate(
      500,
      (index) => SessionMonitorActivity(
        at: DateTime.utc(2026, 8, 22).add(Duration(seconds: index)),
        kind: SessionMonitorActivityKind.routeChanged,
        severity: SessionMonitorSeverity.info,
        from: '/route-$index',
        to: '/route-${index + 1}',
      ),
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              height: 420,
              child: SessionActivityView(
                detail: SessionMonitorDetail(activity: activity),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('/route-499 → /route-500'), findsOneWidget);
    expect(find.text('/route-0 → /route-1'), findsNothing);
    expect(find.textContaining('500 / 500'), findsOneWidget);
  });

  testWidgets('logs are independently collapsible, selectable, and copyable', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const detail = SessionMonitorDetail(
      sessionLogs: <String, Object?>{
        'logPath': '/tmp/session.log',
        'lines': <String>['startup-old', 'startup-new'],
        'truncated': false,
      },
      logs: <String, Object?>{
        'source': 'app_snapshot',
        'lines': <String>['app-old', 'app-new'],
        'truncated': false,
      },
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: const Scaffold(
            body: SizedBox(height: 640, child: SessionLogsView(detail: detail)),
          ),
        ),
      ),
    );

    expect(find.text('Startup and Flutter tool logs'), findsOneWidget);
    expect(find.text('Application logs'), findsOneWidget);
    expect(find.textContaining('Refreshes every 2 seconds'), findsNWidgets(2));
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('startup-new')).dy,
      greaterThan(tester.getTopLeft(find.text('startup-old')).dy),
    );
    expect(find.text('app-old'), findsNothing);
    expect(find.text('app-new'), findsNothing);

    await tester.tap(find.text('Application logs'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNWidgets(4));
    expect(
      tester.getTopLeft(find.text('app-new')).dy,
      greaterThan(tester.getTopLeft(find.text('app-old')).dy),
    );

    await tester.tap(find.byTooltip('Copy log lines').first);
    await tester.pump();
    expect(clipboardText, 'startup-old\nstartup-new');
    expect(find.byTooltip('Log lines copied'), findsOneWidget);
    expect(find.text('startup-new'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy log file path'));
    await tester.pump();
    expect(clipboardText, '/tmp/session.log');
    expect(find.byTooltip('Log file path copied'), findsOneWidget);
    expect(find.text('startup-new'), findsOneWidget);

    await tester.tap(find.text('Startup and Flutter tool logs'));
    await tester.pumpAndSettle();
    expect(find.text('startup-old'), findsNothing);
    expect(find.text('startup-new'), findsNothing);
  });

  testWidgets('diagnostic session logs stay compact and copyable', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const detail = SessionMonitorDetail(
      sessionLogs: <String, Object?>{
        'logPath': '/tmp/session.log',
        'lines': <String>['lifecycle-old', 'lifecycle-new'],
      },
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: const Scaffold(
            body: SizedBox(
              height: 640,
              child: SessionDiagnosticsView(detail: detail),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Session logs'), findsOneWidget);
    expect(find.text('lifecycle-new'), findsNothing);
    expect(find.byTooltip('Show log output'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy log lines'));
    await tester.pump();
    expect(clipboardText, 'lifecycle-old\nlifecycle-new');
    expect(find.byTooltip('Log lines copied'), findsOneWidget);

    await tester.tap(find.text('Session logs'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(find.text('lifecycle-old'), findsOneWidget);
    expect(find.text('lifecycle-new'), findsOneWidget);
    expect(find.byTooltip('Hide log output'), findsOneWidget);
  });

  testWidgets('log rows stay virtualized and pause refresh while scrolling', (
    tester,
  ) async {
    final lines = List<String>.generate(
      1000,
      (index) =>
          'line-$index ${List<String>.filled(12, 'long-value').join(' ')}',
      growable: false,
    );
    final scrollActivity = <bool>[];
    final detail = SessionMonitorDetail(
      sessionLogs: <String, Object?>{'lines': lines},
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: SessionLogsView(
                detail: detail,
                onScrollActivityChanged: scrollActivity.add,
              ),
            ),
          ),
        ),
      ),
    );

    final logList = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.itemExtent == 18,
    );
    expect(logList, findsOneWidget);
    expect(tester.widget<ListView>(logList).itemExtent, 18);
    expect(
      find.byType(SelectableText).evaluate().length,
      lessThan(lines.length),
    );
    expect(identical(stringList(lines), lines), isTrue);

    final gesture = await tester.startGesture(tester.getCenter(logList));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(scrollActivity.last, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scrollActivity.last, isFalse);
  });

  test('activity retention preserves newest events and dropped count', () {
    SessionMonitorActivity event(int value) => SessionMonitorActivity(
      at: DateTime.utc(2026, 8, 22).add(Duration(seconds: value)),
      kind: SessionMonitorActivityKind.changed,
      severity: SessionMonitorSeverity.info,
      value: '$value',
    );

    final window = retainSessionActivity(
      existing: List.generate(4, event),
      dropped: 2,
      additions: List.generate(4, (index) => event(index + 4)),
      limit: 5,
    );

    expect(window.entries.map((entry) => entry.value), [
      '3',
      '4',
      '5',
      '6',
      '7',
    ]);
    expect(window.dropped, 5);
  });

  testWidgets('session detail links preserve E2E navigation', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = _session(
      workspace: 'ws-a',
      session: 'session-a',
      project: 'alpha',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ConsoleTheme.build(Brightness.light),
            home: Scaffold(
              body: SessionMonitorDetailPane(
                session: session,
                section: SessionMonitorSection.overview,
                onSectionSelected: (_) {},
                detail: const SessionMonitorDetail(
                  identity: <String, Object?>{
                    'status': <String, Object?>{'state': 'ready'},
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tests'), findsOneWidget);
    expect(find.text('Runs'), findsOneWidget);
    await tester.tap(find.text('Tests'));
    await tester.pump();

    expect(container.read(navProvider), ConsoleNavDestination.documents);
    expect(container.read(selectedWorkspaceIdProvider), 'ws-a');
  });

  testWidgets('activity history follows the current locale', (tester) async {
    final detail = SessionMonitorDetail(
      activity: <SessionMonitorActivity>[
        SessionMonitorActivity(
          at: DateTime.utc(2026, 8, 22, 12),
          kind: SessionMonitorActivityKind.discovered,
          severity: SessionMonitorSeverity.info,
          platform: 'macos',
          device: 'Mac',
        ),
      ],
    );

    Widget app() => TranslationProvider(
      child: MaterialApp(
        theme: ConsoleTheme.build(Brightness.light),
        home: Scaffold(body: SessionActivityView(detail: detail)),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('Session discovered'), findsOneWidget);

    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.zhCn));
    await tester.pumpWidget(app());

    expect(find.text('发现会话'), findsOneWidget);
    expect(find.text('Session discovered'), findsNothing);
    expect(find.text('macos · Mac'), findsOneWidget);
  });
}

MonitoredSession _session({
  required String workspace,
  required String session,
  required String project,
  String platform = 'macos',
}) {
  return MonitoredSession(
    key: SessionMonitorKey(workspaceId: workspace, sessionId: session),
    projectPath: '/workspace/$project',
    projectName: project,
    targetId: 'target-$session',
    platform: platform,
    deviceId: 'device-$platform',
    targetKind: CockpitTargetKind.flutterApp,
    entrypoint: 'cockpit/main.dart',
    flavor: null,
    appId: 'app-$session',
    state: 'ready',
    lastSeenAt: DateTime.utc(2026, 8, 22),
    route: '/',
    appReachable: true,
    bridgeReachable: true,
  );
}
