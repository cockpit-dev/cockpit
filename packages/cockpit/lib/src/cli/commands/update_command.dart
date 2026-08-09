import 'dart:async';

import '../../foundation/cockpit_version.dart';
import '../cockpit_cli_runtime.dart';
import '../cockpit_update_service.dart';

CockpitLeafCommand cockpitUpdateCommand(
  CockpitCliRuntime runtime, {
  CockpitUpdateService? service,
}) => CockpitLeafCommand(
  runtime: runtime,
  name: 'update',
  description: 'Update Cockpit and reconnect its Supervisor.',
  defaultTimeout: const Duration(minutes: 10),
  maximumTimeout: const Duration(minutes: 30),
  actionManagesTimeout: true,
  action: (_) async {
    final updater = service ?? CockpitUpdateService();
    runtime.progress('Current Cockpit version: $cockpitVersion.');
    final heartbeat = Timer.periodic(
      const Duration(seconds: 10),
      (_) => runtime.progress('Cockpit update is still running...'),
    );
    try {
      final result = await updater.update(
        timeout: runtime.remainingTimeout,
        onProgress: runtime.progress,
      );
      await runtime.success(result.toJson());
      return cockpitSuccessExitCode;
    } on CockpitUpdateException catch (error) {
      runtime.error(
        code: error.code,
        message: error.message,
        retryable: error.retryable,
      );
      return error.retryable
          ? cockpitTemporaryExitCode
          : cockpitUnavailableExitCode;
    } finally {
      heartbeat.cancel();
    }
  },
);
