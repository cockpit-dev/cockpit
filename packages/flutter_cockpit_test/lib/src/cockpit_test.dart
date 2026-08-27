import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'cockpit_native_tester.dart';
import 'cockpit_test_options.dart';

/// Registers an integration test that runs the real Cockpit in-app executor.
///
/// The application is mounted inside [FlutterCockpitApp], so production code
/// does not need to import Cockpit. The official integration_test binding is
/// initialized automatically and remains the owner of device lifecycle and
/// test result transport.
void cockpitTestWidgets(
  String description, {
  required CockpitTestAppBuilder app,
  required Future<void> Function(CockpitTester tester) body,
  CockpitTestOptions options = const CockpitTestOptions(),
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(description, (flutterTester) async {
    final rootKey = GlobalKey<FlutterCockpitRootState>();
    final application = app();
    FlutterCockpit.ensureInitialized(options.config);
    final ownsRuntime =
        application is! FlutterCockpitApp && application is! FlutterCockpitRoot;
    await flutterTester.pumpWidget(
      ownsRuntime
          ? FlutterCockpitApp(
              config: options.config,
              ownsRuntime: true,
              rootKey: rootKey,
              child: application,
            )
          : application,
    );
    await flutterTester.pump();
    if (options.initialPump > Duration.zero) {
      await flutterTester.runAsync(
        () => Future<void>.delayed(options.initialPump),
      );
      await flutterTester.pump();
    }

    final root = rootKey.currentState ?? _findRoot(flutterTester);
    if (root == null) {
      fail(
        'Cockpit test app did not mount FlutterCockpitRoot. '
        'Return a FlutterCockpitApp or a Flutter widget that the helper can '
        'wrap.',
      );
    }

    final cockpit = CockpitTester._(
      flutter: flutterTester,
      root: root,
      options: options,
    );
    addTearDown(() async {
      _publishIntegrationReport(cockpit.report);
      await cockpit.native.close();
      await flutterTester.pumpWidget(const SizedBox.shrink());
      await flutterTester.pump();
      if (!ownsRuntime) {
        FlutterCockpit.dispose();
      }
    });

    await body(cockpit);
  });
}

FlutterCockpitRootState? _findRoot(WidgetTester tester) {
  final finder = find.byType(FlutterCockpitRoot);
  if (finder.evaluate().length != 1) return null;
  return tester.state<FlutterCockpitRootState>(finder);
}

void _publishIntegrationReport(Map<String, Object?> report) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final existing = binding.reportData ?? <String, dynamic>{};
  binding.reportData = <String, dynamic>{...existing, 'cockpit': report};
}

/// A compact, selector-first facade over Cockpit's in-app command executor.
final class CockpitTester {
  CockpitTester._({
    required this.flutter,
    required this.root,
    required this.options,
  }) : native = CockpitNativeTester(
         root,
         defaultTimeout: options.nativeTimeout,
       ) {
    _validateTimeout(options.commandTimeout, name: 'commandTimeout');
    _validateTimeout(options.nativeTimeout, name: 'nativeTimeout');
  }

  /// The underlying official Flutter tester for advanced widget assertions.
  final WidgetTester flutter;

  /// The mounted Cockpit root used by this test.
  final FlutterCockpitRootState root;

  /// The options used to bootstrap this test.
  final CockpitTestOptions options;

  /// Supported app-native capture, recording, and viewport controls.
  final CockpitNativeTester native;

  /// Explicit host/system-plane action facade.
  late final CockpitHostTester host = CockpitHostTester._(this);

  final List<CockpitCommandResult> _results = <CockpitCommandResult>[];
  var _sequence = 0;
  late final InAppCockpitCommandExecutor _executor = root.createCommandExecutor(
    platform: options.platform,
    transportType: 'inAppTest',
    // Flutter's test binding needs an explicit frame pump for route pushes,
    // animations, lazy lists, and async state changes. Supplying these hooks
    // keeps the executor's commit/reveal logic identical to the live bridge
    // while making Dart integration tests advance the test clock correctly.
    postActionSettler: flutter.pump,
    waitTickHandler: flutter.pump,
  );

  /// Describes the live in-app commands and locator strategies available to
  /// this test. The result is generated from the same executor used by the
  /// Cockpit bridge, so platform-specific capabilities stay truthful.
  Future<CockpitCapabilities> describeCapabilities() {
    return _executor.describeCapabilities();
  }

  /// A compact report suitable for integration_test's JSON result payload.
  Map<String, Object?> get report {
    final failures = _results.where((result) => !result.success).toList();
    return <String, Object?>{
      'commands': _results.length,
      if (failures.isNotEmpty) 'failures': failures.length,
      if (_results.isNotEmpty)
        'steps': _results
            .map(
              (result) => <String, Object?>{
                'id': result.commandId,
                'type': result.commandType.name,
                'ms': result.durationMs,
                if (!result.success && result.error != null)
                  'error': result.error!.code,
                if (result.artifacts.isNotEmpty)
                  'artifacts': result.artifacts
                      .map((artifact) => artifact.relativePath)
                      .toList(growable: false),
              },
            )
            .toList(growable: false),
    };
  }

