import 'dart:async';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'acp_provider.dart';
import 'core_providers.dart';

const _maximumRetainedRunEvents = 2000;

/// Extracts an operation-level failure message from a raw operation-result
/// body. Returns null when the operation succeeded (or reported no outcome).
String? _operationFailure(Map<String, Object?> result) {
  final outcome = result['outcome'] as String?;
  if (outcome == null || outcome == 'succeeded') return null;
  final failure = result['failure'];
  if (failure is Map) {
    final primary = failure['primary'];
    if (primary is Map) {
      final message = primary['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
      final code = primary['code'] as String?;
      if (code != null && code.isNotEmpty) return code;
    }
  }
  final kind = result['kind'] as String? ?? 'operation';
  return '$kind $outcome';
}

/// Mirrors the canonical automation-target requirement: native, desktop, and
/// browser targets require an explicit platform app id.
bool targetKindRequiresAppId(CockpitTargetKind kind) => switch (kind) {
  CockpitTargetKind.nativeApp ||
  CockpitTargetKind.desktopApp ||
  CockpitTargetKind.browserPage => true,
  CockpitTargetKind.flutterApp ||
  CockpitTargetKind.systemSurface ||
  CockpitTargetKind.device ||
  CockpitTargetKind.hostWorkspace => false,
};

// ── Roots ────────────────────────────────────────────────────────────────

final class RootsState {
  const RootsState({this.items = const [], this.loading = false, this.error});

  final List<CockpitRootResource> items;
  final bool loading;
  final String? error;

  RootsState copyWith({
    List<CockpitRootResource>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return RootsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final class RootsNotifier extends Notifier<RootsState> {
  int _refreshGeneration = 0;

  @override
  RootsState build() => const RootsState();

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final roots = await client.roots();
      if (generation != _refreshGeneration) return;
      state = RootsState(items: roots, loading: false);
    } on Object catch (error) {
      if (generation != _refreshGeneration) return;
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<bool> register({required String path, String? label}) async {
    state = state.copyWith(clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      await client.registerRoot(path: path, label: label);
      await refresh();
      return true;
    } on Object catch (error) {
      state = state.copyWith(error: '$error');
      return false;
    }
  }

  Future<bool> remove({required String rootId, bool force = false}) async {
    state = state.copyWith(clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      await client.removeRoot(rootId: rootId, force: force);
      await Future.wait([
        refresh(),
        ref.read(workspacesProvider.notifier).refresh(),
      ]);
      return true;
    } on Object catch (error) {
      state = state.copyWith(error: '$error');
      return false;
    }
  }
}

final rootsProvider = NotifierProvider<RootsNotifier, RootsState>(
  RootsNotifier.new,
);

// ── Workspaces ───────────────────────────────────────────────────────────

final class WorkspacesState {
  const WorkspacesState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<CockpitWorkspaceResource> items;
  final bool loading;
  final String? error;

  WorkspacesState copyWith({
    List<CockpitWorkspaceResource>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return WorkspacesState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final class WorkspacesNotifier extends Notifier<WorkspacesState> {
  int _refreshGeneration = 0;

  @override
  WorkspacesState build() => const WorkspacesState();

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final workspaces = await client.workspaces();
      if (generation != _refreshGeneration) return;
      state = WorkspacesState(items: workspaces, loading: false);
      final selectedWorkspaceId = ref.read(selectedWorkspaceIdProvider);
      if (selectedWorkspaceId != null &&
          !workspaces.any(
            (workspace) => workspace.workspaceId == selectedWorkspaceId,
          )) {
        ref.read(selectedWorkspaceIdProvider.notifier).select(null);
      }
    } on Object catch (error) {
      if (generation != _refreshGeneration) return;
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<bool> register({required String rootId, required String path}) async {
    state = state.copyWith(clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final workspace = await client.registerWorkspace(
        rootId: rootId,
        path: path,
      );
      await refresh();
      ref
          .read(selectedWorkspaceIdProvider.notifier)
          .select(workspace.workspaceId);
      return true;
    } on Object catch (error) {
      state = state.copyWith(error: '$error');
      return false;
    }
  }

  Future<bool> rebind({
    required String workspaceId,
    required String path,
    required String expectedCheckoutId,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      await client.rebindWorkspace(
        workspaceId: workspaceId,
        path: path,
        expectedCheckoutId: expectedCheckoutId,
      );
      await refresh();
      return true;
    } on Object catch (error) {
      state = state.copyWith(error: '$error');
      return false;
    }
  }

  Future<bool> remove({required String workspaceId, bool force = false}) async {
    state = state.copyWith(clearError: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      await client.removeWorkspace(workspaceId: workspaceId, force: force);
      if (ref.read(selectedWorkspaceIdProvider) == workspaceId) {
        ref.read(selectedWorkspaceIdProvider.notifier).select(null);
      }
      await refresh();
      return true;
    } on Object catch (error) {
      state = state.copyWith(error: '$error');
      return false;
    }
  }
}

final workspacesProvider =
    NotifierProvider<WorkspacesNotifier, WorkspacesState>(
      WorkspacesNotifier.new,
    );

// ── Targets ──────────────────────────────────────────────────────────────

/// A locally discovered Flutter launch target (from `target.discover`), not a
/// registered automation target. Mirrors the Supervisor's launch-target shape.
final class CockpitDiscoveredTarget {
  const CockpitDiscoveredTarget({
    required this.id,
    required this.name,
    required this.platform,
    required this.platformType,
    this.emulator = false,
    this.ephemeral = false,
    this.sdk,
  });

  factory CockpitDiscoveredTarget.fromJson(Map<String, dynamic> json) {
    return CockpitDiscoveredTarget(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      platformType: json['platformType'] as String? ?? '',
      emulator: json['emulator'] as bool? ?? false,
      ephemeral: json['ephemeral'] as bool? ?? false,
      sdk: json['sdk'] as String?,
    );
  }

  final String id;
  final String name;
  final String platform;
  final String platformType;
  final bool emulator;
  final bool ephemeral;
  final String? sdk;
}

final class TargetDiscoveryResult {
  const TargetDiscoveryResult({
    required this.targets,
    required this.discoveredAt,
  });
  final List<CockpitDiscoveredTarget> targets;
  final DateTime discoveredAt;
}

final class DiscoveredTargetsNotifier extends Notifier<TargetDiscoveryResult?> {
  @override
  TargetDiscoveryResult? build() => null;

  void set(TargetDiscoveryResult? result) {
    state = result;
  }
}

final discoveredTargetsProvider =
    NotifierProvider<DiscoveredTargetsNotifier, TargetDiscoveryResult?>(
      DiscoveredTargetsNotifier.new,
    );

final class TargetsState {
  const TargetsState({
    this.workspaceId,
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final String? workspaceId;
  final List<CockpitAutomationTargetResource> items;
  final bool loading;
  final String? error;

  TargetsState copyWith({
    String? workspaceId,
    List<CockpitAutomationTargetResource>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return TargetsState(
      workspaceId: workspaceId ?? this.workspaceId,
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final class TargetsNotifier extends Notifier<TargetsState> {
  int _refreshGeneration = 0;

  @override
  TargetsState build() => const TargetsState();

  Future<void> refresh(String workspaceId) async {
    final generation = ++_refreshGeneration;
    state = state.workspaceId == workspaceId
        ? state.copyWith(loading: true, clearError: true)
        : TargetsState(workspaceId: workspaceId, loading: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final items = await client.targets(workspaceId);
      if (generation != _refreshGeneration) return;
      state = TargetsState(
        workspaceId: workspaceId,
        items: items,
        loading: false,
      );
    } on Object catch (e) {
      if (generation != _refreshGeneration) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Discovers Flutter launch targets. Throws on failure so the caller can
  /// surface it; never swallows discovery errors.
  Future<void> discover() async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    final result = await client.executeOperation(
      kind: 'target.discover',
      input: const <String, Object?>{'timeoutMs': 60000},
    );
    final failure = _operationFailure(result);
    if (failure != null) {
      throw Exception('Target discovery failed: $failure');
    }
    final output = result['output'];
    final rawTargets = output is Map ? output['targets'] : null;
    final targets = <CockpitDiscoveredTarget>[
      for (final item in rawTargets is List ? rawTargets : const <Object?>[])
        if (item is Map<String, dynamic>)
          CockpitDiscoveredTarget.fromJson(item),
    ];
    ref
        .read(discoveredTargetsProvider.notifier)
        .set(
          TargetDiscoveryResult(targets: targets, discoveredAt: DateTime.now()),
        );
  }

  /// Registers an automation target with the canonical `target.register`
  /// input shape. Returns the new target id, or throws on failure so the
  /// caller surfaces the exact error.
  Future<String> register({
    required String workspaceId,
    required String platform,
    required String deviceId,
    required CockpitTargetKind targetKind,
    CockpitTestTargetEnvironment environment =
        CockpitTestTargetEnvironment.development,
    CockpitAppMode mode = CockpitAppMode.development,
    String? appId,
    String? entrypointDocumentId,
    String? flavor,
    String? wdaUrl,
    required String idempotencyKey,
  }) async {
    if (targetKindRequiresAppId(targetKind) &&
        (appId == null || appId.trim().isEmpty)) {
      throw ArgumentError.value(
        appId,
        'appId',
        '${targetKind.name} targets require an appId.',
      );
    }
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    final result = await client.executeOperation(
      kind: 'target.register',
      workspaceId: workspaceId,
      idempotencyKey: idempotencyKey,
      input: <String, Object?>{
        'platform': platform,
        'deviceId': deviceId,
        'targetKind': targetKind.name,
        'environment': environment.name,
        'mode': mode.jsonValue,
        'appId': ?appId,
        'entrypointDocumentId': ?entrypointDocumentId,
        if (flavor != null && flavor.trim().isNotEmpty) 'flavor': flavor.trim(),
        if (wdaUrl != null && wdaUrl.trim().isNotEmpty) 'wdaUrl': wdaUrl.trim(),
      },
    );
    final failure = _operationFailure(result);
    if (failure != null) {
      throw Exception('Target registration failed: $failure');
    }
    final output = result['output'];
    final targetId = output is Map ? output['targetId'] as String? : null;
    if (targetId == null) {
      throw const FormatException('Target registration returned no target id.');
    }
    if (ref.read(selectedWorkspaceIdProvider) == workspaceId) {
      await refresh(workspaceId);
    }
    return targetId;
  }

  /// Launches a registered target with the canonical `target.launch` input
  /// shape. [mode] and [launchConfiguration] apply only to entrypoint-backed
  /// Flutter targets; passing them for system-control targets is rejected by
  /// the worker, so callers must omit them there. Throws on failure.
  Future<void> launch({
    required String workspaceId,
    required String targetId,
    CockpitAppMode? mode,
    int? launchTimeoutMs,
    CockpitFlutterLaunchConfiguration? launchConfiguration,
    required String idempotencyKey,
  }) async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    final result = await client.executeOperation(
      kind: 'target.launch',
      workspaceId: workspaceId,
      idempotencyKey: idempotencyKey,
      input: <String, Object?>{
        'targetId': targetId,
        if (mode != null) 'mode': mode.jsonValue,
        'launchTimeoutMs': ?launchTimeoutMs,
        if (launchConfiguration != null && !launchConfiguration.isEmpty)
          'launchConfiguration': launchConfiguration.toJson(
            includeEnvironmentValues: true,
          ),
      },
    );
    final failure = _operationFailure(result);
    if (failure != null) {
      throw Exception('Target launch failed: $failure');
    }
    if (ref.read(selectedWorkspaceIdProvider) == workspaceId) {
      await refresh(workspaceId);
    }
  }
}

final targetsProvider = NotifierProvider<TargetsNotifier, TargetsState>(
  TargetsNotifier.new,
);

// ── Documents ────────────────────────────────────────────────────────────

final documentsForWorkspaceProvider =
    FutureProvider.family<List<CockpitDocumentResource>, String>((
      ref,
      workspaceId,
    ) async {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      return client.documents(workspaceId, authoredOnly: true);
    });

final sourceDocumentsForWorkspaceProvider =
    FutureProvider.family<List<CockpitDocumentResource>, String>((
      ref,
      workspaceId,
    ) async {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      return client.documents(
        workspaceId,
        kind: CockpitIndexedDocumentKind.source,
      );
    });

final casesForWorkspaceProvider =
    FutureProvider.family<List<CockpitCaseIndexEntry>, String>((
      ref,
      workspaceId,
    ) async {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      return client.cases(workspaceId);
    });

final class DocumentValidation {
  const DocumentValidation({
    required this.valid,
    required this.errors,
    required this.warnings,
  });

  factory DocumentValidation.fromResult(Map<String, Object?> result) {
    final valid = result['valid'] as bool? ?? false;
    final diagnostics = result['diagnostics'] as List? ?? const <Object?>[];
    final errors = diagnostics
        .whereType<Map>()
        .where((diagnostic) => diagnostic['severity'] == 'error')
        .map((diagnostic) => diagnostic['message'] as String? ?? '')
        .where((message) => message.isNotEmpty)
        .toList(growable: true);
    if (!valid && errors.isEmpty) {
      errors.add('Document validation failed without a diagnostic.');
    }
    final warnings = diagnostics
        .whereType<Map>()
        .where((diagnostic) => diagnostic['severity'] == 'warning')
        .map((diagnostic) => diagnostic['message'] as String? ?? '')
        .where((message) => message.isNotEmpty);
    return DocumentValidation(
      valid: valid,
      errors: List<String>.unmodifiable(errors),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  final bool valid;
  final List<String> errors;
  final List<String> warnings;
}

final class DocumentEditorState {
  const DocumentEditorState({
    this.workspaceId,
    this.content = '',
    this.format = CockpitDocumentFormat.yaml,
    this.relativePath = 'document.yaml',
    this.persistedContent = '',
    this.persistedRelativePath = 'document.yaml',
    this.validating = false,
    this.saving = false,
    this.validation,
  });

  final String? workspaceId;
  final String content;
  final CockpitDocumentFormat format;
  final String relativePath;
  final String persistedContent;
  final String persistedRelativePath;
  final bool validating;
  final bool saving;
  final DocumentValidation? validation;

  bool get dirty =>
      content != persistedContent || relativePath != persistedRelativePath;

  DocumentEditorState copyWith({
    String? workspaceId,
    String? content,
    CockpitDocumentFormat? format,
    String? relativePath,
    String? persistedContent,
    String? persistedRelativePath,
    bool? validating,
    bool? saving,
    DocumentValidation? validation,
    bool clearValidation = false,
  }) {
    return DocumentEditorState(
      workspaceId: workspaceId ?? this.workspaceId,
      content: content ?? this.content,
      format: format ?? this.format,
      relativePath: relativePath ?? this.relativePath,
      persistedContent: persistedContent ?? this.persistedContent,
      persistedRelativePath:
          persistedRelativePath ?? this.persistedRelativePath,
      validating: validating ?? this.validating,
      saving: saving ?? this.saving,
      validation: clearValidation ? null : validation ?? this.validation,
    );
  }
}

final class DocumentNotifier extends Notifier<DocumentEditorState> {
  int _validationGeneration = 0;
  int _workspaceGeneration = 0;
  int _saveSerial = 0;

  @override
  DocumentEditorState build() => const DocumentEditorState();
  void activateWorkspace(String workspaceId) {
    if (state.workspaceId == workspaceId) return;
    _workspaceGeneration++;
    _validationGeneration++;
    state = DocumentEditorState(workspaceId: workspaceId);
  }

  void setContent(String content) {
    if (state.saving) return;
    _validationGeneration += 1;
    state = state.copyWith(
      content: content,
      validating: false,
      clearValidation: true,
    );
  }

  void setFormat(CockpitDocumentFormat format) {
    if (state.saving || state.format == format) return;
    _validationGeneration += 1;
    state = state.copyWith(
      format: format,
      relativePath: p.setExtension(state.relativePath, '.${format.name}'),
      validating: false,
      clearValidation: true,
    );
  }

  void setRelativePath(String relativePath) {
    if (state.saving) return;
    _validationGeneration += 1;
    state = state.copyWith(
      relativePath: relativePath,
      validating: false,
      clearValidation: true,
    );
  }

  void newDocument() {
    if (state.saving) return;
    _validationGeneration += 1;
    state = DocumentEditorState(
      workspaceId: state.workspaceId,
      format: state.format,
      relativePath: 'document.${state.format.name}',
      persistedRelativePath: 'document.${state.format.name}',
    );
  }

  void clearValidation() {
    _validationGeneration += 1;
    state = state.copyWith(validating: false, clearValidation: true);
  }

  /// Reads the real workspace-confined file backing an indexed document and
  /// loads it into the editor, inferring format from the extension. Throws on
  /// IO error so the caller can surface it.
  Future<void> selectDocument({
    required String workspaceId,
    required CockpitDocumentResource document,
  }) async {
    final generation = _workspaceGeneration;
    final workspace = await _requireWorkspace(workspaceId);
    final file = File(
      confinePathToRoot(document.relativePath, workspace.canonicalPath),
    );
    final content = await file.readAsString();
    if (generation != _workspaceGeneration ||
        state.workspaceId != workspaceId) {
      return;
    }
    final format = switch (p.extension(document.relativePath).toLowerCase()) {
      '.lon' => CockpitDocumentFormat.lon,
      '.json' => CockpitDocumentFormat.json,
      _ => CockpitDocumentFormat.yaml,
    };
    _validationGeneration += 1;
    state = DocumentEditorState(
      workspaceId: workspaceId,
      content: content,
      format: format,
      relativePath: document.relativePath,
      persistedContent: content,
      persistedRelativePath: document.relativePath,
    );
  }

  Future<void> validate(String workspaceId) async {
    if (state.workspaceId != workspaceId) return;
    final sourceText = state.content;
    final format = state.format;
    final relativePath = state.relativePath;
    final generation = ++_validationGeneration;
    if (sourceText.trim().isEmpty) {
      state = state.copyWith(validating: false, clearValidation: true);
      return;
    }
    state = state.copyWith(validating: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final result = await client.validateDocument(
        workspaceId,
        sourceText: sourceText,
        relativePath: relativePath,
        format: format.name,
      );
      if (generation != _validationGeneration) return;
      state = state.copyWith(
        validating: false,
        validation: DocumentValidation.fromResult(result),
      );
    } on Object catch (error) {
      if (generation != _validationGeneration) return;
      state = state.copyWith(
        validating: false,
        validation: DocumentValidation(
          valid: false,
          errors: ['$error'],
          warnings: const [],
        ),
      );
    }
  }

  /// Validates, atomically replaces, and indexes one workspace-confined
  /// document. A failed validation or index leaves the previous file intact.
  Future<({bool ok, String message})> saveAndIndex({
    required String workspaceId,
  }) async {
    if (state.workspaceId != workspaceId) {
      return (
        ok: false,
        message: 'The selected workspace changed before the save started.',
      );
    }
    if (state.saving) {
      return (ok: false, message: 'A document save is already in progress.');
    }
    final relativePath = p.normalize(state.relativePath.trim());
    final content = state.content;
    if (content.trim().isEmpty) {
      return (ok: false, message: 'Document content cannot be empty.');
    }
    if (relativePath.isEmpty ||
        relativePath == '.' ||
        p.isAbsolute(relativePath)) {
      return (ok: false, message: 'Document path must be workspace-relative.');
    }
    final extension = p.extension(relativePath).toLowerCase();
    final extensionMatches = switch (state.format) {
      CockpitDocumentFormat.lon => extension == '.lon',
      CockpitDocumentFormat.json => extension == '.json',
      CockpitDocumentFormat.yaml => extension == '.yaml' || extension == '.yml',
    };
    if (!extensionMatches) {
      return (
        ok: false,
        message: switch (state.format) {
          CockpitDocumentFormat.lon => 'LON documents must use a .lon path.',
          CockpitDocumentFormat.json => 'JSON documents must use a .json path.',
          CockpitDocumentFormat.yaml =>
            'YAML documents must use a .yaml or .yml path.',
        },
      );
    }

    final workspaceGeneration = _workspaceGeneration;
    final validationGeneration = _validationGeneration;
    final transactionSerial = ++_saveSerial;
    state = state.copyWith(saving: true, validating: true);
    try {
      final workspace = await _requireWorkspace(workspaceId);
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final validationResult = await client.validateDocument(
        workspaceId,
        sourceText: content,
        relativePath: relativePath,
        format: state.format.name,
      );
      if (workspaceGeneration != _workspaceGeneration ||
          validationGeneration != _validationGeneration ||
          state.workspaceId != workspaceId) {
        return (
          ok: false,
          message: 'The document changed while validation was in progress.',
        );
      }
      final validation = DocumentValidation.fromResult(validationResult);
      state = state.copyWith(validating: false, validation: validation);
      if (!validation.valid) {
        return (ok: false, message: validation.errors.first);
      }

      final file = File(
        confinePathToRoot(relativePath, workspace.canonicalPath),
      );
      final cleanupWarning = await _replaceAndIndexDocument(
        client: client,
        workspaceId: workspaceId,
        relativePath: relativePath,
        content: content,
        file: file,
        transactionSerial: transactionSerial,
      );
      if (workspaceGeneration == _workspaceGeneration &&
          state.workspaceId == workspaceId) {
        state = state.copyWith(
          relativePath: relativePath,
          persistedContent: content,
          persistedRelativePath: relativePath,
        );
      }
      ref.invalidate(documentsForWorkspaceProvider(workspaceId));
      ref.invalidate(casesForWorkspaceProvider(workspaceId));
      return (
        ok: true,
        message: cleanupWarning == null
            ? 'Indexed $relativePath'
            : 'Indexed $relativePath. $cleanupWarning',
      );
    } on Object catch (error) {
      return (ok: false, message: '$error');
    } finally {
      if (workspaceGeneration == _workspaceGeneration &&
          state.workspaceId == workspaceId) {
        state = state.copyWith(saving: false, validating: false);
      }
    }
  }

  Future<String?> _replaceAndIndexDocument({
    required ConsoleSupervisorClient client,
    required String workspaceId,
    required String relativePath,
    required String content,
    required File file,
    required int transactionSerial,
  }) async {
    await file.parent.create(recursive: true);
    final suffix = '.cockpit-console-$pid-$transactionSerial';
    final temporary = File('${file.path}$suffix.tmp');
    final backup = File('${file.path}$suffix.bak');
    var movedOriginal = false;
    var installedReplacement = false;
    var indexed = false;
    try {
      await temporary.writeAsString(content, flush: true);
      if (await file.exists()) {
        await file.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(file.path);
      installedReplacement = true;
      final result = await client.executeOperation(
        kind: 'document.index',
        workspaceId: workspaceId,
        idempotencyKey:
            'document-index-${DateTime.now().microsecondsSinceEpoch}-$transactionSerial',
        input: <String, Object?>{'relativePath': relativePath},
      );
      final failure = _operationFailure(result);
      if (failure != null) {
        throw StateError('Document index failed: $failure');
      }
      final output = result['output'];
      if (output is! Map || output['matchedCount'] != 1) {
        throw const FormatException(
          'Document index did not retain the saved document.',
        );
      }
      indexed = true;
    } on Object catch (error) {
      if (!indexed) {
        final rollbackFailures = <Object>[];
        if (installedReplacement && await file.exists()) {
          try {
            await file.delete();
          } on Object catch (rollbackError) {
            rollbackFailures.add(rollbackError);
          }
        }
        if (movedOriginal && await backup.exists()) {
          try {
            await backup.rename(file.path);
          } on Object catch (rollbackError) {
            rollbackFailures.add(rollbackError);
          }
        }
        if (await temporary.exists()) {
          try {
            await temporary.delete();
          } on Object catch (rollbackError) {
            rollbackFailures.add(rollbackError);
          }
        }
        if (rollbackFailures.isNotEmpty) {
          throw FileSystemException(
            'Document save failed ($error) and rollback failed '
            '(${rollbackFailures.join('; ')}). Recovery backup: ${backup.path}',
            file.path,
          );
        }
      }
      rethrow;
    }

    if (movedOriginal && await backup.exists()) {
      try {
        await backup.delete();
      } on Object catch (error) {
        return 'The previous-file backup could not be removed: $error';
      }
    }
    return null;
  }

  Future<CockpitWorkspaceResource> _requireWorkspace(String workspaceId) async {
    var workspace = _findWorkspace(workspaceId);
    if (workspace == null) {
      await ref.read(workspacesProvider.notifier).refresh();
      workspace = _findWorkspace(workspaceId);
    }
    if (workspace == null) {
      throw StateError('Workspace $workspaceId is not registered.');
    }
    return workspace;
  }

  CockpitWorkspaceResource? _findWorkspace(String workspaceId) {
    for (final item in ref.read(workspacesProvider).items) {
      if (item.workspaceId == workspaceId) return item;
    }
    return null;
  }
}

final documentProvider =
    NotifierProvider<DocumentNotifier, DocumentEditorState>(
      DocumentNotifier.new,
    );

// ── Operations ───────────────────────────────────────────────────────────

final operationsProvider =
    FutureProvider.family<List<CockpitOperationDescriptor>, String?>((
      ref,
      workspaceId,
    ) async {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      return client.operations(workspaceId: workspaceId);
    });

// ── Generic operation invocation ─────────────────────────────────────────

/// Generates a canonical idempotency-key value for an operation invocation.
///
/// Keys are alphanumeric-prefixed and bounded to the protocol's 128-character
/// limit so they satisfy [CockpitIdempotencyKey] validation.
String generateOperationIdempotencyKey(String kind) =>
    '$kind-${DateTime.now().microsecondsSinceEpoch}';

/// Parses a LON, JSON, or YAML object from the operation input editor.
Map<String, Object?> parseOperationInput(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return const <String, Object?>{};
  final decoded = decodeCockpitStructuredInput(trimmed);
  if (decoded is! Map<Object?, Object?> ||
      decoded.keys.any((key) => key is! String)) {
    throw const FormatException(
      'Operation input must be a LON, JSON, or YAML object.',
    );
  }
  return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(decoded));
}

/// Console state for inspecting and invoking one advertised operation at a
/// time. Selection, structured input, and any retained result are owned here so
/// a stale response can never surface under another operation, root, or
/// workspace.
final class OperationInvocationState {
  const OperationInvocationState({
    this.selectedKind,
    this.selectedWorkspaceId,
    this.selectedRootId,
    this.inputText = '{}',
    this.idempotencyKey = '',
    this.submitting = false,
    this.result,
    this.resultKind,
    this.resultRootId,
    this.resultWorkspaceId,
    this.error,
  });

  final String? selectedKind;
  final String? selectedWorkspaceId;
  final String? selectedRootId;
  final String inputText;
  final String idempotencyKey;
  final bool submitting;

  /// The full structured operation-result envelope, retained verbatim for
  /// inspection. Tagged with [resultKind] / [resultRootId] /
  /// [resultWorkspaceId] so the UI can prove it belongs to the current view
  /// before rendering it.
  final Map<String, Object?>? result;
  final String? resultKind;
  final String? resultRootId;
  final String? resultWorkspaceId;

  /// A precise, single-line failure description: an extracted operation
  /// failure message, a transport error (`code: message`), or malformed-input
  /// detail. Null only when the last invocation succeeded.
  final String? error;

  /// True when the retained result belongs to the given selection. A result
  /// produced for another operation, root, or workspace is never shown.
  bool resultBelongsTo({
    required String? kind,
    required String? rootId,
    required String? workspaceId,
  }) =>
      result != null &&
      resultKind == kind &&
      resultRootId == rootId &&
      resultWorkspaceId == workspaceId;

  OperationInvocationState copyWith({
    String? selectedKind,
    String? selectedWorkspaceId,
    String? selectedRootId,
    bool clearSelectedKind = false,
    bool clearSelectedWorkspaceId = false,
    bool clearSelectedRootId = false,
    String? inputText,
    String? idempotencyKey,
    bool? submitting,
    Map<String, Object?>? result,
    String? resultKind,
    String? resultRootId,
    String? resultWorkspaceId,
    String? error,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return OperationInvocationState(
      selectedKind: clearSelectedKind
          ? null
          : selectedKind ?? this.selectedKind,
      selectedWorkspaceId: clearSelectedWorkspaceId
          ? null
          : selectedWorkspaceId ?? this.selectedWorkspaceId,
      selectedRootId: clearSelectedRootId
          ? null
          : selectedRootId ?? this.selectedRootId,
      inputText: inputText ?? this.inputText,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      submitting: submitting ?? this.submitting,
      result: clearResult ? null : result ?? this.result,
      resultKind: clearResult ? null : resultKind ?? this.resultKind,
      resultRootId: clearResult ? null : resultRootId ?? this.resultRootId,
      resultWorkspaceId: clearResult
          ? null
          : resultWorkspaceId ?? this.resultWorkspaceId,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final class OperationInvocationNotifier
    extends Notifier<OperationInvocationState> {
  int _selectionGeneration = 0;

  @override
  OperationInvocationState build() => const OperationInvocationState();

  /// Records the active workspace, resetting any retained result so a result
  /// produced for a previous workspace can never surface under a new one.
  void activateWorkspace(String? workspaceId) {
    if (state.selectedWorkspaceId == workspaceId) return;
    _selectionGeneration += 1;
    state = state.copyWith(
      selectedWorkspaceId: workspaceId,
      clearSelectedWorkspaceId: workspaceId == null,
      clearResult: true,
      clearError: true,
    );
  }

  /// Selects an operation for inspection, resetting the editor and any
  /// retained result so it cannot appear under a different operation.
  void select(String? kind) {
    if (state.selectedKind == kind) return;
    _selectionGeneration += 1;
    state = state.copyWith(
      selectedKind: kind,
      clearSelectedKind: kind == null,
      inputText: '{}',
      idempotencyKey: '',
      clearResult: true,
      clearError: true,
    );
  }

  /// Selects the project root for a root-scoped operation, resetting any
  /// retained result so it cannot appear under a different root.
  void selectRoot(String? rootId) {
    if (state.selectedRootId == rootId) return;
    _selectionGeneration += 1;
    state = state.copyWith(
      selectedRootId: rootId,
      clearSelectedRootId: rootId == null,
      clearResult: true,
      clearError: true,
    );
  }

  void setInput(String text) {
    if (state.submitting) return;
    state = state.copyWith(inputText: text, clearError: true);
  }

  void setIdempotencyKey(String key) {
    if (state.submitting) return;
    state = state.copyWith(idempotencyKey: key, clearError: true);
  }

  /// Invokes [descriptor] through the canonical client.
  ///
  /// [rootId] / [workspaceId] are the scope identities the caller resolved for
  /// this operation: [rootId] for root-scoped operations, [workspaceId] for
  /// workspace-scoped operations, both null for supervisor-scoped operations.
  /// Concurrent duplicate submissions are refused by the single-flight
  /// [OperationInvocationState.submitting] guard; the idempotency key is
  /// resolved per the descriptor contract (generated for required, passed
  /// through for optional, rejected for prohibited); the structured input is
  /// parsed precisely; and the response is generation-guarded so a result
  /// produced before a selection/root/workspace change is discarded rather than
  /// shown.
  Future<void> invoke({
    required CockpitOperationDescriptor descriptor,
    required String? rootId,
    required String? workspaceId,
  }) async {
    if (state.submitting) return;
    final generation = _selectionGeneration;

    final Map<String, Object?> input;
    try {
      input = parseOperationInput(state.inputText);
    } on FormatException catch (error) {
      state = state.copyWith(
        error: error.message.isEmpty
            ? 'Operation input is not a valid LON, JSON, or YAML object.'
            : error.message,
      );
      return;
    }

    final trimmedKey = state.idempotencyKey.trim();
    final String? resolvedKey;
    switch (descriptor.idempotency) {
      case CockpitIdempotencyBehavior.required:
        resolvedKey = trimmedKey.isEmpty
            ? generateOperationIdempotencyKey(descriptor.kind)
            : trimmedKey;
      case CockpitIdempotencyBehavior.optional:
        resolvedKey = trimmedKey.isEmpty ? null : trimmedKey;
      case CockpitIdempotencyBehavior.prohibited:
        if (trimmedKey.isNotEmpty) {
          state = state.copyWith(
            error: 'Operation ${descriptor.kind} prohibits an idempotency key.',
          );
          return;
        }
        resolvedKey = null;
    }
    if (resolvedKey != null && resolvedKey != state.idempotencyKey) {
      state = state.copyWith(idempotencyKey: resolvedKey);
    }

    state = state.copyWith(
      submitting: true,
      clearResult: true,
      clearError: true,
    );
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final result = await client.executeOperation(
        kind: descriptor.kind,
        rootId: rootId,
        workspaceId: workspaceId,
        input: input,
        idempotencyKey: resolvedKey,
      );
      if (generation != _selectionGeneration) return;
      final failure = _operationFailure(result);
      state = state.copyWith(
        submitting: false,
        result: result,
        resultKind: descriptor.kind,
        resultRootId: rootId,
        resultWorkspaceId: workspaceId,
        error: failure,
      );
    } on CockpitSupervisorClientException catch (error) {
      if (generation != _selectionGeneration) return;
      state = state.copyWith(
        submitting: false,
        error: '${error.code}: ${error.message}',
      );
    } on Object catch (error) {
      if (generation != _selectionGeneration) return;
      state = state.copyWith(submitting: false, error: '$error');
    } finally {
      if (state.submitting) {
        state = state.copyWith(submitting: false);
      }
    }
  }
}

final operationInvocationProvider =
    NotifierProvider<OperationInvocationNotifier, OperationInvocationState>(
      OperationInvocationNotifier.new,
    );

// ── Runs ─────────────────────────────────────────────────────────────────

final class RunEvent {
  const RunEvent({
    required this.kind,
    required this.message,
    required this.timestamp,
    this.sequence,
  });

  final String kind;
  final String message;
  final DateTime timestamp;
  final int? sequence;
}

final class RunsState {
  const RunsState({
    this.workspaceId,
    this.currentRunId,
    this.submitting = false,
    this.events = const [],
    this.error,
  });

  final String? workspaceId;
  final String? currentRunId;
  final bool submitting;
  final List<RunEvent> events;
  final String? error;

  RunsState copyWith({
    String? workspaceId,
    String? currentRunId,
    bool? submitting,
    List<RunEvent>? events,
    String? error,
    bool clearError = false,
  }) {
    return RunsState(
      workspaceId: workspaceId ?? this.workspaceId,
      currentRunId: currentRunId ?? this.currentRunId,
      submitting: submitting ?? this.submitting,
      events: events ?? this.events,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final class RunsNotifier extends Notifier<RunsState> {
  int _submissionGeneration = 0;

  @override
  RunsState build() => const RunsState();
  void activateWorkspace(String workspaceId) {
    if (state.workspaceId == workspaceId) return;
    _submissionGeneration++;
    state = RunsState(workspaceId: workspaceId);
  }

  bool isCurrentRun(String runId) => state.currentRunId == runId;

  /// Submits an indexed case and returns its run id on acceptance.
  Future<String?> submitCase({
    required String workspaceId,
    required String documentId,
    required String caseId,
    required String documentSha256,
    required String idempotencyKey,
    Map<String, Object?> inputs = const <String, Object?>{},
    String? targetId,
    int? timeoutMs,
  }) => _submit(
    workspaceId: workspaceId,
    source: CockpitIndexedCaseSource(
      reference: CockpitIndexedCaseReference(
        documentId: documentId,
        caseId: caseId,
        documentSha256: documentSha256,
      ),
    ),
    idempotencyKey: idempotencyKey,
    inputs: inputs,
    targetId: targetId,
    timeoutMs: timeoutMs,
  );

  /// Submits an indexed suite and returns its durable campaign run id.
  Future<String?> submitSuite({
    required String workspaceId,
    required String documentId,
    required String suiteId,
    required String documentSha256,
    required String idempotencyKey,
    Map<String, Object?> inputs = const <String, Object?>{},
    String? targetId,
    int? timeoutMs,
  }) => _submit(
    workspaceId: workspaceId,
    source: CockpitIndexedSuiteSource(
      reference: CockpitIndexedSuiteReference(
        documentId: documentId,
        suiteId: suiteId,
        documentSha256: documentSha256,
      ),
    ),
    idempotencyKey: idempotencyKey,
    inputs: inputs,
    targetId: targetId,
    timeoutMs: timeoutMs,
  );

  Future<String?> _submit({
    required String workspaceId,
    required CockpitRunSubmissionSource source,
    required String idempotencyKey,
    required Map<String, Object?> inputs,
    required String? targetId,
    required int? timeoutMs,
  }) async {
    final generation = ++_submissionGeneration;
    state = state.workspaceId == workspaceId
        ? state.copyWith(submitting: true, clearError: true)
        : RunsState(workspaceId: workspaceId, submitting: true);
    try {
      final client = await ref.read(supervisorProvider.notifier).ensureClient();
      final result = await client.submitRun(
        workspaceId,
        source: source,
        idempotencyKey: idempotencyKey,
        inputs: inputs,
        targetId: targetId,
        timeoutMs: timeoutMs,
      );
      if (generation != _submissionGeneration ||
          state.workspaceId != workspaceId) {
        return null;
      }
      final runId = result['runId'] as String?;
      if (runId == null) {
        state = state.copyWith(
          submitting: false,
          error: 'Run submission returned no run id.',
        );
        return null;
      }
      state = RunsState(
        workspaceId: workspaceId,
        currentRunId: runId,
        submitting: false,
        events: const [],
      );
      return runId;
    } on Object catch (error) {
      if (generation == _submissionGeneration &&
          state.workspaceId == workspaceId) {
        state = state.copyWith(submitting: false, error: '$error');
      }
      return null;
    }
  }

  void addEvent(String runId, RunEvent event) {
    if (!isCurrentRun(runId)) return;
    final retained = state.events.length < _maximumRetainedRunEvents
        ? state.events
        : state.events.sublist(
            state.events.length - _maximumRetainedRunEvents + 1,
          );
    state = state.copyWith(events: [...retained, event]);
  }

  void clearEvents() {
    state = state.copyWith(events: const []);
  }

  void setCurrentRun({required String workspaceId, required String? runId}) {
    _submissionGeneration++;
    state = RunsState(workspaceId: workspaceId, currentRunId: runId);
  }

  /// Cancels a run. Throws on failure so the caller surfaces the exact error.
  Future<void> cancel({
    required String runId,
    required String idempotencyKey,
  }) async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    await client.cancelRun(runId, idempotencyKey: idempotencyKey);
  }

  /// Fetches the current run resource. Throws on failure.
  Future<Map<String, Object?>> getRun(String runId) async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    return client.getRun(runId);
  }

  /// Lists artifacts for a run. Throws on failure.
  Future<List<CockpitArtifactResource>> artifacts(String runId) async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    return client.artifacts(runId);
  }

  /// Streams an artifact to a destination file via core, which verifies size
  /// and digest. Throws if the destination exists or integrity checks fail.
  Future<void> downloadArtifact({
    required CockpitArtifactResource artifact,
    required File destination,
  }) async {
    final client = await ref.read(supervisorProvider.notifier).ensureClient();
    await client.downloadArtifactToFile(
      artifact: artifact,
      destination: destination,
    );
  }

  /// Observes the SSE event stream for a run as raw JSON data payloads.
  Stream<String> observeEvents(String runId, {int afterSequence = 0}) {
    return ref
        .read(supervisorProvider.notifier)
        .requireClient()
        .events(runId, afterSequence: afterSequence);
  }
}

final runsProvider = NotifierProvider<RunsNotifier, RunsState>(
  RunsNotifier.new,
);
