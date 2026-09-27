import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

void main() {
  test('integration commands have bounded defaults', () {
    const options = CockpitTestOptions();
    expect(options.commandTimeout, const Duration(seconds: 10));
    expect(options.nativeTimeout, const Duration(minutes: 2));
  });

  cockpitTestWidgets(
    'controls and restores DevTools debug switches',
    app: () => const _TestApp(),
    body: (cockpit) async {
      final before = cockpit.debug.current;
      final applied = cockpit.debug.apply(
        paintSize: true,
        repaintRainbow: true,
        performanceOverlay: true,
        timeScale: 3,
      );
      expect(applied.paintSize, isTrue);
      expect(applied.repaintRainbow, isTrue);
      expect(applied.performanceOverlay, isTrue);
      expect(applied.timeDilation, 3);
      final restored = cockpit.debug.restore();
      expect(restored.paintSize, before.paintSize);
      expect(restored.repaintRainbow, before.repaintRainbow);
      expect(restored.performanceOverlay, before.performanceOverlay);
      expect(restored.timeDilation, before.timeDilation);
    },
  );

  cockpitTestWidgets(
    'runs selector actions through the in-app executor',
    app: () => const _TestApp(),
    body: (cockpit) async {
      final capabilities = await cockpit.describeCapabilities();
      expect(capabilities.supportsInAppControl, isTrue);
      final tap = await cockpit.tap('Save');
      expect(tap.result.success, isTrue, reason: tap.result.error?.message);
      await cockpit.expectText('Saved', 'Saved');
    },
  );

  cockpitScenarioWidgets(
    'runs a shared platform-neutral scenario',
    app: () => const _TestApp(),
    scenario: CockpitTestScenario(
      id: 'shared-save',
      requirements: CockpitTestRequirements(
        commands: const <CockpitCommandType>{
          CockpitCommandType.tap,
          CockpitCommandType.assertText,
        },
        locators: const <CockpitLocatorKind>{CockpitLocatorKind.text},
        features: const <CockpitTestFeature>{CockpitTestFeature.inAppControl},
      ),
      body: (tester) async {
        await tester.tap('Save');
        await tester.expectText('Saved', 'Saved');
      },
    ),
  );

  cockpitTestWidgets(
    'preserves Flutter locale script and region subtags',
    app: () => const MaterialApp(
      locale: Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
      supportedLocales: <Locale>[
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      ],
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SizedBox.expand(),
    ),
    body: (cockpit) async {
      expect(cockpit.locale.toLanguageTag(), 'zh-Hant-TW');
      expect(cockpit.locale.scriptCode, 'Hant');
      expect(cockpit.locale.regionCode, 'TW');
    },
  );

  final locale = ValueNotifier<String>('en');
  final saved = ValueNotifier<bool>(false);
  final confirmed = ValueNotifier<bool>(false);
  final selectedPeriod = ValueNotifier<int>(0);
  cockpitTestWidgets(
    're-resolves complex translated selectors after repeated locale changes',
    app: () => _LocaleTestApp(
      locale: locale,
      saved: saved,
      confirmed: confirmed,
      selectedPeriod: selectedPeriod,
    ),
    body: (cockpit) async {
      expect(Localizations.localeOf(cockpit.context), const Locale('en'));
      await cockpit.tap(_localeLabels(locale.value).switchLanguage);
      await cockpit.waitForUi();
      expect(locale.value, 'zh-CN');
      expect(Localizations.localeOf(cockpit.context), const Locale('zh', 'CN'));

      final staleEnglish = await cockpit.execute(
        CockpitCommand(
          commandId: 'stale-locale-label',
          commandType: CockpitCommandType.tap,
          locator: CockpitSelector.parse('Save'),
        ),
        check: false,
      );
      expect(staleEnglish.result.success, isFalse);
      expect(
        staleEnglish.result.error?.code,
        CockpitCommandError.targetNotFoundCode,
      );

      final labels = _localeLabels(locale.value);
      await cockpit.tap(labels.save);
      await cockpit.expectText(labels.saved, labels.saved);
      await cockpit.type('买入', into: labels.message);
      await cockpit.tap('Text["${labels.period4h}"]');
      expect(selectedPeriod.value, 1);
      await cockpit.tap(labels.openDialog);
      await cockpit.waitForUi();
      await cockpit.tap('Dialog >> Text["${labels.confirm}"]');
      await cockpit.expectText(labels.confirmed, labels.confirmed);

      await cockpit.tap(labels.switchLanguage);
      await cockpit.waitForUi();
      expect(locale.value, 'ar');
      expect(Localizations.localeOf(cockpit.context), const Locale('ar'));
      final arabicLabels = _localeLabels(locale.value);
      expect(find.text(labels.save), findsNothing);
      await cockpit.tap(arabicLabels.save);
      await cockpit.expectText(arabicLabels.saved, arabicLabels.saved);
      await cockpit.type('شراء', into: arabicLabels.message);
      await cockpit.tap('Text["${arabicLabels.period4h}"]');
      expect(selectedPeriod.value, 1);
      await cockpit.tap(arabicLabels.openDialog);
      await cockpit.waitForUi();
      await cockpit.tap('Dialog >> Text["${arabicLabels.confirm}"]');
      await cockpit.expectText(arabicLabels.confirmed, arabicLabels.confirmed);

      await cockpit.tap(arabicLabels.switchLanguage);
      await cockpit.waitForUi();
      expect(locale.value, 'en');
      expect(Localizations.localeOf(cockpit.context), const Locale('en'));
      final englishLabels = _localeLabels(locale.value);
      await cockpit.tap(englishLabels.save);
      await cockpit.expectText(englishLabels.saved, englishLabels.saved);
      await cockpit.type('buy', into: englishLabels.message);
      await cockpit.tap('Text["${englishLabels.period4h}"]');
      expect(selectedPeriod.value, 1);
    },
  );

  cockpitTestWidgets(
    'context reports a missing localization boundary clearly',
    app: () => const SizedBox.expand(),
    body: (cockpit) async {
      expect(
        () => cockpit.context,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No visible application Localizations boundary'),
          ),
        ),
      );
    },
  );

  cockpitTestWidgets(
    'context keeps the app locale when an overlay has a nested override',
    app: () => const _NestedLocaleOverrideApp(),
    body: (cockpit) async {
      expect(Localizations.localeOf(cockpit.context), const Locale('en'));
      expect(find.text('Nested override'), findsOneWidget);

      await cockpit.flutter.tap(find.text('Open dialog'));
      await cockpit.flutter.pumpAndSettle();
      expect(find.text('Dialog override'), findsOneWidget);
      expect(Localizations.localeOf(cockpit.context), const Locale('en'));
      await cockpit.tap('Dialog >> Text["Close"]');
      await cockpit.waitForUi();
      expect(find.text('Dialog override'), findsNothing);
      expect(Localizations.localeOf(cockpit.context), const Locale('en'));
    },
  );

  final reorderedLabels = <String>[];
  cockpitTestWidgets(
    'dragTo reorders a list from one resolved target to another',
    app: () => _ReorderTestApp(
      onReordered: (labels) {
        reorderedLabels
          ..clear()
          ..addAll(labels);
      },
    ),
    body: (cockpit) async {
      final result = await cockpit.dragTo(
        from: 'Drag Third',
        to: 'Drop First',
        placement: 'before',
        duration: const Duration(milliseconds: 240),
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(reorderedLabels, <String>['Third', 'First', 'Second']);
    },
  );

  cockpitTestWidgets(
    'supports sequential performance segments in one integration test',
    app: () => const _TestApp(),
    body: (cockpit) async {
      final first = await cockpit.beginPerformance(name: 'first');
      await cockpit.flutter.pump();
      final firstReport = await first.end();

      final second = await cockpit.beginPerformance(
        name: 'second',
        mode: CockpitPerformanceMode.light,
      );
      await cockpit.flutter.pump();
      final secondReport = await second.end();

      expect(firstReport.stepId, 'first');
      expect(secondReport.stepId, 'second');
      expect(cockpit.performanceReports, hasLength(2));
      expect(
        cockpit.performanceReports.map((report) => report.stepId),
        <String?>['first', 'second'],
      );
    },
  );

  cockpitTestWidgets(
    'uses the native timeout for explicit host actions',
    app: () => const _TestApp(),
    options: CockpitTestOptions(hostCommand: _successfulHostCommand),
    body: (cockpit) async {
      final result = await cockpit.host.action('dismiss');
      expect(result.result.success, isTrue);
      expect(result.result.commandType, CockpitCommandType.system);
      expect(result.result.durationMs, isNonNegative);
    },
  );

  cockpitTestWidgets(
    'collects a command snapshot and clears network activity',
    app: () => const _TestApp(),
    options: CockpitTestOptions(failFast: false),
    body: (cockpit) async {
      final snapshot = await cockpit.collectSnapshot();
      expect(snapshot.visibleTargets, isNotEmpty);
      final cleared = await cockpit.clearNetworkActivity();
      expect(cleared.result.success, isFalse);
      expect(cleared.result.error?.code, 'unsupportedCapability');
      expect(
        cockpit.report['steps'],
        contains(
          predicate<Object?>((value) {
            final step = value! as Map<Object?, Object?>;
            return step['type'] == CockpitCommandType.collectSnapshot.name;
          }),
        ),
      );
    },
  );

  cockpitTestWidgets(
    'exposes typed host screenshot assertion and travel actions',
    app: () => const _TestApp(),
    options: CockpitTestOptions(hostCommand: _typedHostCommand),
    body: (cockpit) async {
      final screenshot = await cockpit.expectScreenshot(
        baseline: 'test/baselines/home.png',
        name: 'home',
      );
      expect(screenshot.result.success, isTrue);
      final travel = await cockpit.travel(const <CockpitTravelPoint>[
        CockpitTravelPoint(latitude: 31.2, longitude: 121.5),
        CockpitTravelPoint(
          latitude: 31.21,
          longitude: 121.51,
          delay: Duration(milliseconds: 10),
        ),
      ]);
      expect(travel.result.success, isTrue);
    },
  );

  cockpitTestWidgets(
    'long press timing and animation watch use real pointer and frame paths',
    app: () => const _AnimatedTestApp(),
    body: (cockpit) async {
      final hold = await cockpit.longPress(
        'Hold',
        duration: const Duration(milliseconds: 650),
      );
      expect(hold.result.success, isTrue, reason: hold.result.error?.message);
      await cockpit.expectText('Held', 'Held');

      await cockpit.flutter.tap(find.text('Animate'));
      await cockpit.flutter.pump();
      final watch = await cockpit.watch(
        query: 'Moving',
        duration: const Duration(milliseconds: 300),
        interval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 1),
      );

      expect(watch.samples, greaterThan(1));
      expect(watch.changed, isTrue);
      expect(watch.changes.any((change) => change.updated.isNotEmpty), isTrue);

      await cockpit.flutter.tap(find.text('Animate'));
      await cockpit.flutter.pump();

      final paintWatch = await cockpit.watch(
        query: 'Fading',
        duration: const Duration(milliseconds: 300),
        interval: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 1),
      );
      expect(paintWatch.changed, isTrue);
      expect(
        paintWatch.changes
            .expand((change) => change.updated)
            .any(
              (update) =>
                  (update['from'] as Map<Object?, Object?>?)?.containsKey(
                        'style',
                      ) ==
                      true ||
                  (update['to'] as Map<Object?, Object?>?)?.containsKey(
                        'style',
                      ) ==
                      true,
            ),
        isTrue,
      );
      expect(cockpit.report['watches'], hasLength(2));
      await cockpit.waitForUi();
    },
  );

  cockpitTestWidgets(
    'watch rejects an unbounded sampling request before pumping the app',
    app: () => const _TestApp(),
    body: (cockpit) async {
      await expectLater(
        cockpit.watch(
          duration: const Duration(seconds: 20),
          interval: const Duration(milliseconds: 1),
          timeout: const Duration(seconds: 30),
        ),
        throwsArgumentError,
      );
    },
  );

  var lastScale = 1.0;
  cockpitTestWidgets(
    'multi-touch facade dispatches a real two-pointer scale',
    app: () => _ScaleTestApp(onScale: (value) => lastScale = value),
    body: (cockpit) async {
      final result = await cockpit.multiTouch(
        const CockpitMultiTouchSequence(
          steps: <CockpitMultiTouchStep>[
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.down,
              atMs: 0,
              dx: -24,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 2,
              phase: CockpitMultiTouchPhase.down,
              atMs: 0,
              dx: 24,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.move,
              atMs: 120,
              dx: -72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 2,
              phase: CockpitMultiTouchPhase.move,
              atMs: 120,
              dx: 72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.up,
              atMs: 220,
              dx: -72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 2,
              phase: CockpitMultiTouchPhase.up,
              atMs: 220,
              dx: 72,
              dy: 0,
            ),
          ],
        ),
        at: const Offset(400, 300),
      );

      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(lastScale, greaterThan(1.4));
    },
  );

  var doubleTapped = false;
  cockpitTestWidgets(
    'double tap facade honors the requested interval',
    app: () => _DoubleTapTestApp(onDoubleTap: () => doubleTapped = true),
    body: (cockpit) async {
      final result = await cockpit.doubleTap(
        'Double',
        interval: const Duration(milliseconds: 120),
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(doubleTapped, isTrue);
    },
  );

  var hovered = false;
  cockpitTestWidgets(
    'hover facade dispatches a real mouse event to MouseRegion',
    app: () => _HoverTestApp(onHover: () => hovered = true),
    body: (cockpit) async {
      final capabilities = await cockpit.describeCapabilities();
      expect(
        capabilities.supportedCommands,
        contains(CockpitCommandType.hover),
      );
      final result = await cockpit.hover('Hover target');
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(hovered, isTrue);
    },
  );

  PointerDownEvent? pointerDown;
  cockpitTestWidgets(
    'pointer facade supports coordinate and device-specific input',
    app: () => _PointerProbeApp(onDown: (event) => pointerDown = event),
    body: (cockpit) async {
      final result = await cockpit.tap(
        null,
        at: const Offset(400, 300),
        device: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(pointerDown?.kind, PointerDeviceKind.mouse);
      expect(pointerDown?.buttons, kSecondaryButton);
    },
  );

  final wheelDeltas = <Offset>[];
  cockpitTestWidgets(
    'wheel facade dispatches bounded pointer scroll signals',
    app: () => _WheelTestApp(onWheel: wheelDeltas.add),
    body: (cockpit) async {
      final capabilities = await cockpit.describeCapabilities();
      expect(
        capabilities.supportedCommands,
        contains(CockpitCommandType.wheel),
      );
      final result = await cockpit.wheel(
        target: 'Wheel target',
        delta: const Offset(0, 40),
        steps: 2,
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      expect(wheelDeltas, <Offset>[const Offset(0, 40), const Offset(0, 40)]);
    },
  );

  cockpitTestWidgets(
    'scroll facade forwards a canonical scroll locator',
    app: () => const _ScrollTestApp(),
    body: (cockpit) async {
      final result = await cockpit.scroll(
        'Row 24',
        scrollLocator: '@outer-scroll',
        maxScrolls: 40,
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      await cockpit.expectVisible('Row 24');
    },
  );

  var hotkeyActivated = false;
  cockpitTestWidgets(
    'hotkey facade keeps modifiers pressed for Flutter shortcuts',
    app: () => _HotkeyTestApp(onSave: () => hotkeyActivated = true),
    body: (cockpit) async {
      final results = await cockpit.hotkey(const <String>[
        'ControlLeft',
        'KeyS',
      ]);
      expect(results, hasLength(3));
      expect(results.every((result) => result.result.success), isTrue);
      expect(hotkeyActivated, isTrue);
    },
  );

  cockpitTestWidgets(
    'text facade exposes focus, selection, and clear through native editing',
    app: () => const _TextInputTestApp(),
    body: (cockpit) async {
      final focused = await cockpit.focus('Message');
      expect(focused.result.success, isTrue);

      final replaced = await cockpit.setTextEditingValue(
        'Message',
        text: 'hello cockpit',
      );
      expect(replaced.result.success, isTrue);

      final selected = await cockpit.selectText('Message', start: 0, end: 5);
      expect(selected.result.success, isTrue);

      final cleared = await cockpit.clear('Message');
      expect(cleared.result.success, isTrue);
      final input = cockpit.snapshot().visibleTargets.firstWhere(
        (target) => target.text == 'Message',
      );
      expect(input.control?.value, isEmpty);
    },
  );

  cockpitTestWidgets(
    'keeps concurrent commands safe with resident async work',
    app: () => const _ResidentAsyncTestApp(),
    body: (cockpit) async {
      final results = await Future.wait<CockpitCommandExecution>(
        <Future<CockpitCommandExecution>>[
          cockpit.tap('First'),
          cockpit.tap('Second'),
        ],
      );
      expect(results, hasLength(2));
      expect(results.every((result) => result.result.success), isTrue);
    },
  );
}

Future<CockpitCommandExecution> _successfulHostCommand(
  CockpitCommand command,
) async {
  expect(command.timeoutMs, cockpitIntegrationTestNativeTimeout.inMilliseconds);
  return CockpitCommandExecution(
    result: CockpitCommandResult(
      success: true,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: 0,
    ),
  );
}

Future<CockpitCommandExecution> _typedHostCommand(
  CockpitCommand command,
) async {
  expect(command.timeoutMs, cockpitIntegrationTestNativeTimeout.inMilliseconds);
  switch (command.commandType) {
    case CockpitCommandType.assertScreenshot:
      expect(command.parameters['baseline'], 'test/baselines/home.png');
      expect(command.parameters['name'], 'home');
    case CockpitCommandType.travel:
      final route = command.parameters['route']! as List<Object?>;
      expect(route, hasLength(2));
    default:
      fail('Unexpected host command ${command.commandType.name}.');
  }
  return CockpitCommandExecution(
    result: CockpitCommandResult(
      success: true,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: 0,
    ),
  );
}

final class _WheelTestApp extends StatelessWidget {
  const _WheelTestApp({required this.onWheel});

  final ValueChanged<Offset> onWheel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                onWheel(event.scrollDelta);
              }
            },
            child: const SizedBox(
              width: 180,
              height: 100,
              child: Center(child: Text('Wheel target')),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ScrollTestApp extends StatelessWidget {
  const _ScrollTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          key: const ValueKey<String>('outer-scroll'),
          itemExtent: 48,
          itemCount: 40,
          itemBuilder: (context, index) => Text('Row $index'),
        ),
      ),
    );
  }
}

