import '../network/cockpit_network_query.dart';
import '../foundation/cockpit_foundation_value_reader.dart';
import 'cockpit_runtime_query.dart';

enum CockpitSnapshotProfile {
  live('live'),
  baseline('baseline'),
  investigate('investigate'),
  forensic('forensic');

  /// Creates a CockpitSnapshotProfile.
  const CockpitSnapshotProfile(this.jsonValue);

  final String jsonValue;

  static CockpitSnapshotProfile fromJson(Object? json) {
    return values.firstWhere(
      (profile) => profile.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported snapshot profile.',
      ),
    );
  }
}

final class CockpitSnapshotOptions {
  /// Creates a CockpitSnapshotOptions.
  const CockpitSnapshotOptions({
    this.profile = CockpitSnapshotProfile.live,
    this.maxTargets = 25,
    this.maxAncestorsPerTarget = 0,
    this.maxPropertiesPerTarget = 0,
    this.includeStyleDetails = false,
    this.includeDiagnosticProperties = false,
    this.emitArtifactWhenLarge = false,
    this.includeRebuildActivity = false,
    this.maxRebuildEntries = 8,
    this.includeNetworkActivity = false,
    this.maxNetworkEntries = 8,
    this.networkQuery = const CockpitNetworkQuery(),
    this.includeRuntimeActivity = false,
    this.maxRuntimeEntries = 8,
    this.runtimeQuery = const CockpitRuntimeQuery(),
    this.includeAccessibilitySummary = false,
    this.maxAccessibilityEntries = 8,
  });

  /// Creates a CockpitSnapshotOptions using the named constructor `live`.
  const CockpitSnapshotOptions.live()
    : this(profile: CockpitSnapshotProfile.live);

  /// Creates a CockpitSnapshotOptions using the named constructor `baseline`.
  const CockpitSnapshotOptions.baseline()
    : this(
        profile: CockpitSnapshotProfile.baseline,
        maxTargets: 30,
        maxAncestorsPerTarget: 1,
        maxPropertiesPerTarget: 6,
      );

  /// Creates a CockpitSnapshotOptions using the named constructor `investigate`.
  const CockpitSnapshotOptions.investigate()
    : this(
        profile: CockpitSnapshotProfile.investigate,
        maxTargets: 40,
        maxAncestorsPerTarget: 3,
        maxPropertiesPerTarget: 12,
        includeStyleDetails: true,
        includeDiagnosticProperties: true,
        includeRebuildActivity: true,
        includeNetworkActivity: true,
        networkQuery: const CockpitNetworkQuery(onlyFailures: true),
        includeRuntimeActivity: true,
        runtimeQuery: const CockpitRuntimeQuery(onlyErrors: true),
        includeAccessibilitySummary: true,
      );

  /// Creates a CockpitSnapshotOptions using the named constructor `forensic`.
  const CockpitSnapshotOptions.forensic()
    : this(
        profile: CockpitSnapshotProfile.forensic,
        maxTargets: 80,
        maxAncestorsPerTarget: 6,
        maxPropertiesPerTarget: 24,
        includeStyleDetails: true,
        includeDiagnosticProperties: true,
        emitArtifactWhenLarge: true,
        includeRebuildActivity: true,
        maxRebuildEntries: 16,
        includeNetworkActivity: true,
        maxNetworkEntries: 20,
        networkQuery: const CockpitNetworkQuery(onlyFailures: true),
        includeRuntimeActivity: true,
        maxRuntimeEntries: 20,
        includeAccessibilitySummary: true,
        maxAccessibilityEntries: 20,
      );

  final CockpitSnapshotProfile profile;
  final int maxTargets;
  final int maxAncestorsPerTarget;
  final int maxPropertiesPerTarget;
  final bool includeStyleDetails;
  final bool includeDiagnosticProperties;
  final bool emitArtifactWhenLarge;
  final bool includeRebuildActivity;
  final int maxRebuildEntries;
  final bool includeNetworkActivity;
  final int maxNetworkEntries;
  final CockpitNetworkQuery networkQuery;
  final bool includeRuntimeActivity;
  final int maxRuntimeEntries;
  final CockpitRuntimeQuery runtimeQuery;
  final bool includeAccessibilitySummary;
  final int maxAccessibilityEntries;

