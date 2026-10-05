/// Subprocess execution of the `cockpit` CLI, with an injectable interface
/// so the recorder engine can be unit-tested without a live session.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of one cockpit CLI invocation.
class CockpitCommandResult {
  const CockpitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    required this.timedOut,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool timedOut;
}

/// Runs a cockpit argv (without the binary) in a working directory.
abstract class CockpitRunner {
  Future<CockpitCommandResult> run(
    List<String> argv, {
    required String workingDirectory,
    required Duration timeout,
  });
}

/// Real implementation: `<bin> <argv...>` via [Process.run] with a hard
/// timeout that kills the process.
class ProcessCockpitRunner implements CockpitRunner {
  ProcessCockpitRunner({required this.bin});

  /// The cockpit executable to invoke (`cockpit` on PATH by default).
  final String bin;

  @override
  Future<CockpitCommandResult> run(
    List<String> argv, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      bin,
      argv,
      workingDirectory: workingDirectory,
    );
    final stdoutSink = BytesBuilder();
    final stderrSink = BytesBuilder();
    var timedOut = false;

    final stdoutFuture = process.stdout.listen(stdoutSink.add).asFuture<void>();
    final stderrFuture = process.stderr.listen(stderrSink.add).asFuture<void>();
    final exitFuture = process.exitCode;

    final finished = await Future.any(<Future<Object?>>[
      Future.wait<void>(<Future<void>>[
        stdoutFuture,
        stderrFuture,
      ]).then((_) => exitFuture),
      Future<void>.delayed(timeout, () => null),
    ]);

    if (finished == null) {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      await exitFuture;
      await stdoutFuture.catchError((Object _) {});
      await stderrFuture.catchError((Object _) {});
    }

    return CockpitCommandResult(
      exitCode: finished is int ? finished : -1,
      stdout: utf8.decode(stdoutSink.takeBytes()),
      stderr: utf8.decode(stderrSink.takeBytes()),
      durationMs: stopwatch.elapsedMilliseconds,
      timedOut: timedOut,
    );
  }
}
