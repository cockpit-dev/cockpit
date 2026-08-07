import 'dart:typed_data';

import '../model/cockpit_artifact_ref.dart';
import '../runtime/cockpit_snapshot.dart';

final class CockpitCapturedScreenshot {
  /// Creates a CockpitCapturedScreenshot.
  const CockpitCapturedScreenshot({
    required this.artifact,
    required this.bytes,
    this.snapshot,
  });

  final CockpitArtifactRef artifact;
  final Uint8List bytes;
  final CockpitSnapshot? snapshot;
}
