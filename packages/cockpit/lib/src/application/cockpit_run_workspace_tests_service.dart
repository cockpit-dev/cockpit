import '../infrastructure/cockpit_file_system.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../infrastructure/cockpit_sdk_environment.dart';
import 'cockpit_workspace_command_result.dart';
import 'cockpit_workspace_tooling_support.dart';

final class CockpitRunWorkspaceTestsRequest {
  const CockpitRunWorkspaceTestsRequest({
    required this.workspaceRoot,
    this.allowedRoots = const <String>[],
    this.paths = const <String>[],
    this.name,
    this.timeout = const Duration(minutes: 5),
  });

  final String workspaceRoot;
  final List<String> allowedRoots;
  final List<String> paths;
  final String? name;
  final Duration timeout;
}

final class CockpitRunWorkspaceTestsService {
  CockpitRunWorkspaceTestsService({
    CockpitFileSystem? fileSystem,
    CockpitProcessManager? processManager,
    CockpitSdkEnvironment? sdkEnvironment,
  }) : _fileSystem = fileSystem ?? const LocalCockpitFileSystem(),
       _processManager = processManager ?? const LocalCockpitProcessManager(),
       _sdkEnvironment = sdkEnvironment ?? CockpitSdkEnvironment.current();

  final CockpitFileSystem _fileSystem;
  final CockpitProcessManager _processManager;
  final CockpitSdkEnvironment _sdkEnvironment;

  Future<CockpitWorkspaceCommandResult> run(
    CockpitRunWorkspaceTestsRequest request,
  ) {
    final paths = _confinedArguments(request);
    final arguments = <String>[
      'test',
      if (request.name != null) ...<String>['--name', request.name!],
      ...paths,
    ];
    return runWorkspaceCommand(
      fileSystem: _fileSystem,
      processManager: _processManager,
      sdkEnvironment: _sdkEnvironment,
      workspaceRoot: request.workspaceRoot,
      allowedRoots: request.allowedRoots,
      toolchain: null,
      dartArguments: arguments,
      flutterArguments: arguments,
      timeout: request.timeout,
    );
  }

  List<String> _confinedArguments(CockpitRunWorkspaceTestsRequest request) {
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