final class _ReorderTestApp extends StatefulWidget {
  const _ReorderTestApp({required this.onReordered});

  final ValueChanged<List<String>> onReordered;

  @override
  State<_ReorderTestApp> createState() => _ReorderTestAppState();
}

final class _ReorderTestAppState extends State<_ReorderTestApp> {
  final _labels = <String>['First', 'Second', 'Third'];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _labels.length,
          // Flutter 3.32 exposes the original callback; newer Flutter releases
          // prefer onReorderItem, so keep the floor-compatible API here.
          // ignore: deprecated_member_use
          onReorder: (oldIndex, newIndex) {
            final value = _labels.removeAt(oldIndex);
            final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
            _labels.insert(adjustedIndex, value);
            widget.onReordered(List<String>.of(_labels));
            setState(() {});
          },
          itemBuilder: (context, index) {
            final label = _labels[index];
            return Semantics(
              key: ValueKey<String>('drop-$label'),
              label: 'Drop $label',
              container: true,
              child: SizedBox(
                height: 96,
                child: Row(
                  children: <Widget>[
                    Expanded(child: Center(child: Text(label))),
                    Semantics(
                      label: 'Drag $label',
                      button: true,
                      child: ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Icon(Icons.drag_indicator),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

({
  String switchLanguage,
  String save,
  String saved,
  String message,
  String period15m,
  String period4h,
  String openDialog,
  String dialogTitle,
  String confirm,
  String confirmed,
})
_localeLabels(String locale) {
  return switch (locale) {
    'zh-CN' => (
      switchLanguage: 'العربية',
      save: '保存',
      saved: '已保存',
      message: '消息',
      period15m: '15分钟',
      period4h: '4小时',
      openDialog: '打开确认',
      dialogTitle: '确认订单',
      confirm: '确认',
      confirmed: '已确认',
    ),
    'ar' => (
      switchLanguage: 'English',
      save: 'حفظ',
      saved: 'تم الحفظ',
      message: 'رسالة',
      period15m: '١٥ دقيقة',
      period4h: '٤ ساعات',
      openDialog: 'فتح التأكيد',
      dialogTitle: 'تأكيد الطلب',
      confirm: 'تأكيد',
      confirmed: 'تم التأكيد',
    ),
    _ => (
      switchLanguage: '中文',
      save: 'Save',
      saved: 'Saved',
      message: 'Message',
      period15m: '15m',
      period4h: '4h',
      openDialog: 'Open confirmation',
      dialogTitle: 'Confirm order',
      confirm: 'Confirm',
      confirmed: 'Confirmed',
    ),
  };
}

final class _LocaleTestApp extends StatelessWidget {
  const _LocaleTestApp({
    required this.locale,
    required this.saved,
    required this.confirmed,
    required this.selectedPeriod,
  });

  final ValueNotifier<String> locale;
  final ValueNotifier<bool> saved;
  final ValueNotifier<bool> confirmed;
  final ValueNotifier<int> selectedPeriod;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: locale,
      builder: (context, value, child) {
        final labels = _localeLabels(value);
        final parts = value.split('-');
        final appLocale = parts.length > 1
            ? Locale(parts.first, parts[1])
            : Locale(parts.first);
        return MaterialApp(
          locale: appLocale,
          supportedLocales: const <Locale>[
            Locale('en'),
            Locale('zh', 'CN'),
            Locale('ar'),
          ],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Center(
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () {
                          locale.value = switch (value) {
                            'en' => 'zh-CN',
                            'zh-CN' => 'ar',
                            _ => 'en',
                          };
                          saved.value = false;
                          confirmed.value = false;
                          selectedPeriod.value = 0;
                        },
                        child: Text(labels.switchLanguage),
                      ),
                      GestureDetector(
                        onTap: () => saved.value = true,
                        child: Text(labels.save),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: saved,
                        builder: (context, value, child) =>
                            Text(value ? labels.saved : ''),
                      ),
                      GestureDetector(
                        onTap: () => selectedPeriod.value = 0,
                        child: RichText(text: TextSpan(text: labels.period15m)),
                      ),
                      GestureDetector(
                        onTap: () => selectedPeriod.value = 1,
                        child: RichText(text: TextSpan(text: labels.period4h)),
                      ),
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(labels.dialogTitle),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  confirmed.value = true;
                                  Navigator.of(dialogContext).pop();
                                },
                                child: Text(labels.confirm),
                              ),
                            ],
                          ),
                        ),
                        child: Text(labels.openDialog),
                      ),
                      Text(labels.confirm),
                      ValueListenableBuilder<bool>(
                        valueListenable: confirmed,
                        builder: (context, value, child) =>
                            Text(value ? labels.confirmed : ''),
                      ),
                      SizedBox(
                        width: 320,
                        child: TextField(
                          key: const ValueKey<String>('locale-message'),
                          decoration: InputDecoration(
                            labelText: labels.message,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _NestedLocaleOverrideApp extends StatelessWidget {
  const _NestedLocaleOverrideApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('en'), Locale('zh')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Localizations.override(
          context: context,
          locale: const Locale('zh'),
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: <Widget>[
                  const Text('Nested override'),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Localizations.override(
                        context: dialogContext,
                        locale: const Locale('zh'),
                        child: AlertDialog(
                          content: const Text('Dialog override'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TestApp extends StatefulWidget {
  const _TestApp();

  @override
  State<_TestApp> createState() => _TestAppState();
}

final class _TestAppState extends State<_TestApp> {
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_saved ? 'Saved' : 'Ready'),
              TextButton(
                onPressed: () => setState(() => _saved = true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AnimatedTestApp extends StatefulWidget {
  const _AnimatedTestApp();

  @override
  State<_AnimatedTestApp> createState() => _AnimatedTestAppState();
}

final class _ScaleTestApp extends StatelessWidget {
  const _ScaleTestApp({required this.onScale});

  final ValueChanged<double> onScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleUpdate: (details) => onScale(details.scale),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

final class _DoubleTapTestApp extends StatelessWidget {
  const _DoubleTapTestApp({required this.onDoubleTap});

  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onDoubleTap,
          child: const Center(child: Text('Double')),
        ),
      ),
    );
  }
}

final class _HoverTestApp extends StatelessWidget {
  const _HoverTestApp({required this.onHover});

  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MouseRegion(
            onEnter: (_) => onHover(),
            onHover: (_) => onHover(),
            child: const Text('Hover target'),
          ),
        ),
      ),
    );
  }
}

final class _PointerProbeApp extends StatelessWidget {
  const _PointerProbeApp({required this.onDown});

  final ValueChanged<PointerDownEvent> onDown;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: onDown,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

final class _TextInputTestApp extends StatelessWidget {
  const _TextInputTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: TextField(decoration: InputDecoration(labelText: 'Message')),
        ),
      ),
    );
  }
}

final class _ResidentAsyncTestApp extends StatefulWidget {
  const _ResidentAsyncTestApp();

  @override
  State<_ResidentAsyncTestApp> createState() => _ResidentAsyncTestAppState();
}

final class _ResidentAsyncTestAppState extends State<_ResidentAsyncTestApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => Column(
            children: <Widget>[
              TextButton(onPressed: () {}, child: const Text('First')),
              TextButton(onPressed: () {}, child: const Text('Second')),
              Opacity(opacity: 0.5 + (_animation.value / 2), child: child),
            ],
          ),
          child: const Text('resident'),
        ),
      ),
    );
  }
}

final class _HotkeyTestApp extends StatelessWidget {
  const _HotkeyTestApp({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyS &&
                HardwareKeyboard.instance.isControlPressed) {
              onSave();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: const Text('Shortcut target'),
        ),
      ),
    );
  }
}

final class _AnimatedTestAppState extends State<_AnimatedTestApp> {
  var _held = false;
  var _alignedRight = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            GestureDetector(
              onLongPress: () => setState(() => _held = true),
              child: SizedBox(
                height: 80,
                width: double.infinity,
                child: Center(child: Text(_held ? 'Held' : 'Hold')),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _alignedRight = !_alignedRight),
              child: const Text('Animate'),
            ),
            Expanded(
              child: AnimatedAlign(
                alignment: _alignedRight
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 250),
                child: const Text('Moving'),
              ),
            ),
            AnimatedOpacity(
              opacity: _alignedRight ? 0.2 : 1,
              duration: const Duration(milliseconds: 250),
              child: const Text('Fading'),
            ),
          ],
        ),
      ),
    );
  }
}
