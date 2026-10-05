import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/src/trajectory/cockpit_cli.dart';
import '../../../tool/src/trajectory/recorder.dart';
import '../../../tool/src/trajectory/scenario.dart';
import '../../../tool/src/trajectory/trajectory.dart';
import '../../../tool/src/trajectory/trajectory_writer.dart';

/// Queue-driven stand-in for the cockpit process: returns canned results in
/// order and writes screenshot files when the argv asks for --save.
class _FakeRunner implements CockpitRunner {
  final List<CockpitCommandResult> queued = <CockpitCommandResult>[];
  final List<List<String>> calls = <List<String>>[];
  final List<String> workingDirectories = <String>[];

  @override
  Future<CockpitCommandResult> run(
    List<String> argv, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    calls.add(List.of(argv));
    workingDirectories.add(workingDirectory);
    final saveIndex = argv.indexOf('--save');
    if (saveIndex >= 0) {
      File(argv[saveIndex + 1]).writeAsBytesSync(_pngBytes);
    }
    if (argv.join(' ').startsWith('dev stop')) {
      return CockpitCommandResult(
        exitCode: 0,
        stdout: 'ok: true',
        stderr: '',
        durationMs: 5,
        timedOut: false,
      );
    }
    if (queued.isEmpty) {
      throw StateError('No queued result for ${argv.join(' ')}');
    }
    return queued.removeAt(0);
  }

  void enqueueOk({String stdout = 'ok: true'}) {
    queued.add(
      CockpitCommandResult(
        exitCode: 0,
        stdout: stdout,
        stderr: '',
        durationMs: 12,
        timedOut: false,
      ),
    );
  }

  void enqueueFailure({required int exitCode, required String stdout}) {
    queued.add(
      CockpitCommandResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: '',
        durationMs: 12,
        timedOut: false,
      ),
    );
  }

  void enqueueStart(String handle) {
    enqueueOk(stdout: '{"ok":true,"action":"start","session":"$handle"}');
  }

  void enqueueTimeout() {
    queued.add(
      const CockpitCommandResult(
        exitCode: -1,
        stdout: '',
        stderr: '',
        durationMs: 30000,
        timedOut: true,
      ),
    );
  }

  static final List<int> _pngBytes = List<int>.generate(64, (i) => i);
}

Scenario _scenario({
  required List<ScenarioStep> steps,
  bool includeSetup = false,
  List<String> paraphrases = const <String>['帮我把主题切成暗色'],
}) {
  return Scenario(
    id: 'test_flow',
    app: const ScenarioApp(
      name: 'cockpit_demo',
      directory: 'examples/cockpit_demo/cockpit',
      platform: 'macos',
    ),
    goal: '把深色模式打开',
    paraphrases: paraphrases,
    completion: '已完成并验证。',
    includeSetup: includeSetup,
    steps: steps,
  );
}

Directory _tempDataset() {
  return Directory.systemTemp.createTempSync('cockpit-trajectory-test-');
}