  /// Executes a fully specified Cockpit command.
  Future<CockpitCommandExecution> execute(
    CockpitCommand command, {
    bool? check,
  }) async {
    final effectiveCommand = _withTimeout(command);
    final execution = await _executor.executeWithArtifacts(effectiveCommand);
    _results.add(execution.result);
    FlutterCockpit.binding.sessionController.recordCommandResult(
      effectiveCommand,
      execution.result,
    );
    if (options.pumpAfterCommand) {
      await flutter.pump();
    }
    if (check ?? options.failFast) {
      _checkSuccess(effectiveCommand, execution.result);
    }
    return execution;
  }

  Future<CockpitCommandExecution> tap(
    Object target, {
    Duration? timeout,
    CockpitCapturePolicy capture = CockpitCapturePolicy.none,
  }) => _run(
    CockpitCommandType.tap,
    target: target,
    timeout: timeout,
    capturePolicy: capture,
  );

  Future<CockpitCommandExecution> type(
    String value, {
    required Object into,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.enterText,
    target: into,
    timeout: timeout,
    parameters: <String, Object?>{'text': value},
  );

  Future<CockpitCommandExecution> clear(Object target, {Duration? timeout}) =>
      _run(CockpitCommandType.eraseText, target: target, timeout: timeout);

  /// Performs a real long-press on a resolved Flutter target.
  Future<CockpitCommandExecution> longPress(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.longPress, target: target, timeout: timeout);

  /// Performs a real double-tap on a resolved Flutter target.
  Future<CockpitCommandExecution> doubleTap(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.doubleTap, target: target, timeout: timeout);

  /// Moves a slider or other incrementable control forward by one step.
  Future<CockpitCommandExecution> increase(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.increase, target: target, timeout: timeout);

  /// Moves a slider or other decrementable control backward by one step.
  Future<CockpitCommandExecution> decrease(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.decrease, target: target, timeout: timeout);

  /// Reveals a target through every mounted scrollable ancestor without
  /// invoking a mutation action.
  Future<CockpitCommandExecution> showOnScreen(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.showOnScreen, target: target, timeout: timeout);

  Future<CockpitCommandExecution> press(
    CockpitTextInputAction action, {
    Object? target,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.sendTextInputAction,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{'inputAction': action.name},
  );

  Future<CockpitCommandExecution> scroll(
    Object target, {
    String? direction,
    String? align,
    double? offset,
    String? scrollable,
    int? maxScrolls,
    Duration? timeout,
  }) {
    final parameters = <String, Object?>{};
    if (direction != null) parameters['direction'] = direction;
    if (align != null) parameters['revealAlignment'] = align;
    if (offset != null) parameters['revealOffsetPx'] = offset;
    if (scrollable != null) parameters['scrollLocator'] = scrollable;
    if (maxScrolls != null) parameters['maxScrolls'] = maxScrolls;
    return _run(
      CockpitCommandType.scrollUntilVisible,
      target: target,
      timeout: timeout,
      parameters: parameters,
    );
  }

  Future<CockpitCommandExecution> waitForUi({
    bool network = false,
    Duration? timeout,
  }) => _run(
    network
        ? CockpitCommandType.waitForNetworkIdle
        : CockpitCommandType.waitForUiIdle,
    timeout: timeout,
  );

  /// Waits until a target is present, or absent when [absent] is true.
  Future<CockpitCommandExecution> waitFor(
    Object target, {
    bool absent = false,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.waitFor,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{if (absent) 'absent': true},
  );

  /// Waits for a named route and its route-ready targets to be mounted.
  Future<CockpitCommandExecution> waitForRoute(
    String route, {
    Duration? timeout,
  }) => _run(
    CockpitCommandType.waitFor,
    target: CockpitLocator(route: route),
    timeout: timeout,
  );

  Future<CockpitCommandExecution> back({Duration? timeout}) =>
      _run(CockpitCommandType.back, timeout: timeout);

  Future<CockpitCommandExecution> dismiss({Duration? timeout}) =>
      _run(CockpitCommandType.dismiss, timeout: timeout);

  Future<CockpitCommandExecution> dismissKeyboard({Duration? timeout}) =>
      _run(CockpitCommandType.dismissKeyboard, timeout: timeout);

  Future<CockpitCommandExecution> expectVisible(
    Object target, {
    Duration? timeout,
  }) =>
      _run(CockpitCommandType.assertVisible, target: target, timeout: timeout);

  Future<CockpitCommandExecution> expectText(
    Object target,
    String value, {
    CockpitTextMatchMode match = CockpitTextMatchMode.exact,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.assertText,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{
      'text': value,
      if (match != CockpitTextMatchMode.exact) 'matchMode': match.name,
    },
  );

  Future<CockpitCommandExecution> screenshot({
    String name = 'integration_test',
    CockpitCaptureProfile profile = CockpitCaptureProfile.acceptance,
    bool includeSnapshot = true,
    bool allowFallback = true,
    Duration? timeout,
  }) {
    final request = CockpitScreenshotRequest(
      reason: CockpitScreenshotReason.acceptance,
      name: name,
      includeSnapshot: includeSnapshot,
      attachToStep: true,
      profile: profile,
      allowFallback: allowFallback,
    );
    return execute(
      CockpitCommand(
        commandId: _nextId('screenshot'),
        commandType: CockpitCommandType.captureScreenshot,
        timeoutMs: _timeoutMs(timeout),
        screenshotRequest: request,
      ),
    );
  }

  CockpitSnapshot snapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions(),
  }) => root.snapshot(options: options);

  Future<CockpitCommandExecution> _run(
    CockpitCommandType type, {
    Object? target,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration? timeout,
    CockpitCapturePolicy capturePolicy = CockpitCapturePolicy.none,
  }) => execute(
    CockpitCommand(
      commandId: _nextId(type.name),
      commandType: type,
      locator: _locator(target),
      parameters: parameters,
      timeoutMs: _timeoutMs(timeout),
      capturePolicy: capturePolicy,
    ),
  );

  Future<CockpitCommandExecution> _executeHost(CockpitCommand command) async {
    final handler = options.hostCommand;
    if (handler == null) {
      throw StateError(
        'No host command handler is configured. Pass hostCommand in '
        'CockpitTestOptions to enable native/system-plane actions.',
      );
    }
    final effectiveCommand = command.timeoutMs == null
        ? command.copyWith(timeoutMs: _nativeTimeoutMs(null))
        : _withTimeout(command);
    final timeout = Duration(milliseconds: effectiveCommand.timeoutMs!);
    final stopwatch = Stopwatch()..start();
    final execution = await handler(effectiveCommand).timeout(
      timeout,
      onTimeout: () => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: effectiveCommand.commandId,
          commandType: effectiveCommand.commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          error: CockpitCommandError.timeout(
            message:
                'Host command ${effectiveCommand.commandId} exceeded its '
                '${timeout.inMilliseconds}ms timeout.',
            details: <String, Object?>{
              'commandId': effectiveCommand.commandId,
              'commandType': effectiveCommand.commandType.name,
              'timeoutMs': timeout.inMilliseconds,
            },
          ),
        ),
      ),
    );
    stopwatch.stop();
    _results.add(execution.result);
    FlutterCockpit.binding.sessionController.recordCommandResult(
      effectiveCommand,
      execution.result,
    );
    if (options.pumpAfterCommand) {
      await flutter.pump();
    }
    if (options.failFast) {
      _checkSuccess(effectiveCommand, execution.result);
    }
    return execution;
  }

