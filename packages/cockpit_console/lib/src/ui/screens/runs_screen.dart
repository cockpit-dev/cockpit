import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

String _newIdempotencyKey(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

Map<String, Object?> parseRunInputs(
  String source, {
  Translations? translations,
}) {
  final t = translations ?? AppLocale.en.translations;
  final trimmed = source.trim();
  if (trimmed.isEmpty) return const <String, Object?>{};
  final decoded = decodeCockpitStructuredInput(trimmed);
  if (decoded is! Map<Object?, Object?> ||
      decoded.keys.any((key) => key is! String)) {
    throw FormatException(t.runs.inputsObjectError);
  }
  return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(decoded));
}

int? parseRunTimeout(
  String source, {
  required bool isSuite,
  Translations? translations,
}) {
  final t = translations ?? AppLocale.en.translations;
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(
    r'^(\d+)(ms|s|m|h)?$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) {
    throw FormatException(t.runs.durationError);
  }
  final value = int.parse(match.group(1)!);
  final multiplier = switch (match.group(2)?.toLowerCase()) {
    null || 'ms' => 1,
    's' => 1000,
    'm' => 60000,
    'h' => 3600000,
    _ => throw FormatException(t.runs.timeoutUnitError),
  };
  final timeoutMs = value * multiplier;
  final maximum = isSuite ? 86400000 : 21600000;
  if (timeoutMs < 1 || timeoutMs > maximum) {
    throw FormatException(
      t.runs.timeoutRangeError(maximum: isSuite ? '24h' : '6h'),
    );
  }
  return timeoutMs;
}

String _runTargetLabel(CockpitAutomationTargetResource target) {
  final entrypoint = target.entrypoint;
  final detail = entrypoint == null
      ? target.appId ?? target.deviceId
      : _compactRunPath(entrypoint);
  return '${target.platform} · $detail';
}

String _compactRunPath(String value) {
  final parts = value.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return value;
  return parts.sublist(parts.length - 2).join('/');
}

String _runDocumentLabel(Translations t, CockpitDocumentResource document) {
  final kind = document.kind == CockpitIndexedDocumentKind.suite
      ? t.runs.suite
      : t.runs.caseLabel;
  final title = document.title?.trim();
  final name = title != null && title.isNotEmpty
      ? title
      : document.authoredId ?? _compactRunPath(document.relativePath);
  return '$kind · $name';
}

String? _runFailureMessage(Object? failure) {
  if (failure is! Map<Object?, Object?>) return null;
  final primary = failure['primary'];
  if (primary is! Map<Object?, Object?>) return null;
  final message = primary['message'];
  if (message is! String || message.trim().isEmpty) return null;
  return message.trim();
}

String? _runFailureCode(Object? failure) {
  if (failure is! Map<Object?, Object?>) return null;
  final primary = failure['primary'];
  if (primary is! Map<Object?, Object?>) return null;
  final code = primary['code'];
  return code is String && code.trim().isNotEmpty ? code.trim() : null;
}

String formatRunEventMessage({
  required String kind,
  String? entityKind,
  String? lifecycle,
  String? outcome,
}) {
  final subject = _humanizeRunToken(
    entityKind ?? kind.split('.').first,
    capitalize: true,
  );
  final state = _humanizeRunToken(outcome ?? lifecycle ?? kind.split('.').last);
  return state.isEmpty ? subject : '$subject $state';
}

