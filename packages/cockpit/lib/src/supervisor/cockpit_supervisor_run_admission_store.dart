import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';

final class CockpitSupervisorRunAdmission {
  CockpitSupervisorRunAdmission({
    required this.workspaceId,
    required this.idempotencyKey,
    required this.fingerprint,
    required this.runId,
    required this.requestId,
    required this.projectId,
    required this.documentKind,
    required this.documentId,
    required this.sourceSha256,
    required this.submittedAt,
  }) {
    for (final entry in <String, String>{
      'workspaceId': workspaceId,
      'runId': runId,
      'requestId': requestId,
      'projectId': projectId,
      'documentId': documentId,
    }.entries) {
      if (!_id.hasMatch(entry.value)) {
        throw FormatException('${entry.key} is invalid.');
      }
    }
    if (idempotencyKey.isEmpty || idempotencyKey.length > 256) {
      throw const FormatException('Run idempotency key is invalid.');
    }
    if (!_sha256.hasMatch(fingerprint) || !_sha256.hasMatch(sourceSha256)) {
      throw const FormatException('Run admission digest is invalid.');
    }
    if (!submittedAt.isUtc) {
      throw const FormatException('Run admission timestamp must be UTC.');
    }
  }

  final String workspaceId;
  final String idempotencyKey;
  final String fingerprint;
  final String runId;
  final String requestId;
  final String projectId;
  final CockpitRunDocumentKind documentKind;
  final String documentId;
  final String sourceSha256;
  final DateTime submittedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'idempotencyKey': idempotencyKey,
    'fingerprint': fingerprint,
    'runId': runId,
    'requestId': requestId,
    'projectId': projectId,
    'documentKind': documentKind == CockpitRunDocumentKind.testCase
        ? 'case'
        : documentKind.name,
    'documentId': documentId,
    'sourceSha256': sourceSha256,
    'submittedAt': submittedAt.toIso8601String(),
  };

  factory CockpitSupervisorRunAdmission.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Run admission must be a JSON object.');
    }
    const fields = <String>{
      'workspaceId',
      'idempotencyKey',
      'fingerprint',
      'runId',
      'requestId',
      'projectId',
      'documentKind',
      'documentId',
      'sourceSha256',
      'submittedAt',
    };
    if (value.keys.any((key) => key is! String || !fields.contains(key)) ||
        fields.any((field) => !value.containsKey(field))) {
      throw const FormatException('Run admission fields are invalid.');
    }
    String string(String key) {
      final item = value[key];
      if (item is! String) throw FormatException('$key must be a string.');
      return item;
    }

    final submittedAt = DateTime.tryParse(string('submittedAt'));
    if (submittedAt == null || !submittedAt.isUtc) {
      throw const FormatException('Run admission timestamp is invalid.');
    }
    return CockpitSupervisorRunAdmission(
      workspaceId: string('workspaceId'),
      idempotencyKey: string('idempotencyKey'),
      fingerprint: string('fingerprint'),
      runId: string('runId'),
      requestId: string('requestId'),
      projectId: string('projectId'),
      documentKind: _documentKind(value['documentKind']),
      documentId: string('documentId'),
      sourceSha256: string('sourceSha256'),
      submittedAt: submittedAt,
    );
  }
}

final class CockpitSupervisorRunAdmissionResult {
  const CockpitSupervisorRunAdmissionResult({
    required this.admission,
    required this.replayed,
  });

  final CockpitSupervisorRunAdmission admission;
  final bool replayed;
}

final class CockpitSupervisorRunAdmissionConflict implements Exception {
  const CockpitSupervisorRunAdmissionConflict();
}

final class CockpitSupervisorRunAdmissionStore {
  CockpitSupervisorRunAdmissionStore({
    required CockpitHomePaths paths,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    CockpitTokenGenerator? tokenGenerator,
    this.maximumAdmissions = 10000,
  }) : _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _store = CockpitLockedJsonStore<_AdmissionState>(
         path: p.join(paths.runsDirectory, 'admissions.json'),
         codec: const _AdmissionStateCodec(),
         createInitial: _AdmissionState.empty,
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
         maximumBytes: 16 * 1024 * 1024,
       ) {
    if (maximumAdmissions < 1 || maximumAdmissions > 100000) {
      throw ArgumentError.value(maximumAdmissions, 'maximumAdmissions');
    }
  }

  final int maximumAdmissions;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitLockedJsonStore<_AdmissionState> _store;