void main() {
  late _FakeRunner runner;
  late Directory dataset;

  setUp(() {
    runner = _FakeRunner();
    dataset = _tempDataset();
  });

  tearDown(() {
    dataset.deleteSync(recursive: true);
  });

  TrajectoryRecorder buildRecorder() {
    return TrajectoryRecorder(
      runner: runner,
      repoRoot: Directory.current.path,
      cockpitBin: 'cockpit',
      observationFormat: 'lon',
      observationView: 'brief',
      cockpitVersion: '4.11.1',
      now: () => DateTime.utc(2026, 10, 5),
      tokenGenerator: () => 'abc123',
    );
  }

  test('records a happy path with screenshot asset and stop', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueOk()
      ..enqueueOk();
    final recorded = await buildRecorder().record(
      _scenario(
        steps: const <ScenarioStep>[
          ScenarioStep(action: 'tap', selector: 'Settings'),
          ScenarioStep(action: 'screenshot'),
        ],
      ),
      datasetDirectory: dataset.path,
    );

    final trajectory = recorded.trajectory;
    expect(trajectory.id, 'test_flow-abc123');
    expect(trajectory.session.handle, 'h1');
    expect(trajectory.session.startedByRecorder, isTrue);
    expect(trajectory.session.stopped, isTrue);
    expect(trajectory.outcome, TrajectoryOutcome.success);
    expect(trajectory.steps, hasLength(2));

    final tap = trajectory.steps.first;
    expect(tap.command, 'cockpit dev tap Settings --session h1');
    expect(tap.observation, 'ok: true');
    expect(tap.expectationMet, isTrue);

    final screenshot = trajectory.steps.last;
    expect(screenshot.image, isNotNull);
    expect(screenshot.image!.path, 'assets/test_flow-abc123/step-01.png');
    expect(File(recorded.assetPaths.single).existsSync(), isTrue);

    // Start runs in the app directory; commands run from the repo root.
    expect(
      runner.workingDirectories.first.endsWith('examples/cockpit_demo/cockpit'),
      isTrue,
    );
    expect(runner.workingDirectories.last, Directory.current.path);
    // The recorded command carries the capture flags for observation
    // fidelity: --format lon --view brief.
    expect(runner.calls[1].sublist(3), <String>[
      '--session',
      'h1',
      '--format',
      'lon',
      '--view',
      'brief',
    ]);
    // Session teardown runs dev stop.
    expect(runner.calls.last, <String>['dev', 'stop', '--session', 'h1']);
  });

  test('records the setup step when includeSetup is set', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueOk();
    final recorded = await buildRecorder().record(
      _scenario(
        steps: const <ScenarioStep>[ScenarioStep(action: 'status')],
        includeSetup: true,
      ),
      datasetDirectory: dataset.path,
    );
    final trajectory = recorded.trajectory;
    expect(trajectory.session.setupRecorded, isTrue);
    expect(trajectory.steps.first.command, contains('dev start'));
    expect(trajectory.steps.last.command, contains('dev status'));
    expect(trajectory.steps.last.index, 1);
  });

  test('classifies deliberate failures with recovery as recovered', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueFailure(
        exitCode: 65,
        stdout: 'error: {code: ambiguousTarget, candidateCount: 2}',
      )
      ..enqueueOk()
      ..enqueueOk();
    final recorded = await buildRecorder().record(
      _scenario(
        steps: const <ScenarioStep>[
          ScenarioStep(
            action: 'tap',
            selector: 'Today',
            expect: ScenarioExpectation(ok: false, code: 'ambiguousTarget'),
            onFailure: ScenarioFailurePolicy.continueRun,
          ),
          ScenarioStep(action: 'inspect', selector: 'Today'),
          ScenarioStep(action: 'tap', selector: 'Tomorrow'),
        ],
      ),
      datasetDirectory: dataset.path,
    );
    expect(recorded.trajectory.outcome, TrajectoryOutcome.recovered);
    expect(recorded.trajectory.steps.first.expectationMet, isTrue);
    expect(recorded.trajectory.steps.first.expect!.code, 'ambiguousTarget');
  });

  test('aborts remaining steps on an unexpected failure', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueFailure(exitCode: 66, stdout: 'error: {code: targetNotFound}');
    final recorded = await buildRecorder().record(
      _scenario(
        steps: const <ScenarioStep>[
          ScenarioStep(action: 'tap', selector: 'Missing'),
          ScenarioStep(action: 'tap', selector: 'Settings'),
        ],
      ),
      datasetDirectory: dataset.path,
    );
    expect(recorded.trajectory.outcome, TrajectoryOutcome.failure);
    expect(recorded.trajectory.steps, hasLength(1));
    expect(runner.calls, hasLength(3)); // start, tap, stop
  });

  test(
    'a start envelope without a session handle fails the recording',
    () async {
      runner.enqueueOk(stdout: '{"ok":true,"action":"start"}');
      await expectLater(
        buildRecorder().record(
          _scenario(
            steps: const <ScenarioStep>[ScenarioStep(action: 'status')],
          ),
          datasetDirectory: dataset.path,
        ),
        throwsA(isA<RecorderException>()),
      );
    },
  );

  test('timeouts mark the step unmet', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueTimeout();
    final recorded = await buildRecorder().record(
      _scenario(steps: const <ScenarioStep>[ScenarioStep(action: 'wait')]),
      datasetDirectory: dataset.path,
    );
    expect(recorded.trajectory.steps.single.timedOut, isTrue);
    expect(recorded.trajectory.steps.single.expectationMet, isFalse);
    expect(recorded.trajectory.outcome, TrajectoryOutcome.failure);
  });

  test('writer emits the base record plus paraphrase variants', () async {
    runner
      ..enqueueStart('h1')
      ..enqueueOk();
    final recorded = await buildRecorder().record(
      _scenario(steps: const <ScenarioStep>[ScenarioStep(action: 'status')]),
      datasetDirectory: dataset.path,
    );
    const writer = TrajectoryWriter();
    final count = await writer.write(
      record: RecordedRecord(
        scenarioId: recorded.scenario.id,
        trajectory: recorded.trajectory,
      ),
      datasetDirectory: dataset.path,
    );
    expect(count, 2);

    final lines = File(
      '${dataset.path}/test_flow.jsonl',
    ).readAsLinesSync().where((line) => line.isNotEmpty).toList();
    expect(lines, hasLength(2));
    final base = Trajectory.fromJson(_decode(lines.first));
    final variant = Trajectory.fromJson(_decode(lines.last));
    expect(base.id, 'test_flow-abc123');
    expect(base.derivedFrom, isNull);
    expect(variant.id, 'test_flow-abc123-p2');
    expect(variant.derivedFrom, 'test_flow-abc123');
    expect(variant.goal, '帮我把主题切成暗色');
    expect(variant.steps, hasLength(base.steps.length));
  });

  test(
    'validator accepts the written dataset and rejects corruption',
    () async {
      runner
        ..enqueueStart('h1')
        ..enqueueOk();
      final recorded = await buildRecorder().record(
        _scenario(steps: const <ScenarioStep>[ScenarioStep(action: 'status')]),
        datasetDirectory: dataset.path,
      );
      const writer = TrajectoryWriter();
      await writer.write(
        record: RecordedRecord(
          scenarioId: recorded.scenario.id,
          trajectory: recorded.trajectory,
        ),
        datasetDirectory: dataset.path,
      );
      final valid = await const TrajectoryDatasetValidator().validate(
        dataset.path,
      );
      expect(valid, isEmpty);

      File('${dataset.path}/broken.jsonl').writeAsStringSync('not json\n');
      final errors = await const TrajectoryDatasetValidator().validate(
        dataset.path,
      );
      expect(errors.single, contains('broken.jsonl'));
    },
  );
}

Map<String, Object?> _decode(String line) {
  final decoded = jsonDecode(line);
  if (decoded is! Map<String, Object?>) {
    fail('Decoded JSONL line is not an object.');
  }
  return decoded;
}
