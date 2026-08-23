import 'dart:convert';

import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/widgets/console_copy_button.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final class SessionDataView extends StatelessWidget {
  const SessionDataView({
    required this.value,
    this.title,
    this.emptyMessage,
    this.copyLabel,
    super.key,
  });

  final Object? value;
  final String? title;
  final String? emptyMessage;
  final String? copyLabel;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty(value)) {
      return SessionInlineEmpty(
        message: emptyMessage ?? context.t.sessions.data.empty,
      );
    }
    return Container(
      decoration: ConsoleShapes.decoration(
        color: context.consoleColors.surface1,
        borderColor: context.consoleColors.border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.braces,
                  size: 14,
                  color: context.consoleColors.inkSecondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title ?? context.t.sessions.data.structured,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                ConsoleCopyButton(
                  text: const JsonEncoder.withIndent('  ').convert(value),
                  copyLabel: copyLabel ?? context.t.sessions.data.copy,
                  copiedLabel: context.t.sessions.data.copied,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.consoleColors.border),
          _StructuredValue(value: value, depth: 0),
        ],
      ),
    );
  }
}

final class SessionInfoRow extends StatelessWidget {
  const SessionInfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyable,
    this.showWhenEmpty = false,
    super.key,
  });

  final String label;
  final String? value;
  final bool monospace;
  final bool? copyable;
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      if (!showWhenEmpty) return const SizedBox.shrink();
    }
    final displayValue = trimmedValue?.isNotEmpty == true
        ? trimmedValue!
        : context.t.sessions.data.notSet;
    final style = monospace
        ? consoleMono(color: context.consoleColors.inkPrimary)
        : Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.consoleColors.inkPrimary,
          );
    final allowsCopy = copyable ?? monospace;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(child: SelectableText(displayValue, style: style)),
          if (allowsCopy && value?.isNotEmpty == true)
            ConsoleCopyButton(
              text: value!,
              copyLabel: context.t.sessions.data.copyLabel(label: label),
              copiedLabel: context.t.sessions.data.labelCopied(label: label),
              iconSize: 13,
            ),
        ],
      ),
    );
  }
}

final class SessionInlineEmpty extends StatelessWidget {
  const SessionInlineEmpty({required this.message, this.icon, super.key});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? LucideIcons.inbox,
            size: 22,
            color: context.consoleColors.inkTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class SessionSectionCard extends StatefulWidget {
  const SessionSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.expandLabel,
    this.collapseLabel,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final bool collapsible;
  final bool initiallyExpanded;
  final String? expandLabel;
  final String? collapseLabel;

  @override
  State<SessionSectionCard> createState() => _SessionSectionCardState();
}

final class _SessionSectionCardState extends State<SessionSectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final shape = ConsoleShapes.border(
      side: BorderSide(color: context.consoleColors.border),
    );
    final toggleLabel = _expanded ? widget.collapseLabel : widget.expandLabel;
    return Material(
      color: context.consoleColors.surface1,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    customBorder: ConsoleShapes.border(
                      radius: ConsoleShapes.smallRadius,
                    ),
                    onTap: widget.collapsible ? _toggle : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ?widget.trailing,
                if (widget.collapsible)
                  IconButton(
                    tooltip: toggleLabel,
                    onPressed: _toggle,
                    icon: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(LucideIcons.chevronDown, size: 15),
                    ),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: context.consoleColors.border),
                      widget.child,
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

final class _StructuredValue extends StatelessWidget {
  const _StructuredValue({required this.value, required this.depth});

  final Object? value;
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final entries = (value! as Map).entries.toList(growable: false);
      return _StructuredEntries(
        entries: [
          for (final entry in entries)
            MapEntry(entry.key.toString(), entry.value),
        ],
        depth: depth,
      );
    }
    if (value is List) {
      return _StructuredEntries(
        entries: [
          for (var index = 0; index < (value! as List).length; index++)
            MapEntry('[$index]', (value! as List)[index]),
        ],
        depth: depth,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + depth * 12, 7, 12, 7),
      child: SelectableText(
        _displayScalar(value),
        style: consoleMono(
          color: value == null
              ? context.consoleColors.inkTertiary
              : context.consoleColors.inkPrimary,
        ),
      ),
    );
  }
}

final class _StructuredEntries extends StatefulWidget {
  const _StructuredEntries({required this.entries, required this.depth});

  final List<MapEntry<String, Object?>> entries;
  final int depth;

  @override
  State<_StructuredEntries> createState() => _StructuredEntriesState();
}

final class _StructuredEntriesState extends State<_StructuredEntries> {
  static const int _pageSize = 100;

  int _page = 0;

  @override
  void didUpdateWidget(covariant _StructuredEntries oldWidget) {
    super.didUpdateWidget(oldWidget);
    final boundaryChanged =
        _firstKey(oldWidget.entries) != _firstKey(widget.entries) ||
        _lastKey(oldWidget.entries) != _lastKey(widget.entries);
    if (oldWidget.entries.length != widget.entries.length || boundaryChanged) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = (widget.entries.length / _pageSize).ceil();
    final safePage = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final start = safePage * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.entries.length);
    final visible = widget.entries.sublist(start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0)
            Divider(
              height: 1,
              indent: 12 + widget.depth * 12,
              color: context.consoleColors.border.withValues(alpha: 0.65),
            ),
          _StructuredEntry(
            label: visible[index].key,
            value: visible[index].value,
            depth: widget.depth,
          ),
        ],
        if (pageCount > 1) ...[
          Divider(height: 1, color: context.consoleColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t.common.pageRange(
                      start: start + 1,
                      end: end,
                      total: widget.entries.length,
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  tooltip: context.t.common.previousPage,
                  onPressed: safePage == 0
                      ? null
                      : () => setState(() => _page = safePage - 1),
                  icon: const Icon(LucideIcons.chevronLeft, size: 14),
                ),
                IconButton(
                  tooltip: context.t.common.nextPage,
                  onPressed: safePage >= pageCount - 1
                      ? null
                      : () => setState(() => _page = safePage + 1),
                  icon: const Icon(LucideIcons.chevronRight, size: 14),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String? _firstKey(List<MapEntry<String, Object?>> entries) =>
      entries.isEmpty ? null : entries.first.key;

  String? _lastKey(List<MapEntry<String, Object?>> entries) =>
      entries.isEmpty ? null : entries.last.key;
}

final class _StructuredEntry extends StatelessWidget {
  const _StructuredEntry({
    required this.label,
    required this.value,
    required this.depth,
  });

  final String label;
  final Object? value;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final complex = value is Map || value is List;
    if (complex) {
      final count = value is Map
          ? (value! as Map).length
          : (value! as List).length;
      return ExpansionTile(
        initiallyExpanded: depth == 0 && count <= 12,
        tilePadding: EdgeInsets.fromLTRB(12 + depth * 12, 0, 8, 0),
        childrenPadding: EdgeInsets.zero,
        title: Text(label, style: consoleMono(weight: FontWeight.w600)),
        subtitle: Text(
          value is Map
              ? context.t.sessions.data.fields(n: count)
              : context.t.sessions.data.items(n: count),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        children: [_StructuredValue(value: value, depth: depth + 1)],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + depth * 12, 7, 12, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: consoleMono(
                size: 11,
                color: context.consoleColors.inkSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              _displayScalar(value),
              style: consoleMono(color: context.consoleColors.inkPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isEmpty(Object? value) =>
    value == null ||
    (value is Map && value.isEmpty) ||
    (value is List && value.isEmpty);

String _displayScalar(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  return jsonEncode(value);
}