  CockpitCommand _withTimeout(CockpitCommand command) {
    final timeoutMs = command.timeoutMs;
    if (timeoutMs == null) {
      return command.copyWith(timeoutMs: _timeoutMs(null));
    }
    _validateTimeout(
      Duration(milliseconds: timeoutMs),
      name: 'command.timeoutMs',
    );
    return command;
  }

  CockpitLocator? _locator(Object? target) {
    if (target == null) return null;
    if (target is CockpitLocator) return target;
    if (target is String) return CockpitSelector.parse(target);
    throw ArgumentError.value(
      target,
      'target',
      'A target must be a selector String or CockpitLocator.',
    );
  }

  String _nextId(String type) => 'dart-${++_sequence}-$type';

  int _timeoutMs(Duration? timeout) {
    final effective = timeout ?? options.commandTimeout;
    _validateTimeout(effective, name: 'timeout');
    return effective.inMilliseconds;
  }

  int _nativeTimeoutMs(Duration? timeout) {
    final effective = timeout ?? options.nativeTimeout;
    _validateTimeout(effective, name: 'timeout');
    return effective.inMilliseconds;
  }

  static void _validateTimeout(Duration timeout, {required String name}) {
    if (timeout <= Duration.zero ||
        timeout > cockpitIntegrationTestMaximumTimeout) {
      throw ArgumentError.value(
        timeout,
        name,
        'Timeout must be between 1ms and '
        '${cockpitIntegrationTestMaximumTimeout.inMilliseconds}ms.',
      );
    }
  }

  void _checkSuccess(CockpitCommand command, CockpitCommandResult result) {
    if (result.success) return;
    final error = result.error;
    fail(
      'Cockpit command ${command.commandType.name} failed'
      '${error == null ? '' : ': ${error.message}'}',
    );
  }
}

/// Explicit bridge for host/device automation that cannot run inside the
/// Flutter process, such as OS dialogs, app links, and native UI actions.
final class CockpitHostTester {
  CockpitHostTester._(this._tester);

  final CockpitTester _tester;

  /// Executes a host command supplied through [CockpitTestOptions.hostCommand].
  Future<CockpitCommandExecution> execute(CockpitCommand command) =>
      _tester._executeHost(command);

  /// Runs one named system action through the configured host bridge.
  Future<CockpitCommandExecution> action(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration? timeout,
  }) => _tester._executeHost(
    CockpitCommand(
      commandId: _tester._nextId('system'),
      commandType: CockpitCommandType.system,
      parameters: <String, Object?>{'action': name, ...parameters},
      timeoutMs: _tester._nativeTimeoutMs(timeout),
    ),
  );
}
