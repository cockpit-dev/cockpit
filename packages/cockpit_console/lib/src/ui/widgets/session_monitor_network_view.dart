import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_data_view.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_runtime_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final class SessionNetworkView extends HookConsumerWidget {
  const SessionNetworkView({
    required this.session,
    required this.detail,
    super.key,
  });

  final MonitoredSession session;
  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.t.sessions.network;
    final network = detail.network;
    if (network == null) {
      return SessionInlineEmpty(
        icon: LucideIcons.network,
        message: strings.open,
      );
    }
    final entries = objectList(network['entries']);
    final summary = mapValue(network['summary']);
    final totalEntries = summary?['totalEntryCount'] as int? ?? entries.length;
    final hasMore = entries.length < totalEntries;
    final loadingMore = detail.loading(SessionMonitorSection.network);
    final selectedId = useState<String?>(null);
    final validSelected = entries.any(
      (entry) => stringValue(entry['requestId']) == selectedId.value,
    );
    final effectiveSelectedId = validSelected
        ? selectedId.value
        : entries.isEmpty
        ? null
        : stringValue(entries.first['requestId']);
    final selected = entries.cast<Map<String, Object?>?>().firstWhere(
      (entry) => stringValue(entry?['requestId']) == effectiveSelectedId,
      orElse: () => null,
    );

    if (entries.isEmpty) {
      return _NetworkEmpty(network: network);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _NetworkSummary(network: network),
              const SizedBox(height: 12),
              ConsoleDropdownField<String>(
                initialValue: effectiveSelectedId,
                prefixIcon: const Icon(LucideIcons.network, size: 14),
                items: [
                  for (final entry in entries)
                    DropdownMenuItem<String>(
                      value: stringValue(entry['requestId']),
                      child: Text(
                        networkEntryLabel(context, entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => selectedId.value = value,
              ),
              if (hasMore) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: loadingMore
                      ? null
                      : () => ref
                            .read(sessionMonitorProvider.notifier)
                            .loadOlderNetwork(session.key),
                  icon: loadingMore
                      ? const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.chevronsDown, size: 14),
                  label: Text(
                    strings.loadOlder(
                      loaded: entries.length,
                      total: totalEntries,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (selected != null)
                _NetworkDetail(
                  session: session,
                  detail: detail,
                  entry: selected,
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: _NetworkSummary(network: network),
            ),
            Divider(height: 1, color: context.consoleColors.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 330,
                    child: _NetworkList(
                      entries: entries,
                      selectedId: effectiveSelectedId,
                      totalEntries: totalEntries,
                      loadingMore: loadingMore,
                      onLoadMore: hasMore
                          ? () => ref
                                .read(sessionMonitorProvider.notifier)
                                .loadOlderNetwork(session.key)
                          : null,
                      onSelect: (id) => selectedId.value = id,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: context.consoleColors.border,
                  ),
                  Expanded(
                    child: selected == null
                        ? SessionInlineEmpty(message: strings.selectRequest)
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _NetworkDetail(
                              session: session,
                              detail: detail,
                              entry: selected,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _NetworkSummary extends StatelessWidget {
  const _NetworkSummary({required this.network});

  final Map<String, Object?> network;

  @override
  Widget build(BuildContext context) {
    final summary = mapValue(network['summary']);
    final loadedCount = objectList(network['entries']).length;
    final strings = context.t.sessions.network;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: strings.total,
          value: scalarText(summary?['totalEntryCount']) ?? '0',
          color: context.consoleColors.info,
        ),
        _SummaryChip(
          label: strings.loaded,
          value: '$loadedCount',
          color: context.consoleColors.inkSecondary,
        ),
        _SummaryChip(
          label: strings.failures,
          value: scalarText(summary?['failureCount']) ?? '0',
          color: (summary?['failureCount'] as int? ?? 0) > 0
              ? context.consoleColors.errorColor
              : context.consoleColors.success,
        ),
        _SummaryChip(
          label: strings.inFlight,
          value: scalarText(summary?['inFlightCount']) ?? '0',
          color: context.consoleColors.warning,
        ),
        _SummaryChip(
          label: strings.source,
          value: stringValue(network['source']) ?? strings.unknownSource,
          color: context.consoleColors.inkSecondary,
        ),
      ],
    );
  }
}

final class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.2),
        radius: ConsoleShapes.smallRadius,
      ),
      child: Text(
        '$label $value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

final class _NetworkList extends StatelessWidget {
  const _NetworkList({
    required this.entries,
    required this.selectedId,
    required this.totalEntries,
    required this.loadingMore,
    required this.onSelect,
    this.onLoadMore,
  });

  final List<Map<String, Object?>> entries;
  final String? selectedId;
  final int totalEntries;
  final bool loadingMore;
  final ValueChanged<String> onSelect;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.network;
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: entries.length + (onLoadMore == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton.icon(
              onPressed: loadingMore ? null : onLoadMore,
              icon: loadingMore
                  ? const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.chevronsDown, size: 14),
              label: Text(
                strings.loadOlder(loaded: entries.length, total: totalEntries),
              ),
            ),
          );
        }
        final entry = entries[index];
        final id = stringValue(entry['requestId']) ?? '$index';
        return _NetworkRow(
          entry: entry,
          selected: selectedId == id,
          onTap: () => onSelect(id),
        );
      },
    );
  }
}

final class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final Map<String, Object?> entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    final status = entry['statusCode'];
    final state = stringValue(entry['state']) ?? 'complete';
    final failed =
        state == 'failed' ||
        (status is int && status >= 400) ||
        entry['error'] != null;
    final active = const {
      'sending',
      'waiting',
      'receiving',
      'open',
      'closing',
    }.contains(state);
    final statusColor = failed
        ? colors.errorColor
        : active
        ? colors.warning
        : colors.success;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: ConsoleShapes.decoration(
            color: selected ? colors.accentSubtle : Colors.transparent,
            radius: ConsoleShapes.smallRadius,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  stringValue(entry['method']) ??
                      stringValue(entry['protocol']) ??
                      'HTTP',
                  style: consoleMono(
                    size: 10,
                    weight: FontWeight.w600,
                    color: selected
                        ? colors.accentSubtleFg
                        : colors.inkSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      networkUriLabel(context, stringValue(entry['uri'])),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.accentSubtleFg
                            : colors.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$state · ${entry['durationMs'] ?? 0}ms',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                status?.toString() ?? (active ? '…' : '—'),
                style: consoleMono(size: 10, color: statusColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _NetworkDetail extends ConsumerWidget {
  const _NetworkDetail({
    required this.session,
    required this.detail,
    required this.entry,
  });

  final MonitoredSession session;
  final SessionMonitorDetail detail;
  final Map<String, Object?> entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.t.sessions.network;
    final requestId = stringValue(entry['requestId']) ?? '';
    final loadedBodies = detail.networkBodies.entries
        .where((item) => item.key.startsWith('$requestId:'))
        .toList(growable: false);
    final bodyErrors = detail.networkBodyErrors.entries
        .where((item) => item.key.startsWith('$requestId:'))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry['method'] ?? entry['protocol'] ?? 'HTTP'} ${entry['statusCode'] ?? entry['state'] ?? ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    stringValue(entry['uri']) ?? strings.unknownRequestUri,
                    style: consoleMono(
                      size: 11,
                      color: context.consoleColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_BodyExport>(
              tooltip: strings.exportTooltip,
              onSelected: (export) => _export(context, ref, requestId, export),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _BodyExport.safeResponse,
                  child: Text(strings.safeResponse),
                ),
                PopupMenuItem(
                  value: _BodyExport.safeRequest,
                  child: Text(strings.safeRequest),
                ),
                PopupMenuItem(
                  value: _BodyExport.safeBoth,
                  child: Text(strings.safeBoth),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _BodyExport.rawBoth,
                  child: Text(strings.rawBoth),
                ),
              ],
              icon: const Icon(LucideIcons.download, size: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SessionDataView(
          value: entry,
          emptyMessage: strings.metadataEmpty,
          copyLabel: strings.copyMetadata,
        ),
        for (final error in bodyErrors) ...[
          const SizedBox(height: 10),
          _BodyError(message: error.value),
        ],
        for (final body in loadedBodies) ...[
          const SizedBox(height: 10),
          SessionSectionCard(
            title: body.key.contains(':raw')
                ? strings.unmaskedFiles
                : strings.bodyFiles,
            subtitle: strings.bodyDescription,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SessionDataView(
                value: body.value,
                copyLabel: strings.copyPaths,
              ),
            ),
          ),
        ],
        if (detail.loadingNetworkBodies.any(
          (key) => key.startsWith('$requestId:'),
        )) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    _BodyExport export,
  ) async {
    if (requestId.isEmpty) return;
    if (export.raw) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t.sessions.network.confirmRawTitle),
          content: Text(context.t.sessions.network.confirmRawDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.sessions.network.exportUnmasked),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref
        .read(sessionMonitorProvider.notifier)
        .loadNetworkBody(
          session.key,
          requestId: requestId,
          body: export.body,
          raw: export.raw,
        );
  }
}

final class _NetworkEmpty extends StatelessWidget {
  const _NetworkEmpty({required this.network});

  final Map<String, Object?> network;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.network;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NetworkSummary(network: network),
        const SizedBox(height: 20),
        SessionInlineEmpty(icon: LucideIcons.network, message: strings.empty),
      ],
    );
  }
}

final class _BodyError extends StatelessWidget {
  const _BodyError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ConsoleShapes.decoration(
        color: colors.errorSubtle,
        borderColor: colors.errorColor.withValues(alpha: 0.25),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.errorFg),
      ),
    );
  }
}

enum _BodyExport {
  safeResponse('response', false),
  safeRequest('request', false),
  safeBoth('both', false),
  rawBoth('both', true);

  const _BodyExport(this.body, this.raw);

  final String body;
  final bool raw;
}

String networkEntryLabel(BuildContext context, Map<String, Object?> entry) =>
    '${entry['method'] ?? entry['protocol'] ?? 'HTTP'} · ${networkUriLabel(context, stringValue(entry['uri']))}';

String networkUriLabel(BuildContext context, String? value) {
  if (value == null || value.isEmpty) {
    return context.t.sessions.network.unknownUri;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.host.isEmpty ? path : '${uri.host}$path';
}
