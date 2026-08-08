import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_canonical_paths.dart';
import '../foundation/cockpit_filesystem_identity.dart';
import '../foundation/cockpit_locked_json_store.dart';
import 'cockpit_reference_record_codec.dart';
import 'cockpit_registry_record_codec.dart';
import 'cockpit_registry_records.dart';
import 'cockpit_registry_value_reader.dart';

final class CockpitRegistryState {
  CockpitRegistryState({
    List<CockpitRootRecord>? roots,
    List<CockpitWorkspaceRecord>? workspaces,
    List<CockpitSessionReferenceRecord>? sessions,
    List<CockpitRunReferenceRecord>? runs,
    List<CockpitOtherReferenceRecord>? otherReferences,
    List<CockpitLatestRunRecord>? latestRuns,
    List<CockpitMarkerMutationRecord>? markerMutations,
    List<CockpitRetiredWorkspaceIdentityRecord>? retiredWorkspaceIdentities,
  }) : roots = roots ?? <CockpitRootRecord>[],
       workspaces = workspaces ?? <CockpitWorkspaceRecord>[],
       sessions = sessions ?? <CockpitSessionReferenceRecord>[],
       runs = runs ?? <CockpitRunReferenceRecord>[],
       otherReferences = otherReferences ?? <CockpitOtherReferenceRecord>[],
       latestRuns = latestRuns ?? <CockpitLatestRunRecord>[],
       markerMutations = markerMutations ?? <CockpitMarkerMutationRecord>[],
       retiredWorkspaceIdentities =
           retiredWorkspaceIdentities ??
           <CockpitRetiredWorkspaceIdentityRecord>[];

  final List<CockpitRootRecord> roots;
  final List<CockpitWorkspaceRecord> workspaces;
  final List<CockpitSessionReferenceRecord> sessions;
  final List<CockpitRunReferenceRecord> runs;
  final List<CockpitOtherReferenceRecord> otherReferences;
  final List<CockpitLatestRunRecord> latestRuns;
  final List<CockpitMarkerMutationRecord> markerMutations;
  final List<CockpitRetiredWorkspaceIdentityRecord> retiredWorkspaceIdentities;

