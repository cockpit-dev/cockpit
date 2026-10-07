import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marker widget whose subtree is excluded from interaction recording
/// (exclusion tier a).
///
/// The capture layer walks the hit-test path of every observed event and
/// drops events whose path contains a [CockpitRecorderExcludeRenderObject].
/// Wrap host chrome that lives inside the app tree (for example a
/// third-party floating window); chrome mounted beside the capture subtree,
/// such as the default recorder HUD, never enters the hit-test path and
/// needs no marker.
///
/// Example:
///
/// ```dart
/// CockpitRecorderExclude(child: MyHostPanel())
/// ```
final class CockpitRecorderExclude extends SingleChildRenderObjectWidget {
  /// Creates an exclusion marker wrapping [child].
  const CockpitRecorderExclude({super.key, required Widget child})
    : super(child: child);

  @override
  CockpitRecorderExcludeRenderObject createRenderObject(BuildContext context) =>
      CockpitRecorderExcludeRenderObject();
}

/// The render object type [CockpitRecorderExclude] installs.
///
/// The type is the marker: the capture layer detects it with an `is` check
/// while walking a hit path's ancestry. It paints and lays out nothing of
/// its own.
final class CockpitRecorderExcludeRenderObject extends RenderProxyBox {}

/// Mutable registry of subtree roots excluded from interaction recording
/// (exclusion tier b).
///
/// Hosts whose chrome they cannot wrap with [CockpitRecorderExclude] register
/// render objects here instead. The capture layer consults the registry per
/// observed event, so registrations take effect immediately and no change
/// notification is needed.
final class CockpitRecorderExclusionRegistry {
  final Set<RenderObject> _roots = <RenderObject>{};

  /// Whether no roots are currently registered.
  bool get isEmpty => _roots.isEmpty;

  /// Registers [root] as an excluded subtree root. Idempotent: registering
  /// an already-registered root is a no-op.
  void register(RenderObject root) => _roots.add(root);

  /// Unregisters a previously registered root. Unregistering an unknown
  /// root is a no-op, so detach handlers never need pairing guards.
  void unregister(RenderObject root) => _roots.remove(root);

  /// Whether [root] is currently registered.
  bool isRegistered(RenderObject root) => _roots.contains(root);

  /// Whether any node in [path] is a marker render object or a descendant
  /// of a registered root — that is, whether an event hitting [path] must
  /// be excluded from recording.
  ///
  /// Every path entry's parent chain is walked to the render-tree root, so
  /// exclusion also holds for partial paths that omit an ancestor. The walk
  /// is deliberately unbounded: parent chains terminate at the root render
  /// object by construction, while a depth cap could silently miss an
  /// exclusion and record host chrome.
  bool coversPath(Iterable<RenderObject> path) {
    for (final node in path) {
      for (
        RenderObject? current = node;
        current != null;
        current = current.parent
      ) {
        if (current is CockpitRecorderExcludeRenderObject ||
            _roots.contains(current)) {
          return true;
        }
      }
    }
    return false;
  }
}