String _humanizeRunToken(String value, {bool capitalize = false}) {
  final words = value
      .replaceAll('.', ' ')
      .replaceAll('_', ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .trim()
      .toLowerCase();
  if (!capitalize || words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Runs screen: submit case/suite runs, observe live event streams, cancel,
/// and download artifacts.
final class RunsScreen extends HookConsumerWidget {
  const RunsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(selectedWorkspaceIdProvider);
    final rawRunsState = ref.watch(runsProvider);
    final recentRunsAsync = workspaceId == null
        ? const AsyncValue<List<CockpitRunResource>>.data(
            <CockpitRunResource>[],
          )
        : ref.watch(recentRunsForWorkspaceProvider(workspaceId));
    final documentsAsync = workspaceId != null
        ? ref.watch(documentsForWorkspaceProvider(workspaceId))
        : const AsyncValue<List<CockpitDocumentResource>>.loading();
    final rawTargetsState = ref.watch(targetsProvider);

    final selectedDocId = useState<String?>(null);
    final selectedCaseId = useState<String?>(null);
    final idempotencyCtrl = useTextEditingController();
    final selectedTargetId = useState<String?>(null);
    final inputsCtrl = useTextEditingController();
    final timeoutCtrl = useTextEditingController();
    final streamSub = useRef<StreamSubscription<String>?>(null);
    final artifacts = useState<List<CockpitArtifactResource>>(const []);
    final runResource = useState<Map<String, Object?>?>(null);
    final canceling = useState(false);
    final downloadingId = useState<String?>(null);
    final runsState = rawRunsState.workspaceId == workspaceId
        ? rawRunsState
        : RunsState(workspaceId: workspaceId);
    final recentRuns = recentRunsAsync.value ?? const <CockpitRunResource>[];

    void refreshRecentRunsAfterTerminal() {
      final selectedWorkspaceId = workspaceId;
      if (selectedWorkspaceId == null) return;
      final provider = recentRunsForWorkspaceProvider(selectedWorkspaceId);
      if (!ref.read(provider).isLoading) ref.invalidate(provider);
    }

    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        final previous = streamSub.value;
        streamSub.value = null;
        if (previous != null) unawaited(previous.cancel());
        artifacts.value = const [];
        runResource.value = null;
        selectedDocId.value = null;
        selectedCaseId.value = null;
        selectedTargetId.value = null;
        final nextWorkspaceId = workspaceId;
        if (nextWorkspaceId != null) {
          ref.read(runsProvider.notifier).activateWorkspace(nextWorkspaceId);
          unawaited(
            ref.read(targetsProvider.notifier).refresh(nextWorkspaceId),
          );
        }
      });
      return () {
        canceled = true;
        final active = streamSub.value;
        streamSub.value = null;
        if (active != null) unawaited(active.cancel());
      };
    }, [workspaceId]);

    // The test itself may navigate away from this screen. Restore the durable
    // run when the operator returns instead of leaving a stale "0 events"
    // view or asking them to resubmit the test.
    useEffect(() {
      var canceled = false;
      final runId = runsState.currentRunId;
      if (workspaceId == null || runId == null) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (canceled || !context.mounted) return;
        final notifier = ref.read(runsProvider.notifier);
        Map<String, Object?>? resource;
        try {
          resource = await notifier.getRun(runId);
          if (canceled || !context.mounted || !notifier.isCurrentRun(runId)) {
            return;
          }
          runResource.value = resource;
          if (resource['lifecycle'] == 'completed') {
            artifacts.value = await notifier.artifacts(runId);
          }
        } on Object catch (error) {
          if (!canceled && context.mounted && notifier.isCurrentRun(runId)) {
            notifier.addEvent(
              runId,
              RunEvent(
                kind: 'error',
                message: context.t.runs.restoreFailed(error: error.toString()),
                timestamp: DateTime.now(),
              ),
            );
          }
        }
        if (canceled || !context.mounted || !notifier.isCurrentRun(runId)) {
          return;
        }
        final hasTerminalEvent = ref
            .read(runsProvider)
            .events
            .any((event) => event.kind == 'terminal');
        if (resource?['lifecycle'] == 'completed' && hasTerminalEvent) return;
        await _observeStream(
          context,
          ref,
          runId,
          streamSub,
          runResource,
          refreshRecentRunsAfterTerminal,
        );
      });
      return () {
        canceled = true;
        final active = streamSub.value;
        streamSub.value = null;
        if (active != null) unawaited(active.cancel());
      };
    }, [workspaceId, runsState.currentRunId]);

    // Auto-generate an idempotency key once.
    useEffect(() {
      if (idempotencyCtrl.text.isEmpty) {
        idempotencyCtrl.text = _newIdempotencyKey('run');
      }
      return null;
    }, []);

    final documents =
        (documentsAsync.value ?? const <CockpitDocumentResource>[])
            .where(
              (document) =>
                  document.kind == CockpitIndexedDocumentKind.testCase ||
                  document.kind == CockpitIndexedDocumentKind.suite,
            )
            .toList(growable: false);
    final documentsLoading = documentsAsync.isLoading && documents.isEmpty;
    final documentsError = documentsAsync.hasError
        ? documentsAsync.error.toString()
        : null;
    final selectedDoc = documents
        .where((document) => document.documentId == selectedDocId.value)
        .firstOrNull;
    final availableCases =
        selectedDoc?.kind == CockpitIndexedDocumentKind.testCase
        ? selectedDoc!.cases
        : const <CockpitCaseIndexEntry>[];
    final targets = rawTargetsState.workspaceId == workspaceId
        ? rawTargetsState.items
        : const <CockpitAutomationTargetResource>[];

    Future<void> submitRun() async {
      var document = selectedDoc;
      final key = idempotencyCtrl.text.trim();
      if (workspaceId == null || document == null || key.isEmpty) return;
      if (document.kind == CockpitIndexedDocumentKind.testCase &&
          selectedCaseId.value == null) {
        return;
      }
      final selectedDocument = document;

      try {
        final freshDocuments = await ref.refresh(
          documentsForWorkspaceProvider(workspaceId).future,
        );
        if (!context.mounted ||
            ref.read(selectedWorkspaceIdProvider) != workspaceId) {
          return;
        }
        document = freshDocuments
            .where(
              (item) =>
                  item.kind == selectedDocument.kind &&
                  item.authoredId == selectedDocument.authoredId &&
                  item.relativePath == selectedDocument.relativePath,
            )
            .firstOrNull;
        if (document == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.runs.selectedFileChanged)),
          );
          selectedDocId.value = null;
          selectedCaseId.value = null;
          return;
        }
        selectedDocId.value = document.documentId;
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t.runs.refreshTestsFailed(error: error.toString()),
              ),
            ),
          );
        }
        return;
      }

      late final Map<String, Object?> inputs;
      late final int? timeoutMs;
      try {
        inputs = parseRunInputs(inputsCtrl.text, translations: context.t);
        timeoutMs = parseRunTimeout(
          timeoutCtrl.text,
          isSuite: document.kind == CockpitIndexedDocumentKind.suite,
          translations: context.t,
        );
      } on FormatException catch (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }

      await streamSub.value?.cancel();
      streamSub.value = null;
      runResource.value = null;
      artifacts.value = const [];

      final notifier = ref.read(runsProvider.notifier);
      final result = document.kind == CockpitIndexedDocumentKind.suite
          ? await notifier.submitSuite(
              workspaceId: workspaceId,
              documentId: document.documentId,
              suiteId: document.authoredId!,
              documentSha256: document.sha256,
              idempotencyKey: key,
              inputs: inputs,
              targetId: selectedTargetId.value,
              timeoutMs: timeoutMs,
            )
          : await notifier.submitCase(
              workspaceId: workspaceId,
              documentId: document.documentId,
              caseId: selectedCaseId.value!,
              documentSha256: document.sha256,
              idempotencyKey: key,
              inputs: inputs,
              targetId: selectedTargetId.value,
              timeoutMs: timeoutMs,
            );
      if (result == null ||
          !context.mounted ||
          ref.read(selectedWorkspaceIdProvider) != workspaceId) {
        return;
      }

      ref.invalidate(recentRunsForWorkspaceProvider(workspaceId));
      idempotencyCtrl.text = _newIdempotencyKey('run');
    }

    Future<void> cancelRun() async {
      final runId = runsState.currentRunId;
      if (runId == null) return;
      canceling.value = true;
      try {
        await ref
            .read(runsProvider.notifier)
            .cancel(runId: runId, idempotencyKey: 'cancel-$runId');
        final resource = await ref.read(runsProvider.notifier).getRun(runId);
        if (context.mounted &&
            ref.read(runsProvider.notifier).isCurrentRun(runId)) {
          runResource.value = resource;
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.runs.cancellationRequested)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t.runs.cancelFailed(error: error.toString()),
              ),
            ),
          );
        }
      } finally {
        canceling.value = false;
      }
    }

    Future<void> refreshRun() async {
      final runId = runsState.currentRunId;
      if (runId == null) return;
      try {
        final notifier = ref.read(runsProvider.notifier);
        final resource = await notifier.getRun(runId);
        if (!context.mounted || !notifier.isCurrentRun(runId)) return;
        final refreshedArtifacts = resource['lifecycle'] == 'completed'
            ? await notifier.artifacts(runId)
            : const <CockpitArtifactResource>[];
        if (!context.mounted || !notifier.isCurrentRun(runId)) return;
        runResource.value = resource;
        artifacts.value = refreshedArtifacts;
        ref.invalidate(recentRunsForWorkspaceProvider(workspaceId!));
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t.runs.refreshFailed(error: e.toString())),
            ),
          );
        }
      }
    }

    Future<void> refreshRecentRuns() async {
      try {
        final refresh = ref.refresh(
          recentRunsForWorkspaceProvider(workspaceId!).future,
        );
        await refresh;
      } on Object {
        // The provider retains the precise error for the retry affordance.
      }
    }

    Future<void> selectRun(String selectedRunId) async {
      if (selectedRunId == runsState.currentRunId) return;
      final selectedWorkspaceId = workspaceId!;
      await streamSub.value?.cancel();
      if (!context.mounted ||
          ref.read(selectedWorkspaceIdProvider) != selectedWorkspaceId) {
        return;
      }
      streamSub.value = null;
      artifacts.value = const [];
      runResource.value = null;
      ref
          .read(runsProvider.notifier)
          .setCurrentRun(
            workspaceId: selectedWorkspaceId,
            runId: selectedRunId,
          );
    }

    Future<void> startNewRun() async {
      final selectedWorkspaceId = workspaceId!;
      await streamSub.value?.cancel();
      if (!context.mounted ||
          ref.read(selectedWorkspaceIdProvider) != selectedWorkspaceId) {
        return;
      }
      streamSub.value = null;
      artifacts.value = const [];
      runResource.value = null;
      ref
          .read(runsProvider.notifier)
          .setCurrentRun(workspaceId: selectedWorkspaceId, runId: null);
    }

    Future<void> retryDocuments() async {
      try {
        final refresh = ref.refresh(
          documentsForWorkspaceProvider(workspaceId!).future,
        );
        await refresh;
      } on Object {
        // The provider keeps the precise failure and the existing document
        // choices. The inline recovery state remains the single UI response.
      }
    }

    if (workspaceId == null) {
      return ScreenScaffold(
        title: context.t.runs.title,
        subtitle: context.t.runs.subtitle,
        body: EmptyStateView(
          icon: LucideIcons.mousePointerClick,
          title: context.t.runs.selectProject,
          description: context.t.runs.selectProjectDescription,
          action: FilledButton.icon(
            onPressed: () => ref
                .read(navProvider.notifier)
                .go(ConsoleNavDestination.workspaces),
            icon: const Icon(LucideIcons.folderOpen, size: 14),
            label: Text(context.t.runs.chooseProject),
          ),
        ),
      );
    }

    final submissionBar = _SubmissionBar(
      documents: documents,
      selectedDocId: selectedDocId,
      availableCases: availableCases,
      selectedCaseId: selectedCaseId,
      selectedDocument: selectedDoc,
      targets: targets,
      selectedTargetId: selectedTargetId,
      inputsCtrl: inputsCtrl,
      timeoutCtrl: timeoutCtrl,
      onSubmit: submitRun,
      onOpenTests: () =>
          ref.read(navProvider.notifier).go(ConsoleNavDestination.documents),
      documentsLoading: documentsLoading,
      documentsError: documentsError,
      onRetryDocuments: retryDocuments,
      submitting: runsState.submitting,
      error: runsState.error,
    );
    final runId = runsState.currentRunId;

    _RunDetail runDetail() => _RunDetail(
      runId: runId!,
      events: runsState.events,
      runResource: runResource.value,
      artifacts: artifacts.value,
      canceling: canceling.value,
      downloadingId: downloadingId.value,
      onCancel: cancelRun,
      onNewRun: startNewRun,
      recentRuns: recentRuns,
      recentRunsLoading: recentRunsAsync.isLoading,
      recentRunsError: recentRunsAsync.hasError,
      onSelectRun: selectRun,
      onRefresh: refreshRun,
      onDownload: (artifact) => _downloadArtifact(
        context: context,
        ref: ref,
        artifact: artifact,
        downloadingId: downloadingId,
      ),
    );

    return ScreenScaffold(
      title: context.t.runs.title,
      subtitle: context.t.runs.subtitle,
      actions: runId == null
          ? <Widget>[
              if (recentRuns.isNotEmpty)
                _RecentRunMenu(runs: recentRuns, onSelected: selectRun),
              IconButton(
                onPressed: recentRunsAsync.isLoading ? null : refreshRecentRuns,
                icon: recentRunsAsync.isLoading
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 15),
                tooltip: recentRunsAsync.hasError
                    ? context.t.runs.retryRecent
                    : context.t.runs.refreshRecent,
              ),
            ]
          : null,
      body: runId == null
          ? SingleChildScrollView(child: submissionBar)
          : runDetail(),
    );
  }

  Future<void> _downloadArtifact({
    required BuildContext context,
    required WidgetRef ref,
    required CockpitArtifactResource artifact,
    required ValueNotifier<String?> downloadingId,
  }) async {
    final destination = await FilePicker.saveFile(
      dialogTitle: context.t.runs.saveArtifact,
      fileName: artifact.relativePath.split('/').last,
    );
    if (destination == null) return;
    downloadingId.value = artifact.artifactId;
    try {
      await ref
          .read(runsProvider.notifier)
          .downloadArtifact(artifact: artifact, destination: File(destination));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.runs.artifactSaved(path: destination)),
          ),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.runs.downloadFailed(error: e.toString())),
          ),
        );
      }
    } finally {
      downloadingId.value = null;
    }
  }

  Future<void> _observeStream(
    BuildContext context,
    WidgetRef ref,
    String runId,
    ObjectRef<StreamSubscription<String>?> subRef,
    ValueNotifier<Map<String, Object?>?> runResource,
    VoidCallback onTerminal,
  ) async {
    await subRef.value?.cancel();
    if (!context.mounted) return;

    final notifier = ref.read(runsProvider.notifier);
    bool isActive() => context.mounted && notifier.isCurrentRun(runId);

    void record(RunEvent event) => notifier.addEvent(runId, event);

    Future<void> refreshRunResource() async {
      final resource = await notifier.getRun(runId);
      if (isActive()) runResource.value = resource;
    }

    late final Stream<String> stream;
    try {
      var afterSequence = 0;
      for (final event in ref.read(runsProvider).events) {
        final sequence = event.sequence;
        if (sequence != null && sequence > afterSequence) {
          afterSequence = sequence;
        }
      }
      stream = notifier.observeEvents(runId, afterSequence: afterSequence);
    } on Object catch (error) {
      record(
        RunEvent(
          kind: 'error',
          message: context.t.runs.observeFailed(error: error.toString()),
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    var terminalSeen = false;
    var disconnectedSeen = false;
    subRef.value = stream.listen(
      (data) async {
        if (!isActive()) return;
        try {
          final json = jsonDecode(data);
          if (json is! Map<String, Object?>) {
            throw FormatException(context.t.runs.jsonEventError);
          }
          final kind = json['kind'] as String? ?? 'event';
          if (kind == 'terminal' || kind == 'gap' || kind == 'disconnected') {
            terminalSeen = terminalSeen || kind == 'terminal';
            disconnectedSeen = disconnectedSeen || kind == 'disconnected';
            record(
              RunEvent(
                kind: kind,
                message: kind == 'terminal'
                    ? context.t.runs.completed
                    : context.t.runs.streamEvent(kind: kind),
                timestamp: DateTime.now(),
              ),
            );
            return;
          }

          final sequence = json['sequence'] as int?;
          final entityKind = json['entityKind'] as String?;
          final lifecycle = json['lifecycle'] as String?;
          final outcome = json['outcome'] as String?;
          final failureMessage = _runFailureMessage(json['failure']);
          final message = failureMessage == null
              ? formatRunEventMessage(
                  kind: kind,
                  entityKind: entityKind,
                  lifecycle: lifecycle,
                  outcome: outcome,
                )
              : '${formatRunEventMessage(kind: kind, entityKind: entityKind, lifecycle: lifecycle, outcome: outcome)}: $failureMessage';
          record(
            RunEvent(
              kind: kind,
              message: message,
              timestamp: DateTime.now(),
              sequence: sequence,
            ),
          );
        } on Object catch (error) {
          record(
            RunEvent(
              kind: 'error',
              message: context.t.runs.malformedEvent(error: error.toString()),
              timestamp: DateTime.now(),
            ),
          );
        }
      },
      onDone: () async {
        if (!isActive()) return;
        try {
          await refreshRunResource();
          if (isActive()) onTerminal();
        } on Object catch (error) {
          record(
            RunEvent(
              kind: 'error',
              message: context.t.runs.statusLoadFailed(error: error.toString()),
              timestamp: DateTime.now(),
            ),
          );
        }
        if (!terminalSeen && !disconnectedSeen) {
          record(
            RunEvent(
              kind: 'disconnected',
              message: context.t.runs.streamEnded,
              timestamp: DateTime.now(),
            ),
          );
        }
      },
      onError: (Object error) {
        record(
          RunEvent(kind: 'error', message: '$error', timestamp: DateTime.now()),
        );
      },
    );
  }
}

final class _SubmissionBar extends StatelessWidget {
  const _SubmissionBar({
    required this.documents,
    required this.selectedDocId,
    required this.availableCases,
    required this.selectedCaseId,
    required this.selectedDocument,
    required this.targets,
    required this.selectedTargetId,
    required this.inputsCtrl,
    required this.timeoutCtrl,
    required this.onSubmit,
    required this.onOpenTests,
    required this.documentsLoading,
    required this.documentsError,
    required this.onRetryDocuments,
    required this.submitting,
    required this.error,
  });

  final List<CockpitDocumentResource> documents;
  final ValueNotifier<String?> selectedDocId;
  final List<CockpitCaseIndexEntry> availableCases;
  final ValueNotifier<String?> selectedCaseId;
  final CockpitDocumentResource? selectedDocument;
  final List<CockpitAutomationTargetResource> targets;
  final ValueNotifier<String?> selectedTargetId;
  final TextEditingController inputsCtrl;
  final TextEditingController timeoutCtrl;
  final Future<void> Function() onSubmit;
  final VoidCallback onOpenTests;
  final bool documentsLoading;
  final String? documentsError;
  final Future<void> Function() onRetryDocuments;
  final bool submitting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCase =
        availableCases.any((entry) => entry.caseId == selectedCaseId.value)
        ? selectedCaseId.value
        : null;
    final selectedTarget =
        targets.any((target) => target.targetId == selectedTargetId.value)
        ? selectedTargetId.value
        : null;
    final isSuite = selectedDocument?.kind == CockpitIndexedDocumentKind.suite;
    final canSubmit =
        selectedDocument != null &&
        (isSuite || selectedCase != null) &&
        !submitting;
    final guidance = documentsLoading
        ? context.t.runs.loadingTests
        : documentsError != null && documents.isEmpty
        ? context.t.runs.testsUnavailable
        : documents.isEmpty
        ? context.t.runs.createTestFirst
        : selectedDocument == null
        ? context.t.runs.selectFile
        : !isSuite && selectedCase == null
        ? context.t.runs.selectCase
        : context.t.runs.ready;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                context.t.runs.startTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                context.t.runs.startDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final columns = constraints.maxWidth >= 840
                      ? 3
                      : constraints.maxWidth >= 680
                      ? 2
                      : 1;
                  final itemWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: ConsoleDropdownField<String>(
                          initialValue: selectedDocument?.documentId,
                          label: context.t.runs.testFileStep,
                          hint: Text(context.t.runs.chooseTestFile),
                          items: [
                            for (final document in documents)
                              DropdownMenuItem(
                                value: document.documentId,
                                child: Tooltip(
                                  message: document.relativePath,
                                  child: Text(
                                    _runDocumentLabel(context.t, document),
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: submitting || documents.isEmpty
                              ? null
                              : (value) {
                                  selectedDocId.value = value;
                                  final document = documents
                                      .where((item) => item.documentId == value)
                                      .firstOrNull;
                                  selectedCaseId.value =
                                      document?.kind ==
                                              CockpitIndexedDocumentKind
                                                  .testCase &&
                                          document!.cases.length == 1
                                      ? document.cases.single.caseId
                                      : null;
                                },
                        ),
                      ),
                      if (!isSuite)
                        SizedBox(
                          key: ValueKey(selectedDocument?.documentId),
                          width: itemWidth,
                          child: ConsoleDropdownField<String>(
                            initialValue: selectedCase,
                            label: context.t.runs.testCaseStep,
                            hint: Text(context.t.runs.chooseTestCase),
                            items: [
                              for (final entry in availableCases)
                                DropdownMenuItem(
                                  value: entry.caseId,
                                  child: Text(
                                    entry.caseId,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: submitting || selectedDocument == null
                                ? null
                                : (value) => selectedCaseId.value = value,
                          ),
                        ),
                      if (isSuite)
                        SizedBox(
                          width: itemWidth,
                          child: ConsoleFieldValue(
                            label: context.t.runs.suiteContentsStep,
                            child: Text(
                              context.t.runs.allSuiteCases,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: itemWidth,
                        child: ConsoleDropdownField<String>(
                          initialValue: selectedTarget ?? '',
                          label: context.t.runs.targetStep,
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(context.t.runs.useFileDefault),
                            ),
                            for (final target in targets)
                              DropdownMenuItem(
                                value: target.targetId,
                                child: Text(
                                  _runTargetLabel(target),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: submitting
                              ? null
                              : (value) => selectedTargetId.value =
                                    value == null || value.isEmpty
                                    ? null
                                    : value,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final message = Row(
                    children: [
                      Icon(
                        canSubmit ? LucideIcons.checkCircle2 : LucideIcons.info,
                        size: 14,
                        color: canSubmit
                            ? context.consoleColors.success
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          guidance,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (documentsLoading ||
                      documentsError != null ||
                      documents.isEmpty) {
                    final action = documentsLoading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : documentsError != null
                        ? TextButton.icon(
                            onPressed: () => unawaited(onRetryDocuments()),
                            icon: const Icon(LucideIcons.refreshCw, size: 14),
                            label: Text(context.t.runs.retryTests),
                          )
                        : TextButton.icon(
                            onPressed: onOpenTests,
                            icon: const Icon(LucideIcons.filePlus2, size: 14),
                            label: Text(context.t.runs.openTests),
                          );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [message, const SizedBox(height: 8), action],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: message),
                        action,
                      ],
                    );
                  }
                  return message;
                },
              ),
            ),
            if (documentsError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _InlineRunNotice(
                  icon: LucideIcons.triangleAlert,
                  message: documents.isEmpty
                      ? context.t.runs.indexLoadFailed
                      : context.t.runs.indexRefreshFailed,
                  color: context.consoleColors.warning,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: constraints.maxWidth < 520 ? double.infinity : 160,
                      child: FilledButton.icon(
                        onPressed: canSubmit ? onSubmit : null,
                        icon: submitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.play, size: 14),
                        label: Text(
                          isSuite
                              ? context.t.runs.runSuite
                              : context.t.runs.runTest,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ExpansionTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minTileHeight: ConsoleControlStyle.height,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                title: Text(
                  context.t.runs.options,
                  style: theme.textTheme.labelLarge,
                ),
                children: [
                  ConsoleTextArea(
                    controller: inputsCtrl,
                    enabled: !submitting,
                    minLines: 2,
                    maxLines: 4,
                    label: context.t.runs.inputsOptional,
                    hint: context.t.runs.inputsHint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConsoleTextField(
                    controller: timeoutCtrl,
                    enabled: !submitting,
                    label: context.t.runs.timeoutOptional,
                    hint: context.t.runs.timeoutHint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.alertCircle,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _InlineRunNotice extends StatelessWidget {
  const _InlineRunNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.32),
        radius: ConsoleShapes.smallRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _RunDetail extends HookWidget {
  const _RunDetail({
    required this.runId,
    required this.events,
    required this.runResource,
    required this.artifacts,
    required this.canceling,
    required this.downloadingId,
    required this.onCancel,
    required this.onNewRun,
    required this.recentRuns,
    required this.recentRunsLoading,
    required this.recentRunsError,
    required this.onSelectRun,
    required this.onRefresh,
    required this.onDownload,
  });

  final String runId;
  final List<RunEvent> events;
  final Map<String, Object?>? runResource;
  final List<CockpitArtifactResource> artifacts;
  final bool canceling;
  final String? downloadingId;
  final Future<void> Function() onCancel;
  final Future<void> Function() onNewRun;
  final List<CockpitRunResource> recentRuns;
  final bool recentRunsLoading;
  final bool recentRunsError;
  final Future<void> Function(String runId) onSelectRun;
  final Future<void> Function() onRefresh;
  final Future<void> Function(CockpitArtifactResource) onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scrollCtrl = useScrollController();
    final loading = runResource == null;
    final terminal = runResource?['lifecycle'] == 'completed';
    final failure = runResource?['failure'];
    final failureMessage = _runFailureMessage(failure);
    final failureCode = _runFailureCode(failure);

    useEffect(() {
      if (scrollCtrl.hasClients) {
        scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
      }
      return null;
    }, [events.length]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RecentRunMenu(
                runs: recentRuns,
                currentRunId: runId,
                onSelected: onSelectRun,
              ),
              if (recentRunsLoading)
                const SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (recentRunsError)
                Tooltip(
                  message: context.t.runs.recentUnavailable,
                  child: Icon(
                    LucideIcons.triangleAlert,
                    size: 13,
                    color: context.consoleColors.warning,
                  ),
                ),
              if (loading) ...[
                const SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text(
                  context.t.runs.loadingRun,
                  style: theme.textTheme.labelSmall,
                ),
              ],
              if (runResource != null) ...[
                _LifecycleChip(
                  lifecycle: runResource!['lifecycle'] as String? ?? 'unknown',
                  outcome: runResource!['outcome'] as String?,
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: ConsoleShapes.decoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  radius: 6,
                ),
                child: Text(
                  context.t.runs.events(n: events.length),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(LucideIcons.refreshCw, size: 12),
                label: Text(context.t.common.refresh),
              ),
              if (!loading && terminal)
                TextButton.icon(
                  onPressed: onNewRun,
                  icon: const Icon(LucideIcons.plus, size: 12),
                  label: Text(context.t.runs.newRun),
                ),
              if (!loading && !terminal)
                TextButton.icon(
                  onPressed: canceling ? null : onCancel,
                  icon: canceling
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.x, size: 12),
                  label: Text(context.t.runs.cancelRun),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        if (failureMessage != null)
          _RunFailureBanner(message: failureMessage, code: failureCode),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final eventList = Container(
                color: theme.colorScheme.surfaceContainerLowest,
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: events.length,
                  itemBuilder: (context, index) =>
                      _EventRow(event: events[index]),
                ),
              );
              final artifactList = _ArtifactList(
                artifacts: artifacts,
                downloadingId: downloadingId,
                onDownload: onDownload,
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [
                    Expanded(flex: 3, child: eventList),
                    if (artifacts.isNotEmpty) ...[
                      Container(height: 1, color: theme.dividerColor),
                      Expanded(flex: 2, child: artifactList),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: eventList),
                  if (artifacts.isNotEmpty) ...[
                    Container(width: 1, color: theme.dividerColor),
                    SizedBox(width: 280, child: artifactList),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _RecentRunMenu extends StatelessWidget {
  const _RecentRunMenu({
    required this.runs,
    required this.onSelected,
    this.currentRunId,
  });

  final List<CockpitRunResource> runs;
  final String? currentRunId;
  final Future<void> Function(String runId) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      menuChildren: [
        for (final run in runs)
          MenuItemButton(
            onPressed: () => unawaited(onSelected(run.runId)),
            child: SizedBox(
              width: 280,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _runStateColor(context, run),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          run.documentId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          '${run.runId} · ${_runTime(run.submittedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _runStateLabel(context.t, run),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _runStateColor(context, run),
                    ),
                  ),
                  if (run.runId == currentRunId) ...[
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.check,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: runs.isEmpty
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(LucideIcons.history, size: 13),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            currentRunId ?? context.t.runs.recentRuns,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: currentRunId == null ? null : 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

String _runStateLabel(Translations t, CockpitRunResource run) {
  final outcome = run.outcome;
  if (outcome != null) {
    return switch (outcome) {
      CockpitRunOutcome.passed => t.runs.state.passed,
      CockpitRunOutcome.failed => t.runs.state.failed,
      CockpitRunOutcome.blocked => t.runs.state.blocked,
      CockpitRunOutcome.skipped => t.runs.state.skipped,
      CockpitRunOutcome.cancelled => t.runs.state.cancelled,
      CockpitRunOutcome.interrupted => t.runs.state.interrupted,
      CockpitRunOutcome.internalError => t.runs.state.internalError,
    };
  }
  return switch (run.lifecycle) {
    CockpitRunLifecycle.queued => t.runs.state.queued,
    CockpitRunLifecycle.running => t.runs.state.running,
    CockpitRunLifecycle.finalizing => t.runs.state.finalizing,
    CockpitRunLifecycle.completed => t.runs.state.completed,
  };
}

String _localizedRunState(Translations t, String value) => switch (value) {
  'queued' => t.runs.state.queued,
  'running' => t.runs.state.running,
  'finalizing' => t.runs.state.finalizing,
  'completed' => t.runs.state.completed,
  'passed' => t.runs.state.passed,
  'failed' => t.runs.state.failed,
  'blocked' => t.runs.state.blocked,
  'skipped' => t.runs.state.skipped,
  'cancelled' => t.runs.state.cancelled,
  'interrupted' => t.runs.state.interrupted,
  'internalError' => t.runs.state.internalError,
  _ => _humanizeRunToken(value, capitalize: true),
};

Color _runStateColor(BuildContext context, CockpitRunResource run) {
  final theme = Theme.of(context);
  return switch (run.outcome) {
    CockpitRunOutcome.passed => context.consoleColors.success,
    CockpitRunOutcome.failed => theme.colorScheme.error,
    CockpitRunOutcome.blocked => context.consoleColors.warning,
    CockpitRunOutcome.cancelled ||
    CockpitRunOutcome.interrupted ||
    CockpitRunOutcome.internalError => theme.colorScheme.onSurfaceVariant,
    null => theme.colorScheme.primary,
    _ => theme.colorScheme.onSurfaceVariant,
  };
}

String _runTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

final class _RunFailureBanner extends StatelessWidget {
  const _RunFailureBanner({required this.message, this.code});

  final String message;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.alertCircle,
            size: 15,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.runs.failureTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (code != null) ...[
            const SizedBox(width: 12),
            Text(
              code!,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _LifecycleChip extends StatelessWidget {
  const _LifecycleChip({required this.lifecycle, required this.outcome});

  final String lifecycle;
  final String? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (outcome) {
      'passed' => context.consoleColors.success,
      'failed' => theme.colorScheme.error,
      'blocked' => context.consoleColors.warning,
      'cancelled' || 'interrupted' => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final label = _localizedRunState(context.t, outcome ?? lifecycle);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.12),
        radius: 6,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

final class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RunEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _eventColor(event.kind, context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.sequence != null)
            SizedBox(
              width: 32,
              child: Text(
                '${event.sequence}',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: context.consoleColors.inkTertiary,
                ),
              ),
            ),
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              event.message,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: event.kind == 'error'
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${event.timestamp.hour.toString().padLeft(2, '0')}:'
            '${event.timestamp.minute.toString().padLeft(2, '0')}:'
            '${event.timestamp.second.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: context.consoleColors.inkTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Color _eventColor(String type, BuildContext context) {
    final theme = Theme.of(context);
    return switch (type) {
      'error' => theme.colorScheme.error,
      'terminal' => context.consoleColors.success,
      'gap' || 'disconnected' => context.consoleColors.warning,
      _ => theme.colorScheme.primary,
    };
  }
}

final class _ArtifactList extends StatelessWidget {
  const _ArtifactList({
    required this.artifacts,
    required this.downloadingId,
    required this.onDownload,
  });

  final List<CockpitArtifactResource> artifacts;
  final String? downloadingId;
  final Future<void> Function(CockpitArtifactResource) onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Text(
            context.t.runs.filesEvidence(count: artifacts.length),
            style: theme.textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: artifacts.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: theme.dividerColor),
            itemBuilder: (context, index) {
              final artifact = artifacts[index];
              return _ArtifactTile(
                artifact: artifact,
                downloading: downloadingId == artifact.artifactId,
                onDownload: () => onDownload(artifact),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({
    required this.artifact,
    required this.downloading,
    required this.onDownload,
  });

  final CockpitArtifactResource artifact;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(
          _iconFor(artifact.mediaType),
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          artifact.relativePath.split('/').last,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${(artifact.sizeBytes / 1024).toStringAsFixed(1)} KB',
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: SizedBox(
          width: 30,
          height: 30,
          child: downloading
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  onPressed: onDownload,
                  icon: const Icon(LucideIcons.download, size: 13),
                  tooltip: context.t.runs.saveFile,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
        ),
      ),
    );
  }

  IconData _iconFor(String mediaType) {
    return switch (mediaType) {
      'image/png' || 'image/jpeg' || 'image/webp' => LucideIcons.image,
      'video/mp4' => LucideIcons.video,
      'application/json' => LucideIcons.fileJson,
      'text/html' => LucideIcons.fileCode,
      _ => LucideIcons.file,
    };
  }
}
