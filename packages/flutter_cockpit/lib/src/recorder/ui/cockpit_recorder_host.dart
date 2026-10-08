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

/// Default recorder host: a draggable dark floating ball that expands
/// into a mobile-HUD overlay — a full-width bottom sheet with a grab handle
/// on phone-width windows, a centered 480-wide solid card on wider ones.
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

final class _CockpitRecorderHostState extends State<CockpitRecorderHost>
    with SingleTickerProviderStateMixin {
  static const Size _ballSize = Size(40, 40);

  /// Window widths up to this present the bottom-sheet form; wider ones
  /// get the centered card.
  static const double _sheetBreakpoint = 640;
  static const double _sheetHeightFactor = 0.72;
  static const double _cardWidth = 480;
  static const double _cardMaxHeight = 620;
  static const Duration _snapAnimation = Duration(milliseconds: 200);
  static const Duration _expandAnimation = Duration(milliseconds: 220);
  static const Duration _collapseAnimation = Duration(milliseconds: 180);

  late final AnimationController _overlayController = AnimationController(
    vsync: this,
    duration: _expandAnimation,
    reverseDuration: _collapseAnimation,
  );
  late final CurvedAnimation _overlayCurve = CurvedAnimation(
    parent: _overlayController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Null until the first layout provides screen bounds; then the docked
  /// default (right edge, 70% down).
  Offset? _ballPosition;

  /// True while the overlay subtree should exist: from the expand tap until
  /// the collapse animation has fully played out, so the panel slides away
  /// instead of blinking out.
  bool _expanded = false;
  bool _dragging = false;

  /// The phase seen by the previous controller notification, so collapse
  /// triggers on the *transition* into recording — not on every step the
  /// recording session later records while the panel happens to be open.
  /// Initialized in [initState] (a lazy `late` initializer would first run
  /// during a notification, when the transition it should observe is
  /// already over).
  CockpitRecorderPhase _observedPhase = CockpitRecorderPhase.idle;

  @override
  void initState() {
    super.initState();
    _observedPhase = widget.controller.phase;
    widget.controller.addListener(_handleControllerNotification);
    _overlayController.addStatusListener(_handleOverlayStatus);
  }

  @override
  void didUpdateWidget(covariant CockpitRecorderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerNotification);
      widget.controller.addListener(_handleControllerNotification);
      _observedPhase = widget.controller.phase;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerNotification);
    _overlayCurve.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  /// Recording begins with the panel collapsed: the HUD gets out of the way
  /// so the user records the app, not the recorder.
  void _handleControllerNotification() {
    final phase = widget.controller.phase;
    final beganRecording =
        phase == CockpitRecorderPhase.recording &&
        _observedPhase != CockpitRecorderPhase.recording;
    _observedPhase = phase;
    if (_expanded && beganRecording) {
      _collapseOverlay();
    }
  }

  void _handleOverlayStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _expanded) {
      setState(() => _expanded = false);
    }
  }

  void _expandOverlay() {
    setState(() => _expanded = true);
    _overlayController.forward();
  }

  void _collapseOverlay() {
    _overlayController.reverse();
  }

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
                          onTap: () =>
                              _expanded ? _collapseOverlay() : _expandOverlay(),
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
                if (_expanded) _buildExpandedOverlay(),
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
                      ? cockpitRecorderRecord
                      : const Color(0x00000000),
                  width: 1.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The expanded state: a scrim over the app with the solid dark recorder
  /// panel on top. The sheet/card hugs its content — a short recording
  /// reads as a compact receipt, not a mostly-empty frame — capped at 72%
  /// of the overlay height on windows up to [_sheetBreakpoint] wide (a
  /// full-width bottom sheet with a grab handle), and at 480×620 on wider
  /// ones (a centered card). The whole overlay fades in while the panel
  /// rises a touch, and plays the reverse on collapse; both are one-shot,
  /// so nothing keeps scheduling frames once settled. Tapping the scrim
  /// does nothing — closing goes through the header's close button.
  Widget _buildExpandedOverlay() {
    return Positioned.fill(
      key: const ValueKey<String>('cockpit_recorder_fullscreen'),
      child: FadeTransition(
        opacity: _overlayCurve,
        child: ColoredBox(
          color: cockpitRecorderScrim,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounds = constraints.biggest;
              final panel = CockpitRecorderPanel(onClose: _collapseOverlay);
              Widget slide(Widget child) => SlideTransition(
                position: _overlayCurve.drive(
                  Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero),
                ),
                child: child,
              );
              if (bounds.width <= _sheetBreakpoint) {
                return slide(
                  Align(
                    alignment: AlignmentDirectional.bottomCenter,
                    child: ClipPath(
                      clipper: const ShapeBorderClipper(
                        shape: cockpitRecorderSheetTopShape,
                      ),
                      child: ConstrainedBox(
                        key: const ValueKey<String>(
                          'cockpit_recorder_panel_frame',
                        ),
                        constraints: BoxConstraints(
                          maxHeight: bounds.height * _sheetHeightFactor,
                        ),
                        child: SizedBox(
                          width: bounds.width,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const _SheetGrabHandle(),
                              // Flexible carries the height cap into the
                              // panel: a min-size Column hands non-flex
                              // children an unbounded main axis, which would
                              // let the feed grow past the cap instead of
                              // scrolling.
                              Flexible(child: panel),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return slide(
                Center(
                  child: ClipPath(
                    clipper: const ShapeBorderClipper(
                      shape: cockpitRecorderSheetShape,
                    ),
                    child: ConstrainedBox(
                      key: const ValueKey<String>(
                        'cockpit_recorder_panel_frame',
                      ),
                      constraints: const BoxConstraints(
                        maxWidth: _cardWidth,
                        maxHeight: _cardMaxHeight,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[Flexible(child: panel)],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The root Stack builds above the app's `MaterialApp`, so the host
  /// provides its own text environment. The [MediaQuery] feeds
  /// [EditableText]'s context-menu positioning and the panel's bottom-inset
  /// padding; absence would only degrade both, but view-derived data costs
  /// nothing.
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

/// The bottom sheet's grab handle: a 36×5 tertiary pill, centered, 8 from
/// the sheet's top edge.
final class _SheetGrabHandle extends StatelessWidget {
  const _SheetGrabHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 21,
      child: Center(
        child: Container(
          key: const ValueKey<String>('cockpit_recorder_sheet_handle'),
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: cockpitRecorderInkTertiary,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}
