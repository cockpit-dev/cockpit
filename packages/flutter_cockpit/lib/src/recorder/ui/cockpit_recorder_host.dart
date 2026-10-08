import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_recorder_exclusion.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_entry_button.dart';
import 'cockpit_recorder_indicator.dart';
import 'cockpit_recorder_panel.dart';
import 'cockpit_recorder_panel_widgets.dart';

/// Computes the resting position of the floating ball after a drag ends:
/// clamped into [bounds] vertically and docked to the nearer horizontal
/// edge. Pure so drag docking is unit-testable without a widget tree.
Offset cockpitRecorderSnapBallPosition(
  Offset position,
  Size bounds,
  Size ballSize,
) {
  final maxY = (bounds.height - ballSize.height)
      .clamp(0.0, double.infinity)
      .toDouble();
  final maxX = (bounds.width - ballSize.width)
      .clamp(0.0, double.infinity)
      .toDouble();
  final docksLeft = position.dx + ballSize.width / 2 < bounds.width / 2;
  return Offset(
    docksLeft ? 0.0 : maxX,
    position.dy.clamp(0.0, maxY).toDouble(),
  );
}

/// Default recorder host: a draggable floating ball that expands into a
/// full-screen panel over the app.
///
/// Mount topology (verified against `FlutterCockpitRootState.build`): the
/// host mounts as a later `Stack` sibling *above* the capture-wrapped
/// surface, next to the tap-feedback overlay. Stack hit testing visits
/// children top-down and stops at the first absorbing child, so taps on the
/// ball and panel never enter the capture `Listener`'s hit-test path, and
/// the host sits outside the surface `RepaintBoundary`, so evidence
/// screenshots never include it. The [CockpitRecorderExclude] wrapper below
/// is belt-and-braces for the same chrome embedded inside an app tree —
/// when nothing hits the capture layer, the marker simply never matches.
final class CockpitRecorderHost extends StatefulWidget {
  /// Creates the floating-ball host over [controller].
  const CockpitRecorderHost({required this.controller, super.key});

  final CockpitRecorderController controller;

  @override
  State<CockpitRecorderHost> createState() => _CockpitRecorderHostState();
}

final class _CockpitRecorderHostState extends State<CockpitRecorderHost> {
  static const Size _ballSize = Size(40, 40);
  static const double _maxPanelWidth = 840;
  static const Duration _snapAnimation = Duration(milliseconds: 200);

  /// Null until the first layout provides screen bounds; then the docked
  /// default (right edge, 70% down).
  Offset? _ballPosition;
  bool _expanded = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return CockpitRecorderExclude(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounds = constraints.biggest;
          final position = _resolvePosition(bounds);
          return _buildTextEnvironment(
            Stack(
              children: <Widget>[
                AnimatedPositioned(
                  key: const ValueKey<String>('cockpit_recorder_ball'),
                  duration: _dragging ? Duration.zero : _snapAnimation,
                  curve: Curves.easeOut,
                  left: position.dx,
                  top: position.dy,
                  width: _ballSize.width,
                  height: _ballSize.height,
                  child: GestureDetector(
                    // Opaque so the square region around the circular ball
                    // still starts drags; taps resolve to the inner
                    // EntryButton's recognizer, which wins the arena.
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => setState(() => _dragging = true),
                    onPanUpdate: (details) => setState(() {
                      final current = _ballPosition!;
                      _ballPosition = Offset(
                        (current.dx + details.delta.dx)
                            .clamp(0.0, bounds.width - _ballSize.width)
                            .toDouble(),
                        (current.dy + details.delta.dy)
                            .clamp(0.0, bounds.height - _ballSize.height)
                            .toDouble(),
                      );
                    }),
                    onPanEnd: (_) => setState(() {
                      _dragging = false;
                      _ballPosition = cockpitRecorderSnapBallPosition(
                        _ballPosition!,
                        bounds,
                        _ballSize,
                      );
                    }),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        CockpitRecorderEntryButton(
                          onTap: () => setState(() => _expanded = !_expanded),
                        ),
                        _buildRecordingRing(),
                        Positioned(
                          right: -2,
                          top: -2,
                          child: CockpitRecorderIndicator(
                            controller: widget.controller,
                            showLabel: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded) _buildFullscreenPanel(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Static ring tracing the ball while a session records — no animation,
  /// which would keep frames scheduled and break `pumpAndSettle` in host
  /// app tests.
  Widget _buildRecordingRing() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final recording =
                widget.controller.phase == CockpitRecorderPhase.recording;
            return DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: recording
                      ? cockpitRecorderPanelDanger
                      : const Color(0x00000000),
                  width: 2,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The expanded panel: a full-screen overlay whose content column is
  /// centered and capped at [_maxPanelWidth] on wide windows.
  Widget _buildFullscreenPanel() {
    return Positioned.fill(
      key: const ValueKey<String>('cockpit_recorder_fullscreen'),
      child: Container(
        color: cockpitRecorderPanelBackground,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxPanelWidth),
            child: CockpitRecorderPanel(
              onClose: () => setState(() => _expanded = false),
            ),
          ),
        ),
      ),
    );
  }

  /// The root Stack builds above the app's `MaterialApp`, so the host
  /// provides its own text environment. The [MediaQuery] feeds
  /// [EditableText]'s context-menu positioning; absence would only degrade
  /// that menu, but view-derived data costs nothing.
  Widget _buildTextEnvironment(Widget child) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: view == null ? MediaQueryData() : MediaQueryData.fromView(view),
        child: child,
      ),
    );
  }

  Offset _resolvePosition(Size bounds) {
    final position = _ballPosition;
    if (position == null) {
      return _ballPosition = cockpitRecorderSnapBallPosition(
        Offset(bounds.width, bounds.height * 0.7),
        bounds,
        _ballSize,
      );
    }
    // While dragging, the pan handler owns the position; otherwise re-dock
    // so a rotated or resized screen never strands the ball off-screen.
    if (_dragging) {
      return position;
    }
    return cockpitRecorderSnapBallPosition(position, bounds, _ballSize);
  }
}
