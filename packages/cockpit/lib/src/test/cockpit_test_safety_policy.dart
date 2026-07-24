import 'package:cockpit_protocol/cockpit_protocol.dart';

enum CockpitTestTargetEnvironment {
  development,
  test,
  staging,
  production,
  unknown,
}

enum CockpitTestSafetyPhase { preflight, dispatch }

final class CockpitTestSafetyRequest {
  const CockpitTestSafetyRequest({
    required this.phase,
    required this.runContext,
    required this.target,
    required this.targetEnvironment,
    required this.stepId,
    required this.executionId,
    required this.action,
    required this.declaration,
    required this.isMutation,
  });

  final CockpitTestSafetyPhase phase;
  final CockpitTestRunContext runContext;
  final CockpitTestTargetRequirements target;
  final CockpitTestTargetEnvironment targetEnvironment;
  final String stepId;
  final String executionId;
  final CockpitTestAction action;
  final CockpitTestSafetyDeclaration declaration;
  final bool isMutation;
}

final class CockpitTestSafetyDecision {
  const CockpitTestSafetyDecision.allow() : allowed = true, reason = null;

  const CockpitTestSafetyDecision.deny(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

abstract interface class CockpitTestSafetyPolicy {
  Future<CockpitTestSafetyDecision> authorize(CockpitTestSafetyRequest request);
}

final class CockpitDenySensitiveSafetyPolicy
    implements CockpitTestSafetyPolicy {
  const CockpitDenySensitiveSafetyPolicy();

  @override
  Future<CockpitTestSafetyDecision> authorize(
    CockpitTestSafetyRequest request,
  ) async {
    if (request.declaration.effects.isNotEmpty) {
      return const CockpitTestSafetyDecision.deny(
        'Sensitive effects require an explicitly configured safety policy.',
      );
    }
    if (request.isMutation &&
        (request.targetEnvironment == CockpitTestTargetEnvironment.production ||
            request.targetEnvironment ==
                CockpitTestTargetEnvironment.unknown)) {
      return const CockpitTestSafetyDecision.deny(
        'Mutating actions are denied for production or unknown targets.',
      );
    }
    return const CockpitTestSafetyDecision.allow();
  }
}

final class CockpitConfiguredSafetyPolicy implements CockpitTestSafetyPolicy {
  CockpitConfiguredSafetyPolicy({
    required Iterable<CockpitTestTargetEnvironment> environments,
    Iterable<CockpitTestSafetyEffect> allowedEffects =
        const <CockpitTestSafetyEffect>[],
  }) : environments = Set<CockpitTestTargetEnvironment>.unmodifiable(
         environments,
       ),
       allowedEffects = Set<CockpitTestSafetyEffect>.unmodifiable(
         allowedEffects,
       );

  final Set<CockpitTestTargetEnvironment> environments;
  final Set<CockpitTestSafetyEffect> allowedEffects;

  @override
  Future<CockpitTestSafetyDecision> authorize(
    CockpitTestSafetyRequest request,
  ) async {
    if (!environments.contains(request.targetEnvironment)) {
      return CockpitTestSafetyDecision.deny(
        'Target environment ${request.targetEnvironment.name} is not trusted.',
      );
    }
    final denied = request.declaration.effects.difference(allowedEffects);
    if (denied.isNotEmpty) {
      return CockpitTestSafetyDecision.deny(
        'Safety effects are not authorized: '
        '${denied.map((effect) => effect.name).join(', ')}.',
      );
    }
    return const CockpitTestSafetyDecision.allow();
  }
}

bool cockpitTestActionIsMutation(CockpitTestActionKind kind) => switch (kind) {
  CockpitTestActionKind.clearNetworkActivity ||
  CockpitTestActionKind.waitForNetworkIdle ||
  CockpitTestActionKind.waitForUiIdle ||
  CockpitTestActionKind.waitFor ||
  CockpitTestActionKind.assertVisible ||
  CockpitTestActionKind.assertText ||
  CockpitTestActionKind.captureScreenshot ||
  CockpitTestActionKind.collectSnapshot => false,
  _ => true,
};

Future<CockpitTestError?> cockpitAuthorizeTestAction({
  required CockpitTestSafetyPolicy policy,
  required CockpitTestSafetyRequest request,
}) async {
  if (request.action.containsSecret &&
      !request.declaration.effects.contains(
        CockpitTestSafetyEffect.credentialSensitive,
      )) {
    return CockpitTestError(
      code: CockpitTestErrorCode.safetyDenied,
      message: 'Actions containing secrets must declare credentialSensitive.',
      stepId: request.stepId,
    );
  }
  try {
    final decision = await policy.authorize(request);
    if (decision.allowed) {
      return null;
    }
    return CockpitTestError(
      code: CockpitTestErrorCode.safetyDenied,
      message: decision.reason ?? 'Safety policy denied the action.',
      stepId: request.stepId,
    );
  } catch (_) {
    return CockpitTestError(
      code: CockpitTestErrorCode.safetyDenied,
      message: 'Safety policy failed while authorizing the action.',
      stepId: request.stepId,
    );
  }
}
