import 'package:flutter/material.dart';

import '../../model/todo_priority.dart';
import '../../model/todo_task.dart';
import '../theme/orbit_todo_theme.dart';

final class PlanningSurfaceCard extends StatelessWidget {
  const PlanningSurfaceCard({
    required this.tasks,
    required this.zoomLevel,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onResetZoom,
    super.key,
  });

  final List<TodoTask> tasks;
  final double zoomLevel;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final VoidCallback onResetZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lanes = <_PlanningLaneData>[
      _PlanningLaneData(
        title: 'Now',
        subtitle: 'Top focus',
        tasks: tasks.take(2).toList(growable: false),
      ),
      _PlanningLaneData(
        title: 'Next',
        subtitle: 'Queued',
        tasks: tasks.skip(2).take(2).toList(growable: false),
      ),
      _PlanningLaneData(
        title: 'Later',
        subtitle: 'Backlog',
        tasks: tasks.skip(4).take(2).toList(growable: false),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.editorialMutedSurfaceColor,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withAlphaFraction(0.88),
          ),
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlphaFraction(0.88),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'PLANNING',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Planning surface',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use pinch to adjust lane density before reordering the queue or checking handoff pressure.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Canvas ${(zoomLevel * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(onPressed: onResetZoom, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 18),
            GestureDetector(
              key: const Key('planning-surface-gesture'),
              behavior: HitTestBehavior.opaque,
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.editorialSurfaceColor),
                child: CustomPaint(
                  painter: _PlanningGridPainter(
                    dividerColor: colorScheme.outlineVariant.withAlphaFraction(
                      0.72,
                    ),
                    accentColor: colorScheme.primary.withAlphaFraction(0.08),
                  ),
                  child: SizedBox(
                    height: 232,
                    child: Transform.scale(
                      scale: zoomLevel,
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: lanes
                              .map(
                                (lane) =>
                                    Expanded(child: _PlanningLane(lane: lane)),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PlanningLaneData {
  const _PlanningLaneData({
    required this.title,
    required this.subtitle,
    required this.tasks,
  });

  final String title;
  final String subtitle;
  final List<TodoTask> tasks;
}

final class _PlanningLane extends StatelessWidget {
  const _PlanningLane({required this.lane});

  final _PlanningLaneData lane;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withAlphaFraction(0.82),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              lane.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              lane.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: lane.tasks.isEmpty
                    ? <Widget>[
                        Text(
                          'No tasks staged.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]
                    : lane.tasks
                          .map((task) => _PlanningLine(task: task))
                          .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PlanningLine extends StatelessWidget {
  const _PlanningLine({required this.task});

  final TodoTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lineColor = switch (task.priority) {
      TodoPriority.low => colorScheme.secondary,
      TodoPriority.medium => colorScheme.tertiary,
      TodoPriority.high => colorScheme.primary,
      TodoPriority.urgent => colorScheme.error,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: lineColor, width: 2),
            top: BorderSide(
              color: colorScheme.outlineVariant.withAlphaFraction(0.7),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                task.priority.name.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: lineColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PlanningGridPainter extends CustomPainter {
  const _PlanningGridPainter({
    required this.dividerColor,
    required this.accentColor,
  });

  final Color dividerColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dividerPaint = Paint()
      ..color = dividerColor
      ..strokeWidth = 1;
    final accentPaint = Paint()..color = accentColor;
    canvas.drawRect(Offset.zero & size, accentPaint);
    const rowHeight = 46.0;
    for (var y = rowHeight; y < size.height; y += rowHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), dividerPaint);
    }
    for (var x = size.width / 3; x < size.width; x += size.width / 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dividerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanningGridPainter oldDelegate) {
    return oldDelegate.dividerColor != dividerColor ||
        oldDelegate.accentColor != accentColor;
  }
}
