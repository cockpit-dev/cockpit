import 'package:collection/collection.dart';

import 'cockpit_artifact_ref.dart';
import 'cockpit_task_status.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';

final class CockpitRunManifest {
  /// Creates a CockpitRunManifest.
  CockpitRunManifest({
    required this.sessionId,
    required this.taskId,
    required this.platform,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    List<CockpitArtifactRef> artifactRefs = const [],
    this.failureSummary,
    this.targetKind,
    this.primaryExecutionPlane,
    List<CockpitPlaneKind> planesUsed = const [],
    List<CockpitSurfaceKind> surfaceKindsUsed = const [],
    this.fallbackCount = 0,
    List<String> capabilitiesUsed = const [],
    this.commandCount = 0,
    this.screenshotCount = 0,
    this.failureCount = 0,
    this.nativeScreenshotCount = 0,
    this.flutterScreenshotCount = 0,
    this.deliveryArtifactsReady = false,
    List<String> deliveryArtifactFailureCodes = const [],
    this.recordingCount = 0,
    this.nativeRecordingCount = 0,
    this.deliveryVideoReady = false,
    List<String> deliveryVideoFailureCodes = const [],
    this.runtimeEventCount = 0,
    this.runtimeErrorCount = 0,
    this.runtimeWarningCount = 0,
  }) : artifactRefs = List.unmodifiable(artifactRefs),
       planesUsed = List.unmodifiable(planesUsed),
       surfaceKindsUsed = List.unmodifiable(surfaceKindsUsed),
       capabilitiesUsed = List.unmodifiable(capabilitiesUsed),
       deliveryArtifactFailureCodes = List.unmodifiable(
         deliveryArtifactFailureCodes,
       ),
       deliveryVideoFailureCodes = List.unmodifiable(deliveryVideoFailureCodes);

  final String sessionId;
  final String taskId;
  final String platform;
  final CockpitTaskStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<CockpitArtifactRef> artifactRefs;
  final String? failureSummary;
  final CockpitTargetKind? targetKind;
  final CockpitPlaneKind? primaryExecutionPlane;
  final List<CockpitPlaneKind> planesUsed;
  final List<CockpitSurfaceKind> surfaceKindsUsed;
  final int fallbackCount;
  final List<String> capabilitiesUsed;
  final int commandCount;
  final int screenshotCount;
  final int failureCount;
  final int nativeScreenshotCount;
  final int flutterScreenshotCount;
  final bool deliveryArtifactsReady;
  final List<String> deliveryArtifactFailureCodes;
  final int recordingCount;
  final int nativeRecordingCount;
  final bool deliveryVideoReady;
  final List<String> deliveryVideoFailureCodes;
  final int runtimeEventCount;
  final int runtimeErrorCount;
  final int runtimeWarningCount;

  static const ListEquality<CockpitArtifactRef> _artifactListEquality =
      ListEquality<CockpitArtifactRef>();
  static const ListEquality<CockpitPlaneKind> _planeListEquality =
      ListEquality<CockpitPlaneKind>();
  static const ListEquality<CockpitSurfaceKind> _surfaceListEquality =
      ListEquality<CockpitSurfaceKind>();
  static const ListEquality<String> _stringListEquality =
      ListEquality<String>();

