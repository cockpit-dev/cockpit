import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
