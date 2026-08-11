import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../development/cockpit_checkout_identity.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_structured_input.dart';
import '../supervisor/cockpit_supervisor_authorization.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_output.dart';
import 'cockpit_cli_session_handles.dart';
import 'cockpit_cli_timeout.dart';

const int cockpitSuccessExitCode = 0;
const int cockpitUsageExitCode = 64;
const int cockpitDataExitCode = 65;
const int cockpitNoInputExitCode = 66;
const int cockpitUnavailableExitCode = 69;
const int cockpitPermissionExitCode = 77;
const int cockpitTemporaryExitCode = 75;

typedef CockpitSupervisorClientProvider =
    Future<CockpitSupervisorApiClient> Function();
typedef CockpitAuthorizationPolicyStoreProvider =
    Future<CockpitSupervisorAuthorizationPolicyStore> Function();
typedef CockpitCliSessionHandleStoreProvider =
    Future<CockpitCliSessionHandleStore> Function();

typedef CockpitCliAction = Future<int> Function(ArgResults arguments);

final class CockpitCliTimeoutException implements Exception {
  const CockpitCliTimeoutException(this.command, this.timeout);

  final String command;
  final Duration timeout;

  @override
  String toString() =>
      '$command exceeded its ${cockpitFormatDuration(timeout)} timeout.';
}

final class CockpitLeafCommand extends Command<int> {
  CockpitLeafCommand({
    required this.runtime,
    required this.name,
    required this.description,
    required CockpitCliAction action,
    void Function(ArgParser parser)? configure,
    String? example,
    String? invocationSuffix,
    Duration defaultTimeout = cockpitDefaultCliTimeout,
    Duration maximumTimeout = cockpitMaximumCliTimeout,
    String? timeoutDefaultDescription,
    bool actionManagesTimeout = false,
  }) : _action = action,
       _invocationSuffix = invocationSuffix,
       _defaultTimeout = defaultTimeout,
       _maximumTimeout = maximumTimeout,
       _actionManagesTimeout = actionManagesTimeout {
    cockpitAddCliOutputOptions(argParser);
    cockpitAddCliTimeoutOption(
      argParser,
      defaultTimeout: defaultTimeout,
      maximumTimeout: maximumTimeout,
      defaultDescription: timeoutDefaultDescription,
    );
    configure?.call(argParser);
    if (example != null) {
      argParser.addSeparator('Example: $example');
    }
  }

  final CockpitCliRuntime runtime;

  @override
  final String name;

  @override
  final String description;

  final CockpitCliAction _action;
  final String? _invocationSuffix;
  final Duration _defaultTimeout;
  final Duration _maximumTimeout;
  final bool _actionManagesTimeout;

  @override
  String get invocation {
    final suffix = _invocationSuffix;
    if (suffix == null) return super.invocation;
    final parts = <String>[name];
    for (
      Command<int>? command = parent;
      command != null;
      command = command.parent
    ) {
      parts.add(command.name);
    }
    parts.add(runner!.executableName);
    return '${parts.reversed.join(' ')} $suffix';
  }

  @override
  Future<int> run() {
    runtime.configureOutput(
      command: _commandPath(),
      selection: CockpitCliOutputSelection.fromArguments(argResults!),
    );
    final explicitTimeout = argResults!.wasParsed('timeout');
    runtime.configureTimeout(
      explicitTimeout
          ? cockpitReadCliTimeout(argResults!, maximumTimeout: _maximumTimeout)
          : _defaultTimeout,
      explicit: explicitTimeout,
    );
    return _actionManagesTimeout
        ? _action(argResults!)
        : runtime.runTimed(() => _action(argResults!));
  }

  String _commandPath() {
    final parts = <String>[name];
    for (
      Command<int>? command = parent;
      command != null;
      command = command.parent
    ) {
      parts.add(command.name);
    }
    return parts.reversed.join('.');
  }
}

