import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
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

Map<String, Object?> parseRunInputs(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return const <String, Object?>{};
  final decoded = decodeCockpitStructuredInput(trimmed);
  if (decoded is! Map<Object?, Object?> ||
      decoded.keys.any((key) => key is! String)) {
    throw const FormatException(
      'Run inputs must be a LON, JSON, or YAML object.',
    );
  }
  return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(decoded));
}

int? parseRunTimeout(String source, {required bool isSuite}) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(
    r'^(\d+)(ms|s|m|h)?$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) {
    throw const FormatException('Use a duration such as 30s, 5m, or 1h.');
  }
  final value = int.parse(match.group(1)!);
  final multiplier = switch (match.group(2)?.toLowerCase()) {
    null || 'ms' => 1,
    's' => 1000,
    'm' => 60000,
    'h' => 3600000,
    _ => throw const FormatException('Unsupported timeout unit.'),
  };
  final timeoutMs = value * multiplier;
  final maximum = isSuite ? 86400000 : 21600000;
  if (timeoutMs < 1 || timeoutMs > maximum) {
    throw FormatException(
      'Timeout must be between 1ms and ${isSuite ? '24h' : '6h'}.',
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

String _runDocumentLabel(CockpitDocumentResource document) {
  final parts = document.relativePath
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  final path = parts.length <= 4
      ? parts.join('/')
      : '${parts.first}/…/${parts.sublist(parts.length - 3).join('/')}';
  final kind = document.kind == CockpitIndexedDocumentKind.suite
      ? 'Suite'
      : 'Case';
  return '$kind · $path';
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
                message: 'Failed to restore run status: $error',
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
        await _observeStream(context, ref, runId, streamSub, runResource);
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

    final documents = documentsAsync.maybeWhen(
      data: (items) => items
          .where(
            (document) =>
                document.kind == CockpitIndexedDocumentKind.testCase ||
                document.kind == CockpitIndexedDocumentKind.suite,
          )
          .toList(growable: false),
      orElse: () => const <CockpitDocumentResource>[],
    );
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
      final document = selectedDoc;
      final key = idempotencyCtrl.text.trim();
      if (workspaceId == null || document == null || key.isEmpty) return;
      if (document.kind == CockpitIndexedDocumentKind.testCase &&
          selectedCaseId.value == null) {
        return;
      }

      late final Map<String, Object?> inputs;
      late final int? timeoutMs;
      try {
        inputs = parseRunInputs(inputsCtrl.text);
        timeoutMs = parseRunTimeout(
          timeoutCtrl.text,
          isSuite: document.kind == CockpitIndexedDocumentKind.suite,
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
            const SnackBar(content: Text('Cancellation requested')),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Cancel failed: $error')));
        }
      } finally {
        canceling.value = false;
      }
    }

    Future<void> loadArtifacts() async {
      final runId = runsState.currentRunId;
      if (runId == null) return;
      try {
        artifacts.value = await ref
            .read(runsProvider.notifier)
            .artifacts(runId);
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load artifacts: $e')),
          );
        }
      }
    }

    Future<void> startNewRun() async {
      await streamSub.value?.cancel();
      streamSub.value = null;
      artifacts.value = const [];
      runResource.value = null;
      ref
          .read(runsProvider.notifier)
          .setCurrentRun(workspaceId: workspaceId!, runId: null);
    }

    if (workspaceId == null) {
      return const ScreenScaffold(
        title: 'Test runs',
        subtitle: 'Run a test case or suite and follow its result',
        body: EmptyStateView(
          icon: LucideIcons.mousePointerClick,
          title: 'Select a project',
          description:
              'Choose a project from the Projects page to start a test run.',
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
      submitting: runsState.submitting,
      error: runsState.error,
    );
    final runId = runsState.currentRunId;

    _RunDetail runDetail({int flex = 1}) => _RunDetail(
      flex: flex,
      runId: runId!,
      events: runsState.events,
      runResource: runResource.value,
      artifacts: artifacts.value,
      canceling: canceling.value,
      downloadingId: downloadingId.value,
      onCancel: cancelRun,
      onNewRun: startNewRun,
      onRefreshArtifacts: loadArtifacts,
      onDownload: (artifact) => _downloadArtifact(
        context: context,
        ref: ref,
        artifact: artifact,
        downloadingId: downloadingId,
      ),
    );

    return ScreenScaffold(
      title: 'Test runs',
      subtitle: 'Run a test case or suite and follow its result',
      body: runId == null
          ? SingleChildScrollView(child: submissionBar)
          : Column(
              children: [
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(child: submissionBar),
                ),
                Container(height: 1, color: Theme.of(context).dividerColor),
                runDetail(flex: 3),
              ],
            ),
    );
  }

  Future<void> _downloadArtifact({
    required BuildContext context,
    required WidgetRef ref,
    required CockpitArtifactResource artifact,
    required ValueNotifier<String?> downloadingId,
  }) async {
    final destination = await FilePicker.saveFile(
      dialogTitle: 'Save artifact',
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
          SnackBar(content: Text('Saved verified artifact to $destination')),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
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
          message: 'Failed to observe run: $error',
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
            throw const FormatException('Expected a JSON object event.');
          }
          final kind = json['kind'] as String? ?? 'event';
          if (kind == 'terminal' || kind == 'gap' || kind == 'disconnected') {
            terminalSeen = terminalSeen || kind == 'terminal';
            disconnectedSeen = disconnectedSeen || kind == 'disconnected';
            record(
              RunEvent(
                kind: kind,
                message: kind == 'terminal' ? 'Run completed' : 'Stream $kind',
                timestamp: DateTime.now(),
              ),
            );
            if (kind == 'terminal') {
              try {
                await refreshRunResource();
              } on Object catch (error) {
                record(
                  RunEvent(
                    kind: 'error',
                    message: 'Failed to load run status: $error',
                    timestamp: DateTime.now(),
                  ),
                );
              }
            }
            return;
          }

          final sequence = json['sequence'] as int?;
          final entityKind = json['entityKind'] as String?;
          final lifecycle = json['lifecycle'] as String?;
          final outcome = json['outcome'] as String?;
          final message = formatRunEventMessage(
            kind: kind,
            entityKind: entityKind,
            lifecycle: lifecycle,
            outcome: outcome,
          );
          record(
            RunEvent(
              kind: kind,
              message: message,
              timestamp: DateTime.now(),
              sequence: sequence,
            ),
          );
          if (outcome != null) {
            try {
              await refreshRunResource();
            } on Object {
              // Status refresh is best-effort; the event is already recorded.
            }
          }
        } on Object catch (error) {
          record(
            RunEvent(
              kind: 'error',
              message: 'Malformed event: $error',
              timestamp: DateTime.now(),
            ),
          );
        }
      },
      onDone: () async {
        if (!isActive()) return;
        try {
          await refreshRunResource();
        } on Object catch (error) {
          record(
            RunEvent(
              kind: 'error',
              message: 'Failed to load run status: $error',
              timestamp: DateTime.now(),
            ),
          );
        }
        if (!terminalSeen && !disconnectedSeen) {
          record(
            RunEvent(
              kind: 'disconnected',
              message: 'Event stream ended before terminal state',
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
    final guidance = documents.isEmpty
        ? 'Create a test file before starting a run.'
        : selectedDocument == null
        ? 'Select a test file to continue.'
        : !isSuite && selectedCase == null
        ? 'Select a test case to continue.'
        : 'Ready to run in the current project.';

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
                'Start a test run',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Select a test file and case, then choose where to run it.',
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
                          label: '1. Test file',
                          items: [
                            for (final document in documents)
                              DropdownMenuItem(
                                value: document.documentId,
                                child: Text(
                                  _runDocumentLabel(document),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
                            label: '2. Test case',
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
                            label: '2. Suite contents',
                            child: const Text(
                              'All cases in this suite',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: itemWidth,
                        child: ConsoleDropdownField<String>(
                          initialValue: selectedTarget ?? '',
                          label: '3. App or device',
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Use test file default'),
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
                  if (documents.isEmpty) {
                    final action = TextButton.icon(
                      onPressed: onOpenTests,
                      icon: const Icon(LucideIcons.filePlus2, size: 14),
                      label: const Text('Open tests'),
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
                        label: Text(isSuite ? 'Run suite' : 'Run test'),
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
                title: Text('Run options', style: theme.textTheme.labelLarge),
                children: [
                  ConsoleTextArea(
                    controller: inputsCtrl,
                    enabled: !submitting,
                    minLines: 2,
                    maxLines: 4,
                    label: 'Inputs (optional)',
                    hint: 'LON, JSON, or YAML object',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConsoleTextField(
                    controller: timeoutCtrl,
                    enabled: !submitting,
                    label: 'Timeout (optional)',
                    hint: 'Use default, e.g. 30s or 5m',
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

final class _RunDetail extends HookWidget {
  const _RunDetail({
    this.flex = 1,
    required this.runId,
    required this.events,
    required this.runResource,
    required this.artifacts,
    required this.canceling,
    required this.downloadingId,
    required this.onCancel,
    required this.onNewRun,
    required this.onRefreshArtifacts,
    required this.onDownload,
  });

  final int flex;
  final String runId;
  final List<RunEvent> events;
  final Map<String, Object?>? runResource;
  final List<CockpitArtifactResource> artifacts;
  final bool canceling;
  final String? downloadingId;
  final Future<void> Function() onCancel;
  final Future<void> Function() onNewRun;
  final Future<void> Function() onRefreshArtifacts;
  final Future<void> Function(CockpitArtifactResource) onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scrollCtrl = useScrollController();
    final terminal = runResource?['lifecycle'] == 'completed';

    useEffect(() {
      if (scrollCtrl.hasClients) {
        scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
      }
      return null;
    }, [events.length]);

    return Expanded(
      flex: flex,
      child: Column(
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
                Icon(
                  LucideIcons.radio,
                  size: 13,
                  color: theme.colorScheme.primary,
                ),
                Text(
                  runId,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (runResource != null) ...[
                  _LifecycleChip(
                    lifecycle:
                        runResource!['lifecycle'] as String? ?? 'unknown',
                    outcome: runResource!['outcome'] as String?,
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: ConsoleShapes.decoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    radius: 6,
                  ),
                  child: Text(
                    '${events.length} events',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onRefreshArtifacts,
                  icon: const Icon(LucideIcons.download, size: 12),
                  label: const Text('Refresh files'),
                ),
                if (terminal)
                  TextButton.icon(
                    onPressed: onNewRun,
                    icon: const Icon(LucideIcons.plus, size: 12),
                    label: const Text('New run'),
                  ),
                if (!terminal)
                  TextButton.icon(
                    onPressed: canceling ? null : onCancel,
                    icon: canceling
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.x, size: 12),
                    label: const Text('Cancel run'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
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
    final label = _humanizeRunToken(outcome ?? lifecycle, capitalize: true);
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
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
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
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
            'Files & evidence (${artifacts.length})',
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
                  tooltip: 'Save file',
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
