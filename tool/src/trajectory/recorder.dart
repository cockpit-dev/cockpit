/// Recording engine: executes a scenario against a live Cockpit session and
/// produces a canonical trajectory plus screenshot assets.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'cockpit_cli.dart';
import 'scenario.dart';
import 'system_prompt.dart';
import 'trajectory.dart';

class RecorderException implements Exception {
  RecorderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A recorded scenario: the trajectory plus the asset files it produced.
class RecordedScenario {
  const RecordedScenario({
    required this.scenario,
    required this.trajectory,
    required this.assetPaths,
  });

  final Scenario scenario;
  final Trajectory trajectory;

  /// Absolute paths of screenshot assets referenced by the trajectory.
  final List<String> assetPaths;
}

class TrajectoryRecorder {
  TrajectoryRecorder({
    required this.runner,
    required this.repoRoot,
    required this.cockpitBin,
    required this.observationFormat,
    required this.observationView,
    this.cockpitVersion,
    this.startTimeout = const Duration(minutes: 15),
    DateTime Function()? now,
    String Function()? tokenGenerator,
  }) : _now = now ?? DateTime.now,
       _newToken = tokenGenerator ?? defaultTrajectoryToken;

  final CockpitRunner runner;

  /// Repository root; scenario `app.directory` values resolve against it.
  final String repoRoot;
  final String cockpitBin;

  /// Observation capture flags appended to every recorded command, matching
  /// the defaults a real agent loop uses (`lon` / `brief`).
  final String observationFormat;
  final String observationView;
  final String? cockpitVersion;
  final Duration startTimeout;

  final DateTime Function() _now;
  final String Function() _newToken;

  /// Records [scenario] into [datasetDirectory] (created if missing).
  ///
  /// Pass [sessionHandle] to reuse a running session instead of launching
  /// the app. A session started by the recorder is stopped afterwards
  /// unless [keepSession] is true.
  Future<RecordedScenario> record(
    Scenario scenario, {
    required String datasetDirectory,
    String? sessionHandle,
    bool keepSession = false,
  }) async {
    final appDirectory = _resolveAppDirectory(scenario);
    final trajectoryId = '${scenario.id}-${_newToken()}';
    final assetsRoot = Directory('$datasetDirectory/assets/$trajectoryId')
      ..createSync(recursive: true);

    final steps = <TrajectoryStep>[];
    final String handle;
    var startedByRecorder = false;

    if (sessionHandle != null) {
      handle = sessionHandle;
    } else {
      startedByRecorder = true;
      final start = await _startSession(appDirectory, scenario.app.platform);
      handle = start.handle;
      if (scenario.includeSetup) {
        steps.add(
          TrajectoryStep(
            index: 0,
            command: 'cockpit dev start --platform ${scenario.app.platform}',
            exitCode: start.result.exitCode,
            observation: start.result.stdout,
            stderr: start.result.stderr,
            durationMs: start.result.durationMs,
            timedOut: start.result.timedOut,
            expectationMet: true,
          ),
        );
      }
    }

    var aborted = false;
    var sawDeliberateFailure = false;
    for (var i = 0; i < scenario.steps.length && !aborted; i++) {
      final step = scenario.steps[i];
      if (!step.expect.ok) sawDeliberateFailure = true;
      final index = steps.length;
      final name = 'step-${index.toString().padLeft(2, '0')}';
      final screenshotPath = '${assetsRoot.path}/$name.png';
      final argv =
          step.buildArgv(sessionHandle: handle, screenshotPath: screenshotPath)
            ..addAll(<String>[
              '--format',
              observationFormat,
              '--view',
              observationView,
            ]);
      final result = await runner.run(
        argv,
        workingDirectory: repoRoot,
        timeout: Duration(milliseconds: step.timeoutMs),
      );
      final met = step.evaluate(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        timedOut: result.timedOut,
      );
      final datasetRelativeImage = 'assets/$trajectoryId/$name.png';
      steps.add(
        TrajectoryStep(
          index: index,
          command: step.displayCommand(
            sessionHandle: handle,
            screenshotName: '$name.png',
          ),
          exitCode: result.exitCode,
          observation: result.stdout,
          stderr: result.stderr,
          durationMs: result.durationMs,
          timedOut: result.timedOut,
          expect: TrajectoryExpectation(
            ok: step.expect.ok,
            code: step.expect.code,
          ),
          expectationMet: met,
          image: step.isScreenshot
              ? _imageAsset(screenshotPath, datasetRelativeImage)
              : null,
        ),
      );
      if (!met && step.onFailure == ScenarioFailurePolicy.abort) {
        aborted = true;
      }
    }

    var stopped = false;
    if (startedByRecorder && !keepSession) {
      stopped = await _stopSession(handle);
    }

    final trajectory = Trajectory(
      id: trajectoryId,
      app: TrajectoryApp(
        name: scenario.app.name,
        directory: scenario.app.directory,
        platform: scenario.app.platform,
      ),
      session: TrajectorySession(
        handle: handle,
        startedByRecorder: startedByRecorder,
        setupRecorded: scenario.includeSetup && startedByRecorder,
        stopped: stopped,
      ),
      goal: scenario.goal,
      paraphrases: scenario.paraphrases,
      systemPrompt: TrajectorySystemPrompt(
        id: cockpitDevAgentSystemPromptId,
        sha256: sha256
            .convert(utf8.encode(cockpitDevAgentSystemPrompt))
            .toString(),
        text: cockpitDevAgentSystemPrompt,
      ),
      steps: steps,
      completion: scenario.completion,
      outcome: aborted
          ? TrajectoryOutcome.failure
          : sawDeliberateFailure
          ? TrajectoryOutcome.recovered
          : TrajectoryOutcome.success,
      cockpit: <String, Object?>{
        if (cockpitVersion != null) 'version': cockpitVersion,
        'format': observationFormat,
        'view': observationView,
        'bin': cockpitBin,
      },
      recordedAt: _now().toUtc().toIso8601String(),
    );

    return RecordedScenario(
      scenario: scenario,
      trajectory: trajectory,
      assetPaths: steps
          .map((step) => step.image)
          .whereType<TrajectoryImage>()
          .map((image) => '$datasetDirectory/${image.path}')
          .toList(),
    );
  }

