import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interaction laboratory backing the CI command-coverage verification.
///
/// Every pad mirrors its latest observation into a discoverable status text,
/// so each in-app command type can be verified by asserting the UI effect it
/// produced instead of trusting a successful exit alone.
final class CommandLabScreen extends StatefulWidget {
  const CommandLabScreen({super.key});

  @override
  State<CommandLabScreen> createState() => _CommandLabScreenState();
}

final class _CommandLabScreenState extends State<CommandLabScreen> {
  String _gesture = 'idle';
  String _pan = 'idle';
  String _swipe = 'idle';
  String _transform = 'idle';
  String _touch = 'idle';
  String _hover = 'idle';
  String _wheel = 'idle';
  String _key = 'idle';
  String _submitted = 'none';
  bool _dismissCardVisible = true;
  double _sliderValue = 0.5;
  bool _cupertinoEnabled = false;
  int _cupertinoLayout = 0;

  Offset _panTotal = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;
  int _maxConcurrentPointers = 0;
  int _wheelEvents = 0;

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _cupertinoTextController =
      TextEditingController();
  final FocusNode _textFocusNode = FocusNode(debugLabel: 'lab-text-field');
  final FocusNode _keyPadFocusNode = FocusNode(debugLabel: 'lab-key-pad');

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _cupertinoTextController.addListener(_onTextChanged);
    _textFocusNode.addListener(_onFocusChanged);
    _keyPadFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _cupertinoTextController.removeListener(_onTextChanged);
    _textFocusNode.removeListener(_onFocusChanged);
    _keyPadFocusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _cupertinoTextController.dispose();
    _textFocusNode.dispose();
    _keyPadFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _onFocusChanged() => setState(() {});