  void validate(CockpitLexicalPaths lexicalPaths) {
    _unique(roots.map((value) => value.rootId), 'rootId');
    _unique(
      roots
          .where((value) => value.state != CockpitRootState.retired)
          .map((value) => value.filesystemIdentity),
      'root filesystem identity',
    );
    _unique(workspaces.map((value) => value.workspaceId), 'workspaceId');
    _unique(workspaces.map((value) => value.checkoutId), 'checkoutId');
    _unique(
      workspaces
          .where(
            (value) =>
                value.state != CockpitWorkspaceState.retired &&
                value.identityQuality.isStrong,
          )
          .map((value) => value.filesystemIdentity),
      'strong workspace filesystem identity',
    );
    _unique(
      sessions.map((value) => '${value.workspaceId}\u0000${value.sessionId}'),
      'workspace session',
    );
    _unique(
      runs.map((value) => '${value.workspaceId}\u0000${value.runId}'),
      'workspace run',
    );
    _unique(latestRuns.map((value) => value.workspaceId), 'latest workspace');
    _unique(
      markerMutations.map((value) => value.workspaceId),
      'marker mutation workspace',
    );
    _unique(
      retiredWorkspaceIdentities.map((value) => value.workspaceId),
      'retired workspaceId',
    );
    _unique(
      retiredWorkspaceIdentities.map((value) => value.checkoutId),
      'retired checkoutId',
    );
    for (final root in roots) {
      _validateCanonicalPath(
        lexicalPaths,
        root.canonicalPath,
        'root canonicalPath',
      );
    }
    for (var left = 0; left < roots.length; left += 1) {
      for (var right = left + 1; right < roots.length; right += 1) {
        final leftRoot = roots[left];
        final rightRoot = roots[right];
        if (leftRoot.state != CockpitRootState.retired &&
            rightRoot.state != CockpitRootState.retired &&
            lexicalPaths.overlaps(
              leftRoot.canonicalPath,
              rightRoot.canonicalPath,
            )) {
          throw const FormatException('Registry roots overlap.');
        }
      }
    }
    for (final workspace in workspaces) {
      _validateCanonicalPath(
        lexicalPaths,
        workspace.canonicalPath,
        'workspace canonicalPath',
      );
    }
    for (var left = 0; left < workspaces.length; left += 1) {
      for (var right = left + 1; right < workspaces.length; right += 1) {
        if (workspaces[left].state != CockpitWorkspaceState.retired &&
            workspaces[right].state != CockpitWorkspaceState.retired &&
            lexicalPaths.equals(
              workspaces[left].canonicalPath,
              workspaces[right].canonicalPath,
            )) {
          throw const FormatException('Duplicate workspace canonical path.');
        }
      }
    }
    final rootIds = roots.map((value) => value.rootId).toSet();
    final workspaceIds = workspaces.map((value) => value.workspaceId).toSet();
    for (final workspace in workspaces) {
      if (!rootIds.contains(workspace.rootId)) {
        throw const FormatException('Workspace references an unknown root.');
      }
      final root = roots.singleWhere(
        (candidate) => candidate.rootId == workspace.rootId,
      );
      if (!lexicalPaths.contains(root.canonicalPath, workspace.canonicalPath)) {
        throw const FormatException(
          'Workspace canonical path is outside its referenced root.',
        );
      }
      if (workspace.identityQuality.isStrong) {
        for (final candidate in roots) {
          if (candidate.state != CockpitRootState.retired &&
              candidate.identityQuality.isStrong &&
              candidate.filesystemIdentity == workspace.filesystemIdentity &&
              !lexicalPaths.equals(
                candidate.canonicalPath,
                workspace.canonicalPath,
              )) {
            throw const FormatException(
              'Strong filesystem identity targets conflicting paths.',
            );
          }
        }
      }
      if (workspace.state == CockpitWorkspaceState.active &&
          root.state != CockpitRootState.active) {
        throw const FormatException(
          'Active workspace references a non-active root.',
        );
      }
    }
    for (final workspaceId in <String>[
      ...sessions.map((value) => value.workspaceId),
      ...runs.map((value) => value.workspaceId),
      ...otherReferences.map((value) => value.workspaceId),
      ...latestRuns.map((value) => value.workspaceId),
      ...markerMutations.map((value) => value.workspaceId),
    ]) {
      if (!workspaceIds.contains(workspaceId)) {
        throw const FormatException('Reference targets an unknown workspace.');
      }
    }
    for (final latest in latestRuns) {
      if (!runs.any(
        (run) =>
            run.workspaceId == latest.workspaceId && run.runId == latest.runId,
      )) {
        throw const FormatException('Latest run target is missing.');
      }
    }
    for (final session in sessions) {
      if (_workspace(session.workspaceId).state ==
          CockpitWorkspaceState.retired) {
        throw const FormatException(
          'Active session targets retired workspace.',
        );
      }
    }
    for (final run in runs) {
      if (run.active &&
          _workspace(run.workspaceId).state == CockpitWorkspaceState.retired) {
        throw const FormatException('Active run targets retired workspace.');
      }
    }
    for (final reference in otherReferences) {
      if (_workspace(reference.workspaceId).state ==
          CockpitWorkspaceState.retired) {
        throw const FormatException(
          'Active reference targets retired workspace.',
        );
      }
    }
    for (final mutation in markerMutations) {
      if (_workspace(mutation.workspaceId).state !=
              CockpitWorkspaceState.active ||
          mutation.expectedProjectId == mutation.projectId) {
        throw const FormatException('Invalid pending marker mutation.');
      }
    }
  }

  CockpitWorkspaceRecord _workspace(String workspaceId) => workspaces
      .singleWhere((candidate) => candidate.workspaceId == workspaceId);

  void _validateCanonicalPath(
    CockpitLexicalPaths lexicalPaths,
    String value,
    String label,
  ) {
    late final String normalized;
    try {
      normalized = lexicalPaths.normalizeAbsolute(value);
    } on CockpitPathException {
      throw FormatException('$label must be absolute.');
    }
    if (normalized != value) {
      throw FormatException('$label must be normalized.');
    }
  }