  /// Encodes this CockpitRunManifest as a JSON object.
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'taskId': taskId,
    'platform': platform,
    'status': status.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    'artifactRefs': artifactRefs.map((artifact) => artifact.toJson()).toList(),
    if (failureSummary != null) 'failureSummary': failureSummary,
    if (targetKind != null) 'targetKind': targetKind!.name,
    if (primaryExecutionPlane != null)
      'primaryExecutionPlane': primaryExecutionPlane!.name,
    if (planesUsed.isNotEmpty)
      'planesUsed': planesUsed.map((plane) => plane.name).toList(),
    if (surfaceKindsUsed.isNotEmpty)
      'surfaceKindsUsed': surfaceKindsUsed
          .map((surface) => surface.name)
          .toList(),
    if (fallbackCount > 0) 'fallbackCount': fallbackCount,
    'capabilitiesUsed': capabilitiesUsed,
    'commandCount': commandCount,
    'screenshotCount': screenshotCount,
    'failureCount': failureCount,
    'nativeScreenshotCount': nativeScreenshotCount,
    'flutterScreenshotCount': flutterScreenshotCount,
    'deliveryArtifactsReady': deliveryArtifactsReady,
    'deliveryArtifactFailureCodes': deliveryArtifactFailureCodes,
    'recordingCount': recordingCount,
    'nativeRecordingCount': nativeRecordingCount,
    'deliveryVideoReady': deliveryVideoReady,
    'deliveryVideoFailureCodes': deliveryVideoFailureCodes,
    'runtimeEventCount': runtimeEventCount,
    'runtimeErrorCount': runtimeErrorCount,
    'runtimeWarningCount': runtimeWarningCount,
  };

  /// Decodes a CockpitRunManifest from a JSON object.
  factory CockpitRunManifest.fromJson(Map<String, Object?> json) {
    final artifactRefs =
        (json['artifactRefs'] as List<Object?>? ?? const <Object?>[])
            .cast<Map<Object?, Object?>>()
            .map(
              (item) =>
                  CockpitArtifactRef.fromJson(Map<String, Object?>.from(item)),
            )
            .toList();

    return CockpitRunManifest(
      sessionId: json['sessionId']! as String,
      taskId: json['taskId']! as String,
      platform: json['platform']! as String,
      status: CockpitTaskStatus.fromJson(json['status']),
      startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt']! as String).toUtc(),
      artifactRefs: artifactRefs,
      failureSummary: json['failureSummary'] as String?,
      targetKind: json['targetKind'] == null
          ? null
          : CockpitTargetKind.fromJson(json['targetKind']),
      primaryExecutionPlane: json['primaryExecutionPlane'] == null
          ? null
          : CockpitPlaneKind.fromJson(json['primaryExecutionPlane']),
      planesUsed: (json['planesUsed'] as List<Object?>? ?? const <Object?>[])
          .map(CockpitPlaneKind.fromJson)
          .toList(growable: false),
      surfaceKindsUsed:
          (json['surfaceKindsUsed'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitSurfaceKind.fromJson)
              .toList(growable: false),
      fallbackCount: json['fallbackCount'] as int? ?? 0,
      capabilitiesUsed:
          (json['capabilitiesUsed'] as List<Object?>? ?? const <Object?>[])
              .cast<String>(),
      commandCount: json['commandCount'] as int? ?? 0,
      screenshotCount: json['screenshotCount'] as int? ?? 0,
      failureCount: json['failureCount'] as int? ?? 0,
      nativeScreenshotCount: json['nativeScreenshotCount'] as int? ?? 0,
      flutterScreenshotCount: json['flutterScreenshotCount'] as int? ?? 0,
      deliveryArtifactsReady: json['deliveryArtifactsReady'] as bool? ?? false,
      deliveryArtifactFailureCodes:
          (json['deliveryArtifactFailureCodes'] as List<Object?>? ??
                  const <Object?>[])
              .cast<String>(),
      recordingCount: json['recordingCount'] as int? ?? 0,
      nativeRecordingCount: json['nativeRecordingCount'] as int? ?? 0,
      deliveryVideoReady: json['deliveryVideoReady'] as bool? ?? false,
      deliveryVideoFailureCodes:
          (json['deliveryVideoFailureCodes'] as List<Object?>? ??
                  const <Object?>[])
              .cast<String>(),
      runtimeEventCount: json['runtimeEventCount'] as int? ?? 0,
      runtimeErrorCount: json['runtimeErrorCount'] as int? ?? 0,
      runtimeWarningCount: json['runtimeWarningCount'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRunManifest &&
            other.sessionId == sessionId &&
            other.taskId == taskId &&
            other.platform == platform &&
            other.status == status &&
            other.startedAt == startedAt &&
            other.finishedAt == finishedAt &&
            other.failureSummary == failureSummary &&
            other.targetKind == targetKind &&
            other.primaryExecutionPlane == primaryExecutionPlane &&
            _planeListEquality.equals(other.planesUsed, planesUsed) &&
            _surfaceListEquality.equals(
              other.surfaceKindsUsed,
              surfaceKindsUsed,
            ) &&
            other.fallbackCount == fallbackCount &&
            other.commandCount == commandCount &&
            other.screenshotCount == screenshotCount &&
            other.failureCount == failureCount &&
            other.nativeScreenshotCount == nativeScreenshotCount &&
            other.flutterScreenshotCount == flutterScreenshotCount &&
            other.deliveryArtifactsReady == deliveryArtifactsReady &&
            _stringListEquality.equals(
              other.deliveryArtifactFailureCodes,
              deliveryArtifactFailureCodes,
            ) &&
            other.recordingCount == recordingCount &&
            other.nativeRecordingCount == nativeRecordingCount &&
            other.deliveryVideoReady == deliveryVideoReady &&
            _stringListEquality.equals(
              other.deliveryVideoFailureCodes,
              deliveryVideoFailureCodes,
            ) &&
            other.runtimeEventCount == runtimeEventCount &&
            other.runtimeErrorCount == runtimeErrorCount &&
            other.runtimeWarningCount == runtimeWarningCount &&
            _stringListEquality.equals(
              other.capabilitiesUsed,
              capabilitiesUsed,
            ) &&
            _artifactListEquality.equals(other.artifactRefs, artifactRefs);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    sessionId,
    taskId,
    platform,
    status,
    startedAt,
    finishedAt,
    failureSummary,
    targetKind,
    primaryExecutionPlane,
    _planeListEquality.hash(planesUsed),
    _surfaceListEquality.hash(surfaceKindsUsed),
    fallbackCount,
    commandCount,
    screenshotCount,
    failureCount,
    nativeScreenshotCount,
    flutterScreenshotCount,
    deliveryArtifactsReady,
    _stringListEquality.hash(deliveryArtifactFailureCodes),
    recordingCount,
    nativeRecordingCount,
    deliveryVideoReady,
    _stringListEquality.hash(deliveryVideoFailureCodes),
    runtimeEventCount,
    runtimeErrorCount,
    runtimeWarningCount,
    _stringListEquality.hash(capabilitiesUsed),
    _artifactListEquality.hash(artifactRefs),
  ]);
}