  void _recordPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final kind = velocity.distance >= 900 ? 'fling' : 'drag';
    final horizontal = _panTotal.dx.abs() >= _panTotal.dy.abs();
    final direction = horizontal
        ? (_panTotal.dx >= 0 ? 'right' : 'left')
        : (_panTotal.dy >= 0 ? 'down' : 'up');
    setState(() => _pan = '$kind-$direction');
  }

  void _recordScaleEnd(ScaleEndDetails details) {
    setState(() {
      if (_lastRotation.abs() > 0.5) {
        _transform = 'rotated';
      } else if (_lastScale > 1.25) {
        _transform = 'scale-up';
      } else if (_lastScale < 0.8) {
        _transform = 'scale-down';
      } else {
        _transform = 'panned';
      }
    });
  }

  KeyEventResult _recordKeyEvent(FocusNode node, KeyEvent event) {
    final phase = switch (event) {
      KeyDownEvent() => 'down',
      KeyUpEvent() => 'up',
      KeyRepeatEvent() => 'repeat',
      _ => 'unknown',
    };
    final name = event.logicalKey.debugName ?? event.logicalKey.keyLabel;
    setState(() => _key = '${name.replaceAll(' ', '')}-$phase');
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Command Lab')),
      // A non-virtualized scroll view keeps every target built, so deep
      // targets remain resolvable for showOnScreen while off-viewport.
      body: SingleChildScrollView(
        key: const Key('lab-scroll-view'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _statusText('lab-gesture-status', 'gesture:$_gesture', theme),
            _pad(
              key: 'lab-gesture-pad',
              label: 'Gesture pad',
              color: theme.colorScheme.primaryContainer,
              child: GestureDetector(
                key: const Key('lab-gesture-detector'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _gesture = 'tap'),
                onDoubleTap: () => setState(() => _gesture = 'doubleTap'),
                onLongPress: () => setState(() => _gesture = 'longPress'),
                child: const SizedBox(
                  height: 88,
                  child: Center(child: Text('Tap, double tap, or hold')),
                ),
              ),
            ),
            _statusText('lab-pan-status', 'pan:$_pan', theme),
            _pad(
              key: 'lab-pan-pad',
              label: 'Pan pad',
              color: theme.colorScheme.secondaryContainer,
              child: GestureDetector(
                key: const Key('lab-pan-detector'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _panTotal = Offset.zero,
                onPanUpdate: (details) => _panTotal += details.delta,
                onPanEnd: _recordPanEnd,
                child: const SizedBox(
                  height: 104,
                  child: Center(child: Text('Drag or fling across this pad')),
                ),
              ),
            ),
            _statusText('lab-swipe-status', 'swipe:$_swipe', theme),
            _pad(
              key: 'lab-swipe-pad',
              label: 'Swipe pad',
              color: theme.colorScheme.tertiaryContainer,
              child: GestureDetector(
                key: const Key('lab-swipe-detector'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  setState(() => _swipe = velocity <= 0 ? 'up' : 'down');
                },
                child: const SizedBox(
                  height: 104,
                  child: Center(child: Text('Swipe up or down on this pad')),
                ),
              ),
            ),
            _statusText('lab-transform-status', 'transform:$_transform', theme),
            _pad(
              key: 'lab-transform-pad',
              label: 'Transform pad',
              color: theme.colorScheme.surfaceContainerHighest,
              child: GestureDetector(
                key: const Key('lab-transform-detector'),
                behavior: HitTestBehavior.opaque,
                // The scale recognizer also consumes trackpad pan-zoom
                // pointer events, so panZoom verification lands here too.
                onScaleStart: (_) {
                  _lastScale = 1;
                  _lastRotation = 0;
                },
                onScaleUpdate: (details) {
                  _lastScale = details.scale;
                  _lastRotation = details.rotation;
                },
                onScaleEnd: _recordScaleEnd,
                child: const SizedBox(
                  height: 128,
                  child: Center(child: Text('Pinch, rotate, or pan-zoom')),
                ),
              ),
            ),
            TextButton(
              key: const Key('lab-transform-reset'),
              onPressed: () => setState(() => _transform = 'idle'),
              child: const Text('Reset transform pad'),
            ),
            _statusText('lab-multitouch-status', 'touch:$_touch', theme),
            _pad(
              key: 'lab-multitouch-pad',
              label: 'Multi-touch pad',
              color: theme.colorScheme.primaryContainer,
              child: GestureDetector(
                key: const Key('lab-multitouch-listener'),
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _recordPointerCount(details.pointerCount);
                },
                onScaleUpdate: (details) {
                  _recordPointerCount(details.pointerCount);
                },
                child: const SizedBox(
                  height: 104,
                  child: Center(child: Text('Touch with several pointers')),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _statusText('lab-hover-status', 'hover:$_hover', theme),
            _pad(
              key: 'lab-hover-pad',
              label: 'Hover pad',
              color: theme.colorScheme.tertiaryContainer,
              child: MouseRegion(
                key: const Key('lab-hover-region'),
                opaque: true,
                onEnter: (_) => setState(() => _hover = 'entered'),
                onHover: (_) {
                  if (_hover != 'entered') {
                    setState(() => _hover = 'entered');
                  }
                },
                onExit: (_) => setState(() => _hover = 'exited'),
                child: const SizedBox(
                  height: 88,
                  child: Center(child: Text('Move a pointer across this pad')),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _statusText('lab-wheel-status', 'wheel:$_wheel', theme),
            _pad(
              key: 'lab-wheel-pad',
              label: 'Wheel pad',
              color: theme.colorScheme.secondaryContainer,
              child: Listener(
                key: const Key('lab-wheel-listener'),
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final direction = event.scrollDelta.dy < 0 ? 'up' : 'down';
                    setState(() {
                      _wheelEvents += 1;
                      _wheel = '$direction-$_wheelEvents';
                    });
                  }
                },
                child: const SizedBox(
                  height: 88,
                  child: Center(child: Text('Send wheel or trackpad input')),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _statusText(
              'lab-slider-status',
              'slider:${(_sliderValue * 100).round()}',
              theme,
            ),
            Semantics(
              key: const Key('lab-slider-semantics'),
              container: true,
              label: 'Lab slider',
              value: '${(_sliderValue * 100).round()}',
              increasedValue:
                  '${((_sliderValue + 0.1).clamp(0.0, 1.0) * 100).round()}',
              decreasedValue:
                  '${((_sliderValue - 0.1).clamp(0.0, 1.0) * 100).round()}',
              onIncrease: () {
                setState(() {
                  _sliderValue = (_sliderValue + 0.1).clamp(0.0, 1.0);
                });
              },
              onDecrease: () {
                setState(() {
                  _sliderValue = (_sliderValue - 0.1).clamp(0.0, 1.0);
                });
              },
              child: Slider(
                key: const Key('lab-slider'),
                value: _sliderValue,
                divisions: 10,
                label: 'Lab level',
                onChanged: (value) => setState(() => _sliderValue = value),
              ),
            ),
            const SizedBox(height: 12),
            _statusText(
              'lab-dismiss-status',
              'dismiss:${_dismissCardVisible ? 'visible' : 'done'}',
              theme,
            ),
            if (_dismissCardVisible)
              Semantics(
                key: const Key('lab-dismiss-card'),
                label: 'Dismissible lab card',
                onDismiss: () => setState(() => _dismissCardVisible = false),
                child: Card(
                  color: theme.colorScheme.errorContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Dismiss me through semantics'),
                  ),
                ),
              )
            else
              TextButton(
                key: const Key('lab-dismiss-reset'),
                onPressed: () => setState(() => _dismissCardVisible = true),
                child: const Text('Restore dismissible card'),
              ),
            const SizedBox(height: 20),
            _statusText(
              'lab-focus-status',
              'focus:${_textFocusNode.hasFocus ? 'yes' : 'no'}',
              theme,
            ),
            _statusText(
              'lab-text-status',
              'text:${_textController.text}',
              theme,
            ),
            _statusText('lab-submit-status', 'submitted:$_submitted', theme),
            TextField(
              key: const Key('lab-text-field'),
              controller: _textController,
              focusNode: _textFocusNode,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Lab text field',
                hintText: 'Type into the lab',
              ),
              onSubmitted: (value) => setState(() => _submitted = value),
            ),
            const SizedBox(height: 20),
            _statusText(
              'lab-cupertino-status',
              'cupertino:${_cupertinoEnabled ? 'on' : 'off'}:'
                  '${_cupertinoLayout == 0 ? 'grid' : 'list'}:'
                  '${_cupertinoTextController.text}',
              theme,
            ),
            _pad(
              key: 'lab-cupertino-pad',
              label: 'Cupertino controls',
              color: theme.colorScheme.surfaceContainerHighest,
              child: Column(
                children: <Widget>[
                  CupertinoSwitch(
                    key: const Key('lab-cupertino-switch'),
                    value: _cupertinoEnabled,
                    onChanged: (value) =>
                        setState(() => _cupertinoEnabled = value),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    key: const Key('lab-cupertino-text'),
                    controller: _cupertinoTextController,
                    placeholder: 'Cupertino message',
                  ),
                  const SizedBox(height: 12),
                  CupertinoSlidingSegmentedControl<int>(
                    key: const Key('lab-cupertino-layout'),
                    groupValue: _cupertinoLayout,
                    children: const <int, Widget>{
                      0: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Grid'),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('List'),
                      ),
                    },
                    onValueChanged: (value) => setState(
                      () => _cupertinoLayout = value ?? _cupertinoLayout,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _statusText('lab-key-status', 'key:$_key', theme),
            _statusText(
              'lab-key-focus-status',
              'keyFocus:${_keyPadFocusNode.hasFocus ? 'yes' : 'no'}',
              theme,
            ),
            Focus(
              focusNode: _keyPadFocusNode,
              onKeyEvent: _recordKeyEvent,
              child: _pad(
                key: 'lab-key-pad',
                label: 'Key pad',
                color: theme.colorScheme.secondaryContainer,
                child: GestureDetector(
                  key: const Key('lab-key-pad-activator'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _keyPadFocusNode.requestFocus();
                    setState(() => _key = 'focused');
                  },
                  child: const SizedBox(
                    height: 88,
                    child: Center(
                      child: Text('Tap to focus, then send key events'),
                    ),
                  ),
                ),
              ),
            ),
            // Deep spacer keeps the target below the fold on every CI
            // viewport so showOnScreen has real scrolling work to do.
            const SizedBox(height: 1400),
            Card(
              key: const Key('lab-deep-item'),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Deep lab target reached'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _recordPointerCount(int pointerCount) {
    if (pointerCount <= 0) {
      return;
    }
    if (pointerCount > _maxConcurrentPointers) {
      _maxConcurrentPointers = pointerCount;
    }
    setState(() => _touch = '$_maxConcurrentPointers-pointers');
  }

  Widget _statusText(String key, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(value, key: Key(key), style: theme.textTheme.labelLarge),
    );
  }

  Widget _pad({
    required String key,
    required String label,
    required Color color,
    required Widget child,
  }) {
    return Card(
      key: Key(key),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: Semantics(label: label, container: true, child: child),
    );
  }
}