  Future<CockpitSupervisorRunAdmissionResult> admit({
    required String workspaceId,
    required String idempotencyKey,
    required String fingerprint,
    required String projectId,
    required CockpitRunDocumentKind documentKind,
    required String documentId,
    required String sourceSha256,
    required DateTime submittedAt,
  }) => _store.transact((state) {
    final key = _admissionKey(workspaceId, idempotencyKey);
    final existing = state.byKey[key];
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        throw const CockpitSupervisorRunAdmissionConflict();
      }
      return CockpitLockedJsonUpdate.readOnly(
        state,
        CockpitSupervisorRunAdmissionResult(
          admission: existing,
          replayed: true,
        ),
      );
    }
    if (state.byKey.length >= maximumAdmissions) {
      throw const FormatException('Supervisor run admission bound exceeded.');
    }
    final runId = _nextRunId(state);
    final admission = CockpitSupervisorRunAdmission(
      workspaceId: workspaceId,
      idempotencyKey: idempotencyKey,
      fingerprint: fingerprint,
      runId: runId,
      requestId: runId,
      projectId: projectId,
      documentKind: documentKind,
      documentId: documentId,
      sourceSha256: sourceSha256,
      submittedAt: submittedAt,
    );
    final updated = state.copy();
    updated.byKey[key] = admission;
    updated.byRunId[admission.runId] = admission;
    return CockpitLockedJsonUpdate.write(
      updated,
      CockpitSupervisorRunAdmissionResult(
        admission: admission,
        replayed: false,
      ),
    );
  });

  String _nextRunId(_AdmissionState state) {
    for (var attempt = 0; attempt < 32; attempt += 1) {
      final runId = _tokenGenerator.nextResourceId('r');
      if (!state.byRunId.containsKey(runId)) return runId;
    }
    throw const FormatException('Could not allocate a unique run id.');
  }

  Future<CockpitSupervisorRunAdmission?> findRun(String runId) async =>
      (await _store.read()).byRunId[runId];

  Future<void> validateOwner({
    required String workspaceId,
    required String runId,
    required String projectId,
    required String? caseId,
  }) async {
    final admission = await findRun(runId);
    if (admission == null) {
      throw const FormatException('Run has no durable admission.');
    }
    if (admission.workspaceId != workspaceId ||
        admission.projectId != projectId ||
        (admission.documentKind == CockpitRunDocumentKind.testCase &&
            caseId != null &&
            admission.documentId != caseId)) {
      throw const FormatException(
        'Projected run ownership conflicts with durable admission.',
      );
    }
  }
}

CockpitRunDocumentKind _documentKind(Object? value) {
  if (value == 'case') return CockpitRunDocumentKind.testCase;
  if (value == 'suite') return CockpitRunDocumentKind.suite;
  throw const FormatException('Run admission document kind is invalid.');
}

final class _AdmissionState {
  _AdmissionState({required this.byKey, required this.byRunId});

  factory _AdmissionState.empty() => _AdmissionState(
    byKey: <String, CockpitSupervisorRunAdmission>{},
    byRunId: <String, CockpitSupervisorRunAdmission>{},
  );

  final Map<String, CockpitSupervisorRunAdmission> byKey;
  final Map<String, CockpitSupervisorRunAdmission> byRunId;

  _AdmissionState copy() => _AdmissionState(
    byKey: Map<String, CockpitSupervisorRunAdmission>.from(byKey),
    byRunId: Map<String, CockpitSupervisorRunAdmission>.from(byRunId),
  );
}

final class _AdmissionStateCodec implements CockpitJsonCodec<_AdmissionState> {
  const _AdmissionStateCodec();

  @override
  _AdmissionState decode(Object? json) {
    if (json is! Map<Object?, Object?> ||
        json.length != 2 ||
        json['schemaVersion'] != 1 ||
        json['admissions'] is! List<Object?>) {
      throw const FormatException('Run admission store is invalid.');
    }
    final state = _AdmissionState.empty();
    for (final raw in json['admissions']! as List<Object?>) {
      final admission = CockpitSupervisorRunAdmission.fromJson(raw);
      final key = _admissionKey(
        admission.workspaceId,
        admission.idempotencyKey,
      );
      if (state.byKey.putIfAbsent(key, () => admission) != admission ||
          state.byRunId.putIfAbsent(admission.runId, () => admission) !=
              admission) {
        throw const FormatException('Run admission identity is duplicated.');
      }
    }
    return state;
  }

  @override
  Object? encode(_AdmissionState value) => <String, Object?>{
    'schemaVersion': 1,
    'admissions': value.byKey.values
        .map((admission) => admission.toJson())
        .toList(growable: false),
  };
}

String _admissionKey(String workspaceId, String idempotencyKey) =>
    '$workspaceId\u0000$idempotencyKey';

final _id = RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,255}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
