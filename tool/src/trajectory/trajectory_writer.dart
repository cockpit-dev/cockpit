/// Dataset writer: appends recorded trajectories (and their paraphrase
/// variants) to per-scenario JSONL files.
library;

import 'dart:convert';
import 'dart:io';

import 'trajectory.dart';

class TrajectoryWriter {
  const TrajectoryWriter();

  /// Appends the trajectory, plus one variant per paraphrase when
  /// [includeParaphrases] is set, to `<datasetDirectory>/<scenarioId>.jsonl`.
  ///
  /// Returns the number of records written in this call.
  Future<int> write({
    required RecordedRecord record,
    required String datasetDirectory,
    bool includeParaphrases = true,
  }) async {
    final trajectories = includeParaphrases
        ? <Trajectory>[
            record.trajectory,
            ...record.trajectory.paraphraseVariants(),
          ]
        : <Trajectory>[record.trajectory];
    Directory(datasetDirectory).createSync(recursive: true);
    final sink = File(
      '$datasetDirectory/${record.scenarioId}.jsonl',
    ).openWrite(mode: FileMode.append);
    try {
      for (final trajectory in trajectories) {
        sink.write('${trajectory.toJsonLine()}\n');
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return trajectories.length;
  }
}

/// Input bundle for [TrajectoryWriter.write]: the scenario id and the
/// recorded trajectory.
class RecordedRecord {
  const RecordedRecord({required this.scenarioId, required this.trajectory});

  final String scenarioId;
  final Trajectory trajectory;
}

/// Validates JSONL dataset files: every line must parse into a trajectory
/// of the current schema, and referenced image assets must exist.
class TrajectoryDatasetValidator {
  const TrajectoryDatasetValidator();

  /// Returns per-file error messages; empty result means the dataset is
  /// valid.
  Future<List<String>> validate(String datasetDirectory) async {
    final errors = <String>[];
    final directory = Directory(datasetDirectory);
    if (!directory.existsSync()) {
      return <String>['Dataset directory does not exist: $datasetDirectory'];
    }
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.jsonl'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      return <String>['No .jsonl files found in $datasetDirectory'];
    }
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final lines = const LineSplitter().convert(await file.readAsString());
      if (lines.where((line) => line.isNotEmpty).isEmpty) {
        errors.add('$name: empty file.');
        continue;
      }
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, Object?>) {
            throw const FormatException('Record is not a JSON object.');
          }
          if (decoded['schema'] != trajectorySchema) {
            throw FormatException("Unexpected schema '${decoded['schema']}'.");
          }
          final trajectory = Trajectory.fromJson(decoded);
          for (final image
              in trajectory.steps
                  .map((step) => step.image)
                  .whereType<TrajectoryImage>()) {
            final asset = File('$datasetDirectory/${image.path}');
            if (!asset.existsSync()) {
              errors.add('$name line ${i + 1}: missing asset ${image.path}');
            }
          }
        } on FormatException catch (error) {
          errors.add('$name line ${i + 1}: ${error.message}');
        } on TypeError {
          errors.add('$name line ${i + 1}: malformed record.');
        }
      }
    }
    return errors;
  }
}
