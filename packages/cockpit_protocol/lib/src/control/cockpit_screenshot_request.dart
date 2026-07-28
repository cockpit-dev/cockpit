import '../runtime/cockpit_snapshot_options.dart';
import '../capture/cockpit_capture_profile.dart';
import 'cockpit_locator.dart';

enum CockpitScreenshotReason {
  baseline('baseline'),
  beforeAction('before_action'),
  afterAction('after_action'),
  assertionFailure('assertion_failure'),
  acceptance('acceptance');

  const CockpitScreenshotReason(this.jsonValue);

  final String jsonValue;

  static CockpitScreenshotReason fromJson(Object? json) {
    return values.firstWhere(
      (reason) => reason.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported screenshot reason.',
      ),
    );
  }
}

final class CockpitScreenshotRequest {
  const CockpitScreenshotRequest({
    required this.reason,
    required this.name,
    this.includeSnapshot = false,
    this.attachToStep = false,
    this.snapshotOptions,
    this.profile,
    this.allowFallback,
    this.cropLocator,
  });

  final CockpitScreenshotReason reason;
  final String name;
  final bool includeSnapshot;
  final bool attachToStep;
  final CockpitSnapshotOptions? snapshotOptions;
  final CockpitCaptureProfile? profile;
  final bool? allowFallback;
  final CockpitLocator? cropLocator;

  bool get allowsFallback => allowFallback ?? true;

  Map<String, Object?> toJson() => {
    'reason': reason.jsonValue,
    'name': name,
    'includeSnapshot': includeSnapshot,
    'attachToStep': attachToStep,
    if (snapshotOptions != null) 'snapshotOptions': snapshotOptions!.toJson(),
    if (profile != null) 'profile': profile!.name,
    if (allowFallback != null) 'allowFallback': allowFallback,
    if (cropLocator != null) 'cropLocator': cropLocator!.toJson(),
  };

  factory CockpitScreenshotRequest.fromJson(Map<String, Object?> json) {
    final snapshotOptionsJson =
        json['snapshotOptions'] as Map<Object?, Object?>?;
    final cropLocatorJson = json['cropLocator'] as Map<Object?, Object?>?;
    return CockpitScreenshotRequest(
      reason: CockpitScreenshotReason.fromJson(json['reason']),
      name: json['name']! as String,
      includeSnapshot: json['includeSnapshot'] as bool? ?? false,
      attachToStep: json['attachToStep'] as bool? ?? false,
      snapshotOptions: snapshotOptionsJson == null
          ? null
          : CockpitSnapshotOptions.fromJson(
              Map<String, Object?>.from(snapshotOptionsJson),
            ),
      profile: json['profile'] == null
          ? null
          : CockpitCaptureProfile.fromJson(json['profile']),
      allowFallback: json['allowFallback'] as bool?,
      cropLocator: cropLocatorJson == null
          ? null
          : CockpitLocator.fromJson(Map<String, Object?>.from(cropLocatorJson)),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitScreenshotRequest &&
            other.reason == reason &&
            other.name == name &&
            other.includeSnapshot == includeSnapshot &&
            other.attachToStep == attachToStep &&
            other.snapshotOptions == snapshotOptions &&
            other.profile == profile &&
            other.allowFallback == allowFallback &&
            other.cropLocator == cropLocator;
  }

  @override
  int get hashCode => Object.hash(
    reason,
    name,
    includeSnapshot,
    attachToStep,
    snapshotOptions,
    profile,
    allowFallback,
    cropLocator,
  );

  CockpitScreenshotRequest copyWith({
    CockpitScreenshotReason? reason,
    String? name,
    bool? includeSnapshot,
    bool? attachToStep,
    CockpitSnapshotOptions? snapshotOptions,
    Object? profile = _unsetField,
    Object? allowFallback = _unsetField,
    Object? cropLocator = _unsetField,
  }) {
    return CockpitScreenshotRequest(
      reason: reason ?? this.reason,
      name: name ?? this.name,
      includeSnapshot: includeSnapshot ?? this.includeSnapshot,
      attachToStep: attachToStep ?? this.attachToStep,
      snapshotOptions: snapshotOptions ?? this.snapshotOptions,
      profile: identical(profile, _unsetField)
          ? this.profile
          : profile as CockpitCaptureProfile?,
      allowFallback: identical(allowFallback, _unsetField)
          ? this.allowFallback
          : allowFallback as bool?,
      cropLocator: identical(cropLocator, _unsetField)
          ? this.cropLocator
          : cropLocator as CockpitLocator?,
    );
  }
}

const Object _unsetField = Object();
