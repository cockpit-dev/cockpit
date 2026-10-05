/// Canonical trajectory data model for `cockpit.training/trajectory-v1`.
///
/// See `docs/agent-training/trajectory-format.md` for the full contract.
/// The model is deliberately model-agnostic: steps store raw commands and
/// verbatim observations; chat-template rendering happens at training time.
library;

import 'dart:convert';

const String trajectorySchema = 'cockpit.training/trajectory-v1';

/// Overall result of a recorded trajectory.
enum TrajectoryOutcome { success, recovered, failure }

String trajectoryOutcomeToJson(TrajectoryOutcome outcome) {
  return outcome.name;
}

TrajectoryOutcome trajectoryOutcomeFromJson(String value) {
  return TrajectoryOutcome.values.firstWhere(
    (outcome) => outcome.name == value,
    orElse: () => throw FormatException('Unknown trajectory outcome: $value'),
  );
}

/// The application a trajectory was recorded against.
class TrajectoryApp {
  const TrajectoryApp({
    required this.name,
    required this.directory,
    required this.platform,
  });

  factory TrajectoryApp.fromJson(Map<String, Object?> json) {
    return TrajectoryApp(
      name: _stringField(json, 'name'),
      directory: _stringField(json, 'directory'),
      platform: _stringField(json, 'platform'),
    );
  }

  final String name;
  final String directory;
  final String platform;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'directory': directory,
    'platform': platform,
  };
}

/// Development session the trajectory ran in.
class TrajectorySession {
  const TrajectorySession({
    required this.handle,
    required this.startedByRecorder,
    required this.setupRecorded,
    required this.stopped,
  });

  factory TrajectorySession.fromJson(Map<String, Object?> json) {
    return TrajectorySession(
      handle: _stringField(json, 'handle'),
      startedByRecorder: _boolField(json, 'startedByRecorder'),
      setupRecorded: _boolField(json, 'setupRecorded'),
      stopped: _boolField(json, 'stopped'),
    );
  }

  final String handle;
  final bool startedByRecorder;
  final bool setupRecorded;
  final bool stopped;

  Map<String, Object?> toJson() => <String, Object?>{
    'handle': handle,
    'startedByRecorder': startedByRecorder,
    'setupRecorded': setupRecorded,
    'stopped': stopped,
  };
}

/// Reference to the fixed system prompt in effect for the trajectory.
class TrajectorySystemPrompt {
  const TrajectorySystemPrompt({
    required this.id,
    required this.sha256,
    required this.text,
  });

  factory TrajectorySystemPrompt.fromJson(Map<String, Object?> json) {
    return TrajectorySystemPrompt(
      id: _stringField(json, 'id'),
      sha256: _stringField(json, 'sha256'),
      text: _stringField(json, 'text'),
    );
  }

  final String id;
  final String sha256;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sha256': sha256,
    'text': text,
  };
}

/// Scenario expectation attached to a step: `ok` compares against the exit
/// code, `code` (optional, failure envelopes only) requires the code string
/// to appear in the observation or stderr.
class TrajectoryExpectation {
  const TrajectoryExpectation({required this.ok, this.code});

  factory TrajectoryExpectation.fromJson(Map<String, Object?> json) {
    final code = json['code'];
    if (code != null && code is! String) {
      throw const FormatException('Expectation "code" must be a string.');
    }
    return TrajectoryExpectation(
      ok: _boolField(json, 'ok'),
      code: code as String?,
    );
  }

  final bool ok;
  final String? code;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (code != null) 'code': code,
  };
}

/// Screenshot asset captured by a step, stored under the dataset assets
/// directory and referenced dataset-relatively.
class TrajectoryImage {
  const TrajectoryImage({
    required this.path,
    required this.sha256,
    required this.sizeBytes,
  });

  factory TrajectoryImage.fromJson(Map<String, Object?> json) {
    return TrajectoryImage(
      path: _stringField(json, 'path'),
      sha256: _stringField(json, 'sha256'),
      sizeBytes: _intField(json, 'sizeBytes'),
    );
  }

  final String path;
  final String sha256;
  final int sizeBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
}

/// One executed command and its verbatim observation.
class TrajectoryStep {
  const TrajectoryStep({
    required this.index,
    required this.command,
    required this.exitCode,
    required this.observation,
    required this.stderr,
    required this.durationMs,
    required this.timedOut,
    required this.expectationMet,
    this.expect,
    this.image,
  });

  factory TrajectoryStep.fromJson(Map<String, Object?> json) {
    final expect = json['expect'];
    final image = json['image'];
    return TrajectoryStep(
      index: _intField(json, 'index'),
      command: _stringField(json, 'command'),
      exitCode: _intField(json, 'exitCode'),
      observation: _stringField(json, 'observation'),
      stderr: json['stderr'] as String? ?? '',
      durationMs: _intField(json, 'durationMs'),
      timedOut: _boolField(json, 'timedOut'),
      expect: expect is Map<String, Object?>
          ? TrajectoryExpectation.fromJson(expect)
          : null,
      expectationMet: _boolField(json, 'expectationMet'),
      image: image is Map<String, Object?>
          ? TrajectoryImage.fromJson(image)
          : null,
    );
  }