  Future<_SessionStart> _startSession(
    String appDirectory,
    String platform,
  ) async {
    final result = await runner.run(
      <String>[
        'dev',
        'start',
        '--platform',
        platform,
        '--format',
        'json',
        '--view',
        'full',
      ],
      workingDirectory: appDirectory,
      timeout: startTimeout,
    );
    if (result.timedOut) {
      throw RecorderException(
        'cockpit dev start timed out after ${startTimeout.inSeconds}s.',
      );
    }
    Object? envelope;
    try {
      envelope = jsonDecode(result.stdout);
    } on FormatException {
      envelope = null;
    }
    String? handle;
    if (envelope is Map<String, Object?>) {
      final ok = envelope['ok'];
      final session = envelope['session'];
      if (ok == true && (session is String || session is int)) {
        handle = session.toString();
      }
    }
    if (handle == null) {
      throw RecorderException(
        'cockpit dev start did not return a session handle.\n'
        'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      );
    }
    return _SessionStart(handle, result);
  }

  String _resolveAppDirectory(Scenario scenario) {
    final directory = Directory(
      scenario.app.directory.startsWith('/')
          ? scenario.app.directory
          : '$repoRoot/${scenario.app.directory}',
    );
    if (!directory.existsSync()) {
      throw RecorderException(
        'App directory does not exist: ${directory.path}',
      );
    }
    return directory.path;
  }

  Future<bool> _stopSession(String handle) async {
    final result = await runner.run(
      <String>['dev', 'stop', '--session', handle],
      workingDirectory: repoRoot,
      timeout: const Duration(seconds: 60),
    );
    return result.exitCode == 0;
  }

  TrajectoryImage? _imageAsset(String screenshotPath, String datasetRelative) {
    final file = File(screenshotPath);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    return TrajectoryImage(
      path: datasetRelative,
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
    );
  }
}

/// Default trajectory id suffix: 6 characters of base-36 entropy.
String defaultTrajectoryToken() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(
    6,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

class _SessionStart {
  const _SessionStart(this.handle, this.result);

  final String handle;
  final CockpitCommandResult result;
}
