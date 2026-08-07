import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_execute_remote_command_service.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_session_registry.dart';

final class CockpitRunCommandRequest {
  const CockpitRunCommandRequest({
    required this.command,
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.iosDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.standard(),
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
    this.defaultCommandTimeout = const Duration(seconds: 30),
    this.cancellation,
  });

  final CockpitCommand command;
  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
  final Duration defaultCommandTimeout;
  final Future<void>? cancellation;
}

typedef CockpitRunCommandResult = CockpitExecuteRemoteCommandResult;

final class CockpitRunCommandService {
  CockpitRunCommandService({
    CockpitExecuteRemoteCommandService? executeService,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitSessionRegistry? registry,
  }) : _executeService = executeService ?? CockpitExecuteRemoteCommandService(),
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry);

  final CockpitExecuteRemoteCommandService _executeService;
  final CockpitAppReferenceResolver _appReferenceResolver;

  Future<CockpitRunCommandResult> run(CockpitRunCommandRequest request) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    return _executeService.execute(
      CockpitExecuteRemoteCommandRequest(
        baseUri: resolved.baseUri,
        sessionHandle: resolved.app?.remoteSession,
        command: request.command,
        resultProfile: request.resultProfile,
        snapshotOptions: request.snapshotOptions,
        compareAgainstSnapshotRef: request.compareAgainstSnapshotRef,
        defaultCommandTimeout: request.defaultCommandTimeout,
        cancellation: request.cancellation,
      ),
    );
  }
}