  /// Encodes this CockpitSnapshotOptions as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.jsonValue,
    'maxTargets': maxTargets,
    'maxAncestorsPerTarget': maxAncestorsPerTarget,
    'maxPropertiesPerTarget': maxPropertiesPerTarget,
    'includeStyleDetails': includeStyleDetails,
    'includeDiagnosticProperties': includeDiagnosticProperties,
    'emitArtifactWhenLarge': emitArtifactWhenLarge,
    'includeRebuildActivity': includeRebuildActivity,
    'maxRebuildEntries': maxRebuildEntries,
    'includeNetworkActivity': includeNetworkActivity,
    'maxNetworkEntries': maxNetworkEntries,
    'networkQuery': networkQuery.toJson(),
    'includeRuntimeActivity': includeRuntimeActivity,
    'maxRuntimeEntries': maxRuntimeEntries,
    'runtimeQuery': runtimeQuery.toJson(),
    'includeAccessibilitySummary': includeAccessibilitySummary,
    'maxAccessibilityEntries': maxAccessibilityEntries,
  };

  /// Decodes a CockpitSnapshotOptions from a JSON object.
  factory CockpitSnapshotOptions.fromJson(Map<String, Object?> json) {
    CockpitFoundationValueReader.keys(json, const <String>{
      'profile',
      'maxTargets',
      'maxAncestorsPerTarget',
      'maxPropertiesPerTarget',
      'includeStyleDetails',
      'includeDiagnosticProperties',
      'emitArtifactWhenLarge',
      'includeRebuildActivity',
      'maxRebuildEntries',
      'includeNetworkActivity',
      'maxNetworkEntries',
      'networkQuery',
      'includeRuntimeActivity',
      'maxRuntimeEntries',
      'runtimeQuery',
      'includeAccessibilitySummary',
      'maxAccessibilityEntries',
    }, r'$');
    final networkQueryJson = json['networkQuery'] == null
        ? null
        : CockpitFoundationValueReader.object(
            json['networkQuery'],
            r'$.networkQuery',
          );
    final runtimeQueryJson = json['runtimeQuery'] == null
        ? null
        : CockpitFoundationValueReader.object(
            json['runtimeQuery'],
            r'$.runtimeQuery',
          );
    return CockpitSnapshotOptions(
      profile: json['profile'] == null
          ? CockpitSnapshotProfile.live
          : CockpitSnapshotProfile.fromJson(json['profile']),
      maxTargets: _integer(json, 'maxTargets', 25, maximum: 100000),
      maxAncestorsPerTarget: _integer(
        json,
        'maxAncestorsPerTarget',
        0,
        maximum: 256,
      ),
      maxPropertiesPerTarget: _integer(
        json,
        'maxPropertiesPerTarget',
        0,
        maximum: 100000,
      ),
      includeStyleDetails: _boolean(json, 'includeStyleDetails'),
      includeDiagnosticProperties: _boolean(
        json,
        'includeDiagnosticProperties',
      ),
      emitArtifactWhenLarge: _boolean(json, 'emitArtifactWhenLarge'),
      includeRebuildActivity: _boolean(json, 'includeRebuildActivity'),
      maxRebuildEntries: _integer(json, 'maxRebuildEntries', 8, maximum: 10000),
      includeNetworkActivity: _boolean(json, 'includeNetworkActivity'),
      maxNetworkEntries: _integer(json, 'maxNetworkEntries', 8, maximum: 10000),
      networkQuery: networkQueryJson == null
          ? const CockpitNetworkQuery()
          : CockpitNetworkQuery.fromJson(
              Map<String, Object?>.from(networkQueryJson),
            ),
      includeRuntimeActivity: _boolean(json, 'includeRuntimeActivity'),
      maxRuntimeEntries: _integer(json, 'maxRuntimeEntries', 8, maximum: 10000),
      runtimeQuery: runtimeQueryJson == null
          ? const CockpitRuntimeQuery()
          : CockpitRuntimeQuery.fromJson(
              Map<String, Object?>.from(runtimeQueryJson),
            ),
      includeAccessibilitySummary: _boolean(
        json,
        'includeAccessibilitySummary',
      ),
      maxAccessibilityEntries: _integer(
        json,
        'maxAccessibilityEntries',
        8,
        maximum: 10000,
      ),
    );
  }

  /// Returns a copy of this CockpitSnapshotOptions with supplied fields replaced.
  CockpitSnapshotOptions copyWith({
    CockpitSnapshotProfile? profile,
    int? maxTargets,
    int? maxAncestorsPerTarget,
    int? maxPropertiesPerTarget,
    bool? includeStyleDetails,
    bool? includeDiagnosticProperties,
    bool? emitArtifactWhenLarge,
    bool? includeRebuildActivity,
    int? maxRebuildEntries,
    bool? includeNetworkActivity,
    int? maxNetworkEntries,
    CockpitNetworkQuery? networkQuery,
    bool? includeRuntimeActivity,
    int? maxRuntimeEntries,
    CockpitRuntimeQuery? runtimeQuery,
    bool? includeAccessibilitySummary,
    int? maxAccessibilityEntries,
  }) {
    return CockpitSnapshotOptions(
      profile: profile ?? this.profile,
      maxTargets: maxTargets ?? this.maxTargets,
      maxAncestorsPerTarget:
          maxAncestorsPerTarget ?? this.maxAncestorsPerTarget,
      maxPropertiesPerTarget:
          maxPropertiesPerTarget ?? this.maxPropertiesPerTarget,
      includeStyleDetails: includeStyleDetails ?? this.includeStyleDetails,
      includeDiagnosticProperties:
          includeDiagnosticProperties ?? this.includeDiagnosticProperties,
      emitArtifactWhenLarge:
          emitArtifactWhenLarge ?? this.emitArtifactWhenLarge,
      includeRebuildActivity:
          includeRebuildActivity ?? this.includeRebuildActivity,
      maxRebuildEntries: maxRebuildEntries ?? this.maxRebuildEntries,
      includeNetworkActivity:
          includeNetworkActivity ?? this.includeNetworkActivity,
      maxNetworkEntries: maxNetworkEntries ?? this.maxNetworkEntries,
      networkQuery: networkQuery ?? this.networkQuery,
      includeRuntimeActivity:
          includeRuntimeActivity ?? this.includeRuntimeActivity,
      maxRuntimeEntries: maxRuntimeEntries ?? this.maxRuntimeEntries,
      runtimeQuery: runtimeQuery ?? this.runtimeQuery,
      includeAccessibilitySummary:
          includeAccessibilitySummary ?? this.includeAccessibilitySummary,
      maxAccessibilityEntries:
          maxAccessibilityEntries ?? this.maxAccessibilityEntries,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitSnapshotOptions &&
            other.profile == profile &&
            other.maxTargets == maxTargets &&
            other.maxAncestorsPerTarget == maxAncestorsPerTarget &&
            other.maxPropertiesPerTarget == maxPropertiesPerTarget &&
            other.includeStyleDetails == includeStyleDetails &&
            other.includeDiagnosticProperties == includeDiagnosticProperties &&
            other.emitArtifactWhenLarge == emitArtifactWhenLarge &&
            other.includeRebuildActivity == includeRebuildActivity &&
            other.maxRebuildEntries == maxRebuildEntries &&
            other.includeNetworkActivity == includeNetworkActivity &&
            other.maxNetworkEntries == maxNetworkEntries &&
            other.networkQuery == networkQuery &&
            other.includeRuntimeActivity == includeRuntimeActivity &&
            other.maxRuntimeEntries == maxRuntimeEntries &&
            other.runtimeQuery == runtimeQuery &&
            other.includeAccessibilitySummary == includeAccessibilitySummary &&
            other.maxAccessibilityEntries == maxAccessibilityEntries;
  }

  @override
  int get hashCode => Object.hash(
    profile,
    maxTargets,
    maxAncestorsPerTarget,
    maxPropertiesPerTarget,
    includeStyleDetails,
    includeDiagnosticProperties,
    emitArtifactWhenLarge,
    includeRebuildActivity,
    maxRebuildEntries,
    includeNetworkActivity,
    maxNetworkEntries,
    networkQuery,
    includeRuntimeActivity,
    maxRuntimeEntries,
    runtimeQuery,
    includeAccessibilitySummary,
    maxAccessibilityEntries,
  );
}

bool _boolean(Map<String, Object?> json, String key) => json[key] == null
    ? false
    : CockpitFoundationValueReader.boolean(json[key], '\$.$key');

int _integer(
  Map<String, Object?> json,
  String key,
  int defaultValue, {
  required int maximum,
}) => json[key] == null
    ? defaultValue
    : CockpitFoundationValueReader.integer(
        json[key],
        '\$.$key',
        min: 0,
        max: maximum,
      );