final class CockpitCliRuntime {
  CockpitCliRuntime({
    CockpitSupervisorClientProvider? clientProvider,
    CockpitAuthorizationPolicyStoreProvider? authorizationPolicyStoreProvider,
    CockpitCliSessionHandleStoreProvider? sessionHandleStoreProvider,
    CockpitCheckoutIdentityResolver? checkoutIdentityResolver,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    String? workingDirectory,
    bool? interactive,
  }) : _clientProvider =
           clientProvider ??
           (() => createCockpitSupervisorApiClient(selfContained: true)),
       _authorizationPolicyStoreProvider =
           authorizationPolicyStoreProvider ?? _systemAuthorizationPolicyStore,
       _sessionHandleStoreProvider =
           sessionHandleStoreProvider ?? _systemCliSessionHandleStore,
       _checkoutIdentityResolver =
           checkoutIdentityResolver ?? CockpitCheckoutIdentityResolver(),
       interactive = interactive ?? (stderrSink == null && stderr.hasTerminal),
       stdoutSink = stdoutSink ?? stdout,
       stderrSink = stderrSink ?? stderr,
       workingDirectory = workingDirectory ?? Directory.current.path {
    _outputWriter = CockpitCliOutputWriter(
      stdoutSink: this.stdoutSink,
      workingDirectory: this.workingDirectory,
    );
  }

  final CockpitSupervisorClientProvider _clientProvider;
  final CockpitAuthorizationPolicyStoreProvider
  _authorizationPolicyStoreProvider;
  final CockpitCliSessionHandleStoreProvider _sessionHandleStoreProvider;
  final CockpitCheckoutIdentityResolver _checkoutIdentityResolver;
  final StringSink stdoutSink;
  final StringSink stderrSink;
  final String workingDirectory;
  final bool interactive;
  Future<CockpitSupervisorApiClient>? _client;
  late final CockpitCliOutputWriter _outputWriter;
  String _command = 'cockpit';
  CockpitCliOutputSelection _outputSelection =
      const CockpitCliOutputSelection();
  Future<CockpitSupervisorAuthorizationPolicyStore>? _authorizationPolicyStore;
  Future<CockpitCliSessionHandleStore>? _sessionHandleStore;

  Duration _commandTimeout = cockpitDefaultCliTimeout;
  DateTime _commandDeadline = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
  bool _timeoutExplicit = false;

  Future<CockpitSupervisorApiClient> client() async {
    final client = await (_client ??= _clientProvider());
    client.requestTimeout = remainingTimeout;
    return client;
  }

  Future<CockpitSupervisorApiClient> developmentClient() async {
    final client = await this.client();
    await client.lifecycle.start(
      authorizationMode: CockpitAuthorizationMode.yolo,
      timeout: remainingTimeout,
    );
    client.requestTimeout = remainingTimeout;
    return client;
  }

  Duration get commandTimeout => _commandTimeout;

  DateTime get commandDeadline => _commandDeadline;

  bool get timeoutExplicit => _timeoutExplicit;

