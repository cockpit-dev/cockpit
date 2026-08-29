import 'package:flutter/material.dart';
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
      expect(cockpit.report['watches'], hasLength(1));
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
              onPressed: () => setState(() => _alignedRight = true),
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
          ],
        ),
      ),
    );
  }
}
