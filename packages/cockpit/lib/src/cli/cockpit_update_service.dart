import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../foundation/cockpit_version.dart';
import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_update_installation.dart';
import 'cockpit_update_models.dart';
import 'cockpit_update_support.dart';

export 'cockpit_update_models.dart';

final class CockpitUpdateService {
  CockpitUpdateService({
    CockpitUpdateProcessRunner? processRunner,
    CockpitLatestVersionLookup? latestVersionLookup,
    CockpitHostedInstallProbe? hostedInstallProbe,
    Map<String, String>? environment,
    bool? windows,
    String? resolvedExecutable,
  }) : _processRunner = processRunner ?? _runProcess,
       _latestVersionLookup = latestVersionLookup ?? cockpitLookupLatestVersion,
       _environment = environment ?? Platform.environment,
       _windows = windows ?? Platform.isWindows,
       _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _hostedInstallProbe =
           hostedInstallProbe ??
           ((version) => cockpitHasCanonicalHostedInstall(
             environment: environment ?? Platform.environment,
             windows: windows ?? Platform.isWindows,
             resolvedExecutable:
                 resolvedExecutable ?? Platform.resolvedExecutable,
             version: version,
           ));

  final CockpitUpdateProcessRunner _processRunner;
  final CockpitLatestVersionLookup _latestVersionLookup;
  final CockpitHostedInstallProbe _hostedInstallProbe;
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
    onProgress?.call('Checking for Cockpit updates...');
    if (await _canSkipInstall(currentVersion, deadline)) {
      await _cleanupLegacySourcePayload();
      onProgress?.call('Reconnecting the Cockpit Supervisor...');
      await _reconnectSupervisor(_resolvedExecutable, deadline);
      return CockpitUpdateResult(
        previousVersion: currentVersion,
        version: currentVersion,
      );
    }
    late final CockpitUpdateInstallation installation;
    try {
      installation = await CockpitUpdateInstallation.prepare(
        processRunner: _processRunner,
        environment: _environment,
        windows: _windows,
        resolvedExecutable: _resolvedExecutable,
      );
    } on Object catch (error) {
      throw CockpitUpdateException(
        'updateInstallFailed',
        'Cockpit could not prepare its installed executable for update. '
            '${cockpitBoundUpdateText('$error')}',
      );
    }
    var completed = false;

    try {
      onProgress?.call('Installing the latest Cockpit release...');
      final activation = await _invoke(
        dart,
        const <String>['pub', 'global', 'activate', 'cockpit'],
        deadline,
        failureCode: 'updateInstallFailed',
        failureMessage:
            'Dart Pub could not install the latest Cockpit release.',
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
      _requireNoDowngrade(
        currentVersion: currentVersion,
        installedVersion: installedVersion,
      );
      await installation.acceptHosted();

      onProgress?.call('Optimizing the installed Cockpit executable...');
      await installation.installHostedAot(
        version: installedVersion,
        deadline: deadline,
      );

      await _cleanupLegacySourcePayload();
      onProgress?.call('Reconnecting the Cockpit Supervisor...');
      await _reconnectSupervisor(installation.executablePath, deadline);
      try {
        await installation.finish();
      } on Object catch (error) {
        throw CockpitUpdateException(
          'updateCleanupFailed',
          'Cockpit was updated, but temporary update files could not be '
              'removed. ${cockpitBoundUpdateText('$error')}',
        );
      }
      completed = true;

      return CockpitUpdateResult(
        previousVersion: currentVersion,
        version: installedVersion,
      );
    } finally {
      if (!completed) await installation.abort();
    }
  }

  Future<bool> _canSkipInstall(String currentVersion, DateTime deadline) async {
    try {
      if (!await _hostedInstallProbe(currentVersion)) return false;
      final latestText = await _latestVersionLookup(_remaining(deadline));
      final current = Version.parse(currentVersion);
      final latest = Version.parse(latestText);
      return latest < current || latestText == currentVersion;
    } on Object {
      return false;
    }
  }

  Future<void> _reconnectSupervisor(
    String? executable,
    DateTime deadline,
  ) async {
    if (executable == null) {
      throw const CockpitUpdateException(
        'updateSupervisorFailed',
        'The installed Cockpit executable could not be located.',
      );
    }
    final remaining = _remaining(deadline);
    final supervisor = await _invoke(
      executable,
      <String>[
        'server',
        '--format',
        'none',
        '--timeout',
        '${remaining.inMilliseconds}ms',
      ],
      deadline,
      failureCode: 'updateSupervisorFailed',
      failureMessage: 'Cockpit could not reconnect its Supervisor.',
    );
    _requireSuccess(
      supervisor,
      code: 'updateSupervisorFailed',
      message: 'Cockpit could not reconnect its Supervisor.',
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
    try {
      return cockpitReadInstalledVersion(output);
    } on FormatException {
      throw const CockpitUpdateException(
        'updateVerificationFailed',
        'The updated Cockpit executable returned an invalid version.',
        retryable: false,
      );
    }
  }

  void _requireNoDowngrade({
    required String currentVersion,
    required String installedVersion,
  }) {
    try {
      final current = Version.parse(currentVersion);
      final installed = Version.parse(installedVersion);
      if (installed >= current) return;
    } on FormatException {
      throw const CockpitUpdateException(
        'updateVerificationFailed',
        'Cockpit could not compare the current and installed versions.',
        retryable: false,
      );
    }
    throw CockpitUpdateException(
      'updateDowngradeBlocked',
      'Dart Pub resolved Cockpit $installedVersion, which is older than the '
          'running $currentVersion release. The current executable was kept; '
          'retry after Pub finishes publishing the newer release.',
    );
  }

  Future<void> _cleanupLegacySourcePayload() async {
    try {
      await cockpitRemoveLegacySourcePayload(
        environment: _environment,
        windows: _windows,
        resolvedExecutable: _resolvedExecutable,
      );
    } on Object catch (error) {
      throw CockpitUpdateException(
        'updateCleanupFailed',
        'Cockpit could not remove its retired source payload. '
            '${cockpitBoundUpdateText('$error')}',
      );
    }
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
