import '../infrastructure/cockpit_file_system.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../infrastructure/cockpit_sdk_environment.dart';
import 'cockpit_workspace_command_result.dart';
import 'cockpit_workspace_tooling_support.dart';

final class CockpitFormatWorkspaceRequest {
  const CockpitFormatWorkspaceRequest({
    required this.workspaceRoot,
    this.allowedRoots = const <String>[],
    this.paths = const <String>[],
    this.timeout = const Duration(seconds: 90),
  });

  final String workspaceRoot;
  final List<String> allowedRoots;
  final List<String> paths;
  final Duration timeout;
}

final class CockpitFormatWorkspaceService {
  CockpitFormatWorkspaceService({
    CockpitFileSystem? fileSystem,
    CockpitProcessManager? processManager,
    CockpitSdkEnvironment? sdkEnvironment,
  }) : _fileSystem = fileSystem ?? const LocalCockpitFileSystem(),
       _processManager = processManager ?? const LocalCockpitProcessManager(),
       _sdkEnvironment = sdkEnvironment ?? CockpitSdkEnvironment.current();

  final CockpitFileSystem _fileSystem;
  final CockpitProcessManager _processManager;
  final CockpitSdkEnvironment _sdkEnvironment;

  Future<CockpitWorkspaceCommandResult> format(
    CockpitFormatWorkspaceRequest request,
  ) {
    final paths = _confinedArguments(request);
    return runWorkspaceCommand(
      fileSystem: _fileSystem,
      processManager: _processManager,
      sdkEnvironment: _sdkEnvironment,
      workspaceRoot: request.workspaceRoot,
      allowedRoots: request.allowedRoots,
      toolchain: CockpitWorkspaceToolchain.dart,
      dartArguments: <String>['format', if (paths.isEmpty) '.' else ...paths],
      timeout: request.timeout,
    );
  }

  List<String> _confinedArguments(CockpitFormatWorkspaceRequest request) {
    final context = _fileSystem.pathContext;
    final root = assertWorkspaceRootAllowed(
      request.workspaceRoot,
      request.allowedRoots,
      pathContext: context,
    );
    return <String>[
      for (final path in request.paths)
        context.relative(
          assertWorkspaceRootAllowed(
            context.normalize(
              context.isAbsolute(path) ? path : context.join(root, path),
            ),
            <String>[root],
            pathContext: context,
          ),
          from: root,
        ),
    ];
  }
}