  void _unique(Iterable<String> values, String label) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) {
        throw FormatException('Duplicate $label in registry.');
      }
    }
  }
}

final class CockpitRegistryStateCodec
    implements CockpitJsonCodec<CockpitRegistryState> {
  const CockpitRegistryStateCodec(this.lexicalPaths);

  final CockpitLexicalPaths lexicalPaths;

  static const schemaVersion = 'cockpit.registry/v2';
  static const _fields = <String>{
    'schemaVersion',
    'roots',
    'workspaces',
    'sessions',
    'runs',
    'otherReferences',
    'latestRuns',
    'markerMutations',
    'retiredWorkspaceIdentities',
  };

  @override
  CockpitRegistryState decode(Object? value) {
    final json = CockpitRegistryValueReader.object(value, r'$', _fields);
    if (CockpitRegistryValueReader.string(
          json['schemaVersion'],
          r'$.schemaVersion',
        ) !=
        schemaVersion) {
      throw const FormatException('Unsupported registry schemaVersion.');
    }
    final state = CockpitRegistryState(
      roots: _decodeList(
        json['roots'],
        r'$.roots',
        CockpitRegistryRecordCodec.decodeRoot,
      ),
      workspaces: _decodeList(
        json['workspaces'],
        r'$.workspaces',
        CockpitRegistryRecordCodec.decodeWorkspace,
      ),
      sessions: _decodeList(
        json['sessions'],
        r'$.sessions',
        CockpitReferenceRecordCodec.decodeSession,
      ),
      runs: _decodeList(
        json['runs'],
        r'$.runs',
        CockpitReferenceRecordCodec.decodeRun,
      ),
      otherReferences: _decodeList(
        json['otherReferences'],
        r'$.otherReferences',
        CockpitReferenceRecordCodec.decodeOther,
      ),
      latestRuns: _decodeList(
        json['latestRuns'],
        r'$.latestRuns',
        CockpitReferenceRecordCodec.decodeLatest,
      ),
      markerMutations: _decodeList(
        json['markerMutations'],
        r'$.markerMutations',
        CockpitReferenceRecordCodec.decodeMarkerMutation,
      ),
      retiredWorkspaceIdentities: _decodeList(
        json['retiredWorkspaceIdentities'],
        r'$.retiredWorkspaceIdentities',
        CockpitReferenceRecordCodec.decodeRetiredIdentity,
      ),
    );
    state.validate(lexicalPaths);
    return state;
  }

  @override
  Object? encode(CockpitRegistryState value) {
    value.validate(lexicalPaths);
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'roots': value.roots.map(CockpitRegistryRecordCodec.encodeRoot).toList(),
      'workspaces': value.workspaces
          .map(CockpitRegistryRecordCodec.encodeWorkspace)
          .toList(),
      'sessions': value.sessions
          .map(CockpitReferenceRecordCodec.encodeSession)
          .toList(),
      'runs': value.runs.map(CockpitReferenceRecordCodec.encodeRun).toList(),
      'otherReferences': value.otherReferences
          .map(CockpitReferenceRecordCodec.encodeOther)
          .toList(),
      'latestRuns': value.latestRuns
          .map(CockpitReferenceRecordCodec.encodeLatest)
          .toList(),
      'markerMutations': value.markerMutations
          .map(CockpitReferenceRecordCodec.encodeMarkerMutation)
          .toList(),
      'retiredWorkspaceIdentities': value.retiredWorkspaceIdentities
          .map(CockpitReferenceRecordCodec.encodeRetiredIdentity)
          .toList(),
    };
  }

  List<T> _decodeList<T>(
    Object? value,
    String path,
    T Function(Object? value, String path) decode,
  ) {
    final source = CockpitRegistryValueReader.list(value, path);
    return <T>[
      for (var index = 0; index < source.length; index += 1)
        decode(source[index], '$path[$index]'),
    ];
  }
}