  Duration get remainingTimeout {
    final remaining = _commandDeadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      throw CockpitCliTimeoutException(_command, _commandTimeout);
    }
    return remaining;
  }

  Duration get operationTimeout {
    return _operationBudget(remainingTimeout);
  }

  Duration operationBudget({Duration? maximum}) {
    final budget = _operationBudget(_commandTimeout);
    return maximum != null && budget > maximum ? maximum : budget;
  }

  DateTime operationDeadline(CockpitOperationDescriptor descriptor) {
    final remaining = operationTimeout;
    final maximum = Duration(milliseconds: descriptor.maximumTimeoutMs);
    final budget = remaining < maximum ? remaining : maximum;
    return DateTime.now().toUtc().add(budget);
  }

  void configureTimeout(Duration timeout, {required bool explicit}) {
    if (timeout <= Duration.zero || timeout > cockpitMaximumCliTimeout) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    _commandTimeout = timeout;
    _commandDeadline = DateTime.now().toUtc().add(timeout);
    _timeoutExplicit = explicit;
  }

  void adoptOperationTimeout(CockpitOperationDescriptor descriptor) {
    final fallback = Duration(milliseconds: descriptor.defaultTimeoutMs);
    final maximum = Duration(milliseconds: descriptor.maximumTimeoutMs);
    if (fallback <= Duration.zero || maximum < fallback) {
      throw FormatException(
        'Operation ${descriptor.kind} advertises invalid timeout bounds.',
      );
    }
    if (_timeoutExplicit) {
      if (_commandTimeout > maximum) {
        throw FormatException(
          '--timeout cannot exceed '
          '${cockpitFormatDuration(maximum)} for ${descriptor.kind}.',
        );
      }
      return;
    }
    configureTimeout(fallback, explicit: false);
  }

  Future<T> runTimed<T>(Future<T> Function() action) => action().timeout(
    remainingTimeout,
    onTimeout: () =>
        throw CockpitCliTimeoutException(_command, _commandTimeout),
  );

  CockpitCliOutputSelection get outputSelection => _outputSelection;

  Future<CockpitSupervisorAuthorizationPolicyStore>
  authorizationPolicyStore() =>
      _authorizationPolicyStore ??= _authorizationPolicyStoreProvider();

  Future<CockpitCliSessionHandleStore> sessionHandleStore() =>
      _sessionHandleStore ??= _sessionHandleStoreProvider();

  Future<CockpitCliSessionHandle> resolveSessionHandle(
    String reference, {
    String? explicitWorkspaceId,
  }) async {
    final store = await sessionHandleStore();
    final existing = await store.find(reference);
    if (existing != null) {
      if (explicitWorkspaceId != null &&
          explicitWorkspaceId != existing.workspaceId) {
        throw const FormatException(
          'Session handle belongs to a different workspace.',
        );
      }
      return existing;
    }
    if (RegExp(r'^[0-9a-z]+$').hasMatch(reference)) {
      throw FormatException('Unknown CLI session handle $reference.');
    }
    return store.bind(
      workspaceId: await workspaceId(explicitWorkspaceId),
      sessionId: reference,
    );
  }

  Future<CockpitCliSessionHandle> bindSessionHandle({
    required String workspaceId,
    required String sessionId,
  }) async => (await sessionHandleStore()).bind(
    workspaceId: workspaceId,
    sessionId: sessionId,
  );

  Future<List<CockpitCliSessionHandle>> sessionHandles() async =>
      (await sessionHandleStore()).list();

  Future<CockpitCliSessionHandle> sessionHandle(String? reference) async {
    final store = await sessionHandleStore();
    if (reference != null) {
      final handle = await store.find(reference);
      if (handle == null) {
        throw FormatException('Unknown CLI session $reference.');
      }
      return handle;
    }
    final checkout = await checkoutIdentity();
    final handle = await store.activeForPath(
      checkoutIdentity: checkout.value,
      path: await canonicalWorkingDirectory(),
    );
    if (handle == null) {
      throw const FormatException(
        'No session is active for this Flutter project; run '
        '`cockpit session list`.',
      );
    }
    return handle;
  }

  Future<bool> removeSessionHandle(String reference) async =>
      (await sessionHandleStore()).remove(reference);

  Future<CockpitCheckoutIdentity> checkoutIdentity() =>
      _checkoutIdentityResolver.resolve(workingDirectory);

  Future<String> canonicalWorkingDirectory() async =>
      p.normalize(await Directory(workingDirectory).resolveSymbolicLinks());

  Future<CockpitCliSessionHandle> resolveDevelopmentSession(
    String? reference,
  ) async {
    final store = await sessionHandleStore();
    if (reference == null) {
      final checkout = await checkoutIdentity();
      final active = await store.activeForPath(
        checkoutIdentity: checkout.value,
        path: await canonicalWorkingDirectory(),
      );
      if (active == null) {
        throw const FormatException(
          'No active development session for this Flutter project; run '
          '`cockpit dev start`.',
        );
      }
      return _requireDevelopmentHandle(active);
    }
    final handle = await store.find(reference);
    if (handle == null) {
      throw FormatException('Unknown CLI session $reference.');
    }
    return _requireDevelopmentHandle(handle);
  }

  Future<CockpitCliSessionHandle> selectDevelopmentSession(
    String reference,
  ) async => _requireDevelopmentHandle(
    await (await sessionHandleStore()).selectDevelopment(reference),
  );

  Future<CockpitCliSessionHandle> activeDevelopmentSession({
    String? workspaceId,
  }) async {
    final active = await maybeActiveDevelopmentSession(
      workspaceId: workspaceId,
    );
    if (active == null) {
      throw const FormatException(
        'No active development session for this Flutter project; run '
        '`cockpit dev start`.',
      );
    }
    return active;
  }

  Future<CockpitCliSessionHandle?> maybeActiveDevelopmentSession({
    String? workspaceId,
  }) async {
    final checkout = await checkoutIdentity();
    final active = await (await sessionHandleStore()).activeForPath(
      checkoutIdentity: checkout.value,
      path: await canonicalWorkingDirectory(),
      workspaceId: workspaceId,
    );
    if (active == null) return null;
    final development = _requireDevelopmentHandle(active);
    if (workspaceId != null && development.workspaceId != workspaceId) {
      throw const FormatException(
        'The active development session belongs to a different workspace; '
        'select one with --session.',
      );
    }
    return development;
  }

  Future<CockpitCliSessionHandle> bindDevelopmentSession({
    required CockpitCheckoutIdentity checkout,
    required String projectPath,
    required String workspaceId,
    required String sessionId,
    required String targetId,
    required String appId,
    String? entrypoint,
    String? platform,
    String? deviceId,
    String? flavor,
    String lifecycle = 'ready',
    bool? recoverable,
    int? launchTimeoutMilliseconds,
    bool replaceLaunchIdentity = false,
  }) => sessionHandleStore().then(
    (store) => store.bindDevelopment(
      checkoutIdentity: checkout.value,
      checkoutPath: checkout.canonicalRoot,
      projectPath: projectPath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      targetId: targetId,
      appId: appId,
      entrypoint: entrypoint,
      platform: platform,
      deviceId: deviceId,
      flavor: flavor,
      lifecycle: lifecycle,
      recoverable: recoverable,
      launchTimeoutMilliseconds: launchTimeoutMilliseconds,
      replaceLaunchIdentity: replaceLaunchIdentity,
    ),
  );

  Future<CockpitCliSessionHandle> updateDevelopmentSession({
    required CockpitCliSessionHandle previous,
    required String workspaceId,
    required String sessionId,
    required String targetId,
    required String appId,
    String? entrypoint,
    String? platform,
    String? deviceId,
    String? flavor,
    String lifecycle = 'ready',
    bool? recoverable,
    int? launchTimeoutMilliseconds,
    bool replaceLaunchIdentity = false,
  }) {
    final checkoutIdentity = previous.checkoutIdentity;
    final checkoutPath = previous.checkoutPath;
    final projectPath = previous.projectPath;
    if (checkoutIdentity == null ||
        checkoutPath == null ||
        projectPath == null) {
      throw const FormatException(
        'Session handle is not a Flutter development session.',
      );
    }
    return sessionHandleStore().then(
      (store) => store.bindDevelopment(
        checkoutIdentity: checkoutIdentity,
        checkoutPath: checkoutPath,
        projectPath: projectPath,
        workspaceId: workspaceId,
        sessionId: sessionId,
        targetId: targetId,
        appId: appId,
        entrypoint: entrypoint,
        platform: platform,
        deviceId: deviceId,
        flavor: flavor,
        lifecycle: lifecycle,
        recoverable: recoverable,
        launchTimeoutMilliseconds: launchTimeoutMilliseconds,
        replaceLaunchIdentity: replaceLaunchIdentity,
        handleId: previous.handleId,
      ),
    );
  }

  Future<Map<String, Object?>> operationContract(
    CockpitSupervisorApiClient client,
    String reference,
  ) async {
    final uri = Uri.parse(reference);
    if (uri.scheme != 'cockpit' ||
        uri.host != 'operations' ||
        uri.path != '/schema') {
      throw const FormatException('Unsupported operation schema reference.');
    }
    Object? current = await client.operationSchema();
    for (final segment
        in uri.fragment
            .split('/')
            .where((item) => item.isNotEmpty)
            .map((item) => item.replaceAll('~1', '/').replaceAll('~0', '~'))) {
      if (current is! Map<Object?, Object?> || !current.containsKey(segment)) {
        throw FormatException('Unresolved live operation schema: $reference');
      }
      current = current[segment];
    }
    if (current is! Map<Object?, Object?> ||
        current.keys.any((key) => key is! String)) {
      throw FormatException('Invalid live operation schema: $reference');
    }
    return Map<String, Object?>.from(current);
  }

  Future<bool> operationInjectsSession(
    CockpitSupervisorApiClient client,
    CockpitOperationDescriptor descriptor,
  ) async {
    final contract = await operationContract(
      client,
      descriptor.requestSchemaRef,
    );
    final properties = contract['properties'];
    final session = properties is Map<Object?, Object?>
        ? properties['sessionId']
        : null;
    return session is Map<Object?, Object?> &&
        session['x-cockpit-injected-by'] == '--session';
  }

  CockpitIdempotencyKey? operationIdempotencyKey(
    CockpitOperationDescriptor descriptor,
    String? explicit,
  ) {
    if (descriptor.idempotency == CockpitIdempotencyBehavior.prohibited) {
      if (explicit != null) {
        throw FormatException(
          '${descriptor.kind} prohibits an idempotency key.',
        );
      }
      return null;
    }
    if (explicit != null) return CockpitIdempotencyKey(explicit);
    if (descriptor.idempotency == CockpitIdempotencyBehavior.required) {
      return CockpitIdempotencyKey(
        CockpitSecureTokenGenerator().nextResourceId('c'),
      );
    }
    return null;
  }

  Future<CockpitCliSessionHandle?> captureSessionHandle(
    CockpitOperationResult result, {
    String? workspaceId,
  }) async {
    final sessionId = result.output?['sessionId'];
    final ownerWorkspaceId = result.workspaceId ?? workspaceId;
    if (sessionId is! String || ownerWorkspaceId == null) return null;
    return bindSessionHandle(
      workspaceId: ownerWorkspaceId,
      sessionId: sessionId,
    );
  }

  Map<String, Object?> operationReceipt(
    CockpitOperationResult result, {
    CockpitCliSessionHandle? sessionHandle,
    CockpitIdempotencyKey? idempotencyKey,
  }) => <String, Object?>{
    ...result.toJson(),
    if (sessionHandle != null) 'sessionHandle': sessionHandle.handleId,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey.value,
  };

  CockpitSupervisorAuthorizationPolicy authorizationPolicyFile(String path) {
    final resolved = p.normalize(
      p.isAbsolute(path) ? path : p.join(workingDirectory, path),
    );
    final file = File(resolved);
    if (!file.existsSync()) {
      throw FileSystemException(
        'Authorization policy file was not found.',
        resolved,
      );
    }
    if (file.lengthSync() > 1024 * 1024) {
      throw const FormatException('Authorization policy exceeds 1 MiB.');
    }
    return CockpitSupervisorAuthorizationPolicy.fromJson(
      jsonDecode(file.readAsStringSync()),
    );
  }

  void configureOutput({
    required String command,
    required CockpitCliOutputSelection selection,
  }) {
    _command = command;
    _outputSelection = selection;
  }

  void progress(String message) {
    if (!interactive || _outputSelection.format == CockpitCliFormat.none) {
      return;
    }
    stderrSink.writeln('[cockpit] $message');
  }

  Future<void> success(Object? data) async {
    await _outputWriter.writeSuccess(
      command: _command,
      data: data,
      selection: _outputSelection,
    );
  }

  bool get usesPathOutput => _outputSelection.format == CockpitCliFormat.path;

  void fileReceipt(CockpitCliFileReceipt receipt) {
    _outputWriter.writeReceipt(receipt: receipt, selection: _outputSelection);
  }

  void jsonLine(Object? value) {
    _outputWriter.writeJsonLine(
      command: _command,
      data: value,
      selection: _outputSelection,
    );
  }

  void error({
    required String code,
    required String message,
    bool retryable = false,
    String? category,
    String? responsibleLayer,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final boundedMessage = message.length <= 4096
        ? message
        : '${message.substring(0, 4093)}...';
    _outputWriter.writeError(
      code: code,
      message: boundedMessage,
      retryable: retryable,
      category: category,
      responsibleLayer: responsibleLayer,
      details: details,
      selection: _outputSelection,
      stderrSink: stderrSink,
    );
  }

  Future<String> workspaceId(String? explicit) async {
    final workspaces = await (await client()).workspaces();
    if (explicit != null) {
      final matches = workspaces.where(
        (workspace) => workspace.workspaceId == explicit,
      );
      if (matches.length != 1 ||
          matches.single.state != CockpitWorkspaceState.active) {
        throw CockpitSupervisorClientException(
          code: 'workspaceNotFound',
          message: 'Active workspace $explicit was not found.',
        );
      }
      return explicit;
    }
    final active = await maybeActiveDevelopmentSession();
    if (active != null &&
        workspaces.any(
          (workspace) =>
              workspace.workspaceId == active.workspaceId &&
              workspace.state == CockpitWorkspaceState.active,
        )) {
      return active.workspaceId;
    }
    final canonicalCwd = p.normalize(
      await Directory(workingDirectory).resolveSymbolicLinks(),
    );
    final containing =
        workspaces
            .where(
              (workspace) =>
                  workspace.state == CockpitWorkspaceState.active &&
                  (p.equals(workspace.canonicalPath, canonicalCwd) ||
                      p.isWithin(workspace.canonicalPath, canonicalCwd)),
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                right.canonicalPath.length.compareTo(left.canonicalPath.length),
          );
    if (containing.isNotEmpty) {
      final selected = containing.first;
      if (containing
          .skip(1)
          .any(
            (workspace) =>
                p.equals(workspace.canonicalPath, selected.canonicalPath),
          )) {
        throw const CockpitSupervisorClientException(
          code: 'workspaceAmbiguous',
          message: 'Current project has duplicate active workspaces.',
        );
      }
      return selected.workspaceId;
    }
    final descendants = workspaces
        .where(
          (workspace) =>
              workspace.state == CockpitWorkspaceState.active &&
              p.isWithin(canonicalCwd, workspace.canonicalPath),
        )
        .toList(growable: false);
    if (descendants.length == 1) return descendants.single.workspaceId;
    throw CockpitSupervisorClientException(
      code: descendants.isEmpty ? 'workspaceNotFound' : 'workspaceAmbiguous',
      message: descendants.isEmpty
          ? 'Current directory does not resolve to an active workspace.'
          : 'Multiple project workspaces are active below this directory; '
                'run inside one project or pass --workspace-id.',
    );
  }

  Map<String, Object?> structuredObject(
    String? inline,
    String? file, {
    String option = 'input',
  }) {
    if (inline != null && file != null) {
      throw FormatException('Use only one of --$option and --$option-file.');
    }
    final source =
        inline ?? (file == null ? '{}' : File(file).readAsStringSync());
    if (utf8.encode(source).length > cockpitSupervisorMaximumResponseBytes) {
      throw const FormatException('Structured input exceeds 1 MiB.');
    }
    final value = decodeCockpitStructuredInput(source);
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw const FormatException('Input must be an object.');
    }
    return Map<String, Object?>.from(value);
  }
}

