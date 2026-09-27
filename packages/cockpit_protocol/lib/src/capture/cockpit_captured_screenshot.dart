import 'dart:typed_data';

import '../model/cockpit_artifact_ref.dart';
import '../runtime/cockpit_snapshot.dart';

final class CockpitCapturedScreenshot {
  /// Creates a CockpitCapturedScreenshot.
  const CockpitCapturedScreenshot({
    required this.artifact,
    required this.bytes,
    this.snapshot,
    this.degradationReason,
  });

  final CockpitArtifactRef artifact;
  final Uint8List bytes;
  final CockpitSnapshot? snapshot;

  /// Why this screenshot may not reflect the latest completed visual frame.
  final String? degradationReason;
}
