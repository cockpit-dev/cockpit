import 'dart:io';

import '../foundation/cockpit_version.dart';
import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_update_models.dart';
import 'cockpit_update_support.dart';

export 'cockpit_update_models.dart';

final class CockpitUpdateService {
  CockpitUpdateService({
    CockpitUpdateProcessRunner? processRunner,
    Map<String, String>? environment,
    bool? windows,
    String? resolvedExecutable,
  }) : _processRunner = processRunner ?? _runProcess,
       _environment = environment ?? Platform.environment,
       _windows = windows ?? Platform.isWindows,
       _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable;

  final CockpitUpdateProcessRunner _processRunner;
  final Map<String, String> _environment;
  final bool _windows;
  final String _resolvedExecutable;

  Future<CockpitUpdateResult> update({
    String currentVersion = cockpitVersion,
    Duration timeout = const Duration(minutes: 10),
    void Function(String message)? onProgress,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    final deadline = DateTime.now().toUtc().add(timeout);
    final dart = _windows ? 'dart.exe' : 'dart';

    onProgress?.call('Installing the latest Cockpit release...');
    final activation = await _invoke(
      dart,
      const <String>['pub', 'global', 'activate', 'cockpit', 'any'],
      deadline,
      failureCode: 'updateInstallFailed',
      failureMessage: 'Dart Pub could not install the latest Cockpit release.',
    );
    _requireSuccess(
      activation,
      code: 'updateInstallFailed',
      message: 'Dart Pub could not install the latest Cockpit release.',
    );

    onProgress?.call('Verifying the installed Cockpit release...');
    final probe = await _invoke(
      dart,
      const <String>['pub', 'global', 'run', 'cockpit:cockpit', '--version'],
      deadline,
      failureCode: 'updateVerificationFailed',
      failureMessage: 'The updated Cockpit executable could not be verified.',
    );
    _requireSuccess(
      probe,
      code: 'updateVerificationFailed',
      message: 'The updated Cockpit executable could not be verified.',
    );
    final installedVersion = _readVersion('${probe.stdout}');
    try {
      await _removeLegacySourcePayload();
    } on Object catch (error) {
      throw CockpitUpdateException(
        'updateCleanupFailed',
        'Cockpit was updated, but its retired source payload could not be '
            'removed. ${cockpitBoundUpdateText('$error')}',
      );
    }

    onProgress?.call('Reconnecting the Cockpit Supervisor...');
    final remaining = _remaining(deadline);
    final supervisor = await _invoke(
      dart,
      <String>[
        'pub',
        'global',
        'run',
        'cockpit:cockpit',
        'server',
        '--format',
        'none',
        '--timeout',
        '${remaining.inMilliseconds}ms',
      ],
      deadline,
      failureCode: 'updateSupervisorFailed',
      failureMessage:
          'Cockpit was updated, but the Supervisor could not reconnect.',
    );
    _requireSuccess(
      supervisor,
      code: 'updateSupervisorFailed',
      message: 'Cockpit was updated, but the Supervisor could not reconnect.',
    );

    return CockpitUpdateResult(
      previousVersion: currentVersion,
      version: installedVersion,
    );
  }

  Future<ProcessResult> _invoke(
    String executable,
    List<String> arguments,
    DateTime deadline, {
    required String failureCode,
    required String failureMessage,
  }) async {
    try {
      return await _processRunner(executable, arguments, _remaining(deadline));
    } on CockpitManagedProcessTimeoutException {
      throw CockpitUpdateException(
        failureCode,
        '$failureMessage The update exceeded its timeout.',
      );
    } on Object catch (error) {
      throw CockpitUpdateException(
        failureCode,
        '$failureMessage ${cockpitBoundUpdateText('$error')}',
      );
    }
  }

  void _requireSuccess(
    ProcessResult result, {
    required String code,
    required String message,
  }) {
    if (result.exitCode == 0) return;
    final diagnostic = cockpitUpdateDiagnostic(result);
    throw CockpitUpdateException(
      code,
      diagnostic == null ? message : '$message $diagnostic',
    );
  }

  String _readVersion(String output) {
    final match = RegExp(
      r'^cockpit\s+(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$',
    ).firstMatch(output.trim());
    if (match == null) {
      throw const CockpitUpdateException(
        'updateVerificationFailed',
        'The updated Cockpit executable returned an invalid version.',
        retryable: false,
      );
    }
    return match.group(1)!;
  }

  Future<void> _removeLegacySourcePayload() async {
    await cockpitRemoveLegacySourcePayload(
      environment: _environment,
      windows: _windows,
      resolvedExecutable: _resolvedExecutable,
    );
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
  Duration timeout,
) => cockpitRunUpdateProcess(executable, arguments, timeout);

Duration _remaining(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) {
    throw const CockpitUpdateException(
      'updateTimeout',
      'Cockpit update exceeded its timeout.',
    );
  }
  return remaining;
}