Duration _operationBudget(Duration available) {
  final milliseconds = available.inMilliseconds;
  final grace = milliseconds >= 10000
      ? 1000
      : milliseconds >= 1000
      ? 100
      : 1;
  return Duration(
    milliseconds: milliseconds > grace ? milliseconds - grace : 1,
  );
}

CockpitCliSessionHandle _requireDevelopmentHandle(
  CockpitCliSessionHandle handle,
) {
  if (!handle.isDevelopment ||
      handle.targetId == null ||
      handle.appId == null ||
      handle.entrypoint == null ||
      handle.platform == null ||
      handle.deviceId == null) {
    throw const FormatException(
      'Development session state is incomplete; run `cockpit dev start`.',
    );
  }
  return handle;
}

Future<CockpitSupervisorAuthorizationPolicyStore>
_systemAuthorizationPolicyStore() async {
  final resolver = CockpitHomeResolver.system();
  final home = CockpitHome.system();
  final paths = await home.initialize();
  return CockpitSupervisorAuthorizationPolicyStore(
    path: paths.authorizationPolicy,
    permissionHardener: home.permissionHardener,
    directorySyncer: CockpitSystemDirectorySyncer(resolver.platform),
  );
}

Future<CockpitCliSessionHandleStore> _systemCliSessionHandleStore() async {
  final resolver = CockpitHomeResolver.system();
  final home = CockpitHome.system();
  final paths = await home.initialize();
  return CockpitCliSessionHandleStore.file(
    path: paths.cliSessions,
    permissionHardener: home.permissionHardener,
    directorySyncer: CockpitSystemDirectorySyncer(resolver.platform),
  );
}

int cockpitExitCodeFor(CockpitApiError error) => switch (error.code) {
  CockpitErrorCode.authenticationRequired ||
  CockpitErrorCode.authorizationDenied => cockpitPermissionExitCode,
  CockpitErrorCode.notFound => cockpitNoInputExitCode,
  _ when error.retryable => cockpitTemporaryExitCode,
  _ => cockpitDataExitCode,
};

int cockpitExitCodeForOperation(CockpitOperationResult result) {
  if (result.lifecycle != CockpitOperationLifecycle.completed ||
      result.outcome == null) {
    return cockpitTemporaryExitCode;
  }
  return switch (result.outcome!) {
    CockpitOperationOutcome.succeeded => cockpitSuccessExitCode,
    CockpitOperationOutcome.cancelled ||
    CockpitOperationOutcome.interrupted => cockpitTemporaryExitCode,
    CockpitOperationOutcome.failed || CockpitOperationOutcome.blocked =>
      cockpitExitCodeFor(result.failure!.primary),
  };
}