  final int index;
  final String command;
  final int exitCode;
  final String observation;
  final String stderr;
  final int durationMs;
  final bool timedOut;
  final TrajectoryExpectation? expect;
  final bool expectationMet;
  final TrajectoryImage? image;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'command': command,
    'exitCode': exitCode,
    'observation': observation,
    'stderr': stderr,
    'durationMs': durationMs,
    'timedOut': timedOut,
    if (expect != null) 'expect': expect!.toJson(),
    'expectationMet': expectationMet,
    if (image != null) 'image': image!.toJson(),
  };
}

/// A full recorded episode: goal, ordered steps, completion, outcome.
class Trajectory {
  const Trajectory({
    required this.id,
    required this.app,
    required this.session,
    required this.goal,
    required this.paraphrases,
    required this.systemPrompt,
    required this.steps,
    required this.completion,
    required this.outcome,
    required this.cockpit,
    required this.recordedAt,
    this.derivedFrom,
  });

  factory Trajectory.fromJson(Map<String, Object?> json) {
    final paraphrases = json['paraphrases'];
    final steps = json['steps'];
    if (paraphrases is! List<Object?>) {
      throw const FormatException('Trajectory "paraphrases" must be a list.');
    }
    if (steps is! List<Object?>) {
      throw const FormatException('Trajectory "steps" must be a list.');
    }
    final derivedFrom = json['derivedFrom'];
    if (derivedFrom != null && derivedFrom is! String) {
      throw const FormatException('Trajectory "derivedFrom" must be a string.');
    }
    return Trajectory(
      id: _stringField(json, 'id'),
      app: TrajectoryApp.fromJson(_mapField(json, 'app')),
      session: TrajectorySession.fromJson(_mapField(json, 'session')),
      goal: _stringField(json, 'goal'),
      paraphrases: paraphrases.whereType<String>().toList(),
      systemPrompt: TrajectorySystemPrompt.fromJson(
        _mapField(json, 'systemPrompt'),
      ),
      steps: steps
          .whereType<Map<String, Object?>>()
          .map(TrajectoryStep.fromJson)
          .toList(),
      completion: _stringField(json, 'completion'),
      outcome: trajectoryOutcomeFromJson(_stringField(json, 'outcome')),
      cockpit: _mapField(json, 'cockpit'),
      recordedAt: _stringField(json, 'recordedAt'),
      derivedFrom: derivedFrom as String?,
    );
  }

  final String id;
  final TrajectoryApp app;
  final TrajectorySession session;
  final String goal;
  final List<String> paraphrases;
  final TrajectorySystemPrompt systemPrompt;
  final List<TrajectoryStep> steps;
  final String completion;
  final TrajectoryOutcome outcome;
  final Map<String, Object?> cockpit;
  final String recordedAt;
  final String? derivedFrom;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': trajectorySchema,
    'id': id,
    if (derivedFrom != null) 'derivedFrom': derivedFrom,
    'app': app.toJson(),
    'session': session.toJson(),
    'goal': goal,
    'paraphrases': paraphrases,
    'systemPrompt': systemPrompt.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
    'completion': completion,
    'outcome': trajectoryOutcomeToJson(outcome),
    'cockpit': cockpit,
    'recordedAt': recordedAt,
  };

  /// JSONL line for this trajectory.
  String toJsonLine() => jsonEncode(toJson());

  /// Paraphrase variants of this trajectory: same steps, different goal
  /// phrasing, ids suffixed `-p2`..`-pN`, `derivedFrom` pointing here.
  List<Trajectory> paraphraseVariants() {
    final variants = <Trajectory>[];
    for (var i = 0; i < paraphrases.length; i++) {
      variants.add(
        Trajectory(
          id: '$id-p${i + 2}',
          app: app,
          session: session,
          goal: paraphrases[i],
          paraphrases: const <String>[],
          systemPrompt: systemPrompt,
          steps: steps,
          completion: completion,
          outcome: outcome,
          cockpit: cockpit,
          recordedAt: recordedAt,
          derivedFrom: id,
        ),
      );
    }
    return variants;
  }
}

Map<String, Object?> _mapField(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! Map<String, Object?>) {
    throw FormatException('Trajectory field "$field" must be an object.');
  }
  return value;
}

String _stringField(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw FormatException('Trajectory field "$field" must be a string.');
  }
  return value;
}

int _intField(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw FormatException('Trajectory field "$field" must be an integer.');
  }
  return value;
}

bool _boolField(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw FormatException('Trajectory field "$field" must be a boolean.');
  }
  return value;
}
