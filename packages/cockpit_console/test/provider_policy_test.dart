import 'package:cockpit/cockpit.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permanent Cockpit failures are not retried', () {
    final error = CockpitApiError(
      code: CockpitErrorCode.invalidRequest,
      category: CockpitErrorCategory.invalidInput,
      message: 'Workspace does not grant active authority.',
      retryable: false,
      responsibleLayer: CockpitResponsibleLayer.supervisor,
    );

    expect(
      consoleProviderRetry(
        0,
        CockpitSupervisorClientException(
          code: error.code,
          message: error.message,
          apiError: error,
        ),
      ),
      isNull,
    );
  });

  test('transient failures receive two short retries', () {
    const error = CockpitSupervisorClientException(
      code: CockpitErrorCode.transportFailed,
      message: 'Connection closed.',
    );

    expect(consoleProviderRetry(0, error), const Duration(milliseconds: 250));
    expect(consoleProviderRetry(1, error), const Duration(milliseconds: 500));
    expect(consoleProviderRetry(2, error), isNull);
  });

  test('workspace selection retains only active authority', () {
    final active = _workspace('ws-active', CockpitWorkspaceState.active);
    final retired = _workspace('ws-retired', CockpitWorkspaceState.retired);

    expect(
      resolveActiveWorkspaceSelection(active.workspaceId, [active, retired]),
      active.workspaceId,
    );
    expect(
      resolveActiveWorkspaceSelection(retired.workspaceId, [active, retired]),
      isNull,
    );
    expect(
      resolveActiveWorkspaceSelection('ws-missing', [active, retired]),
      isNull,
    );
  });
}

CockpitWorkspaceResource _workspace(
  String workspaceId,
  CockpitWorkspaceState state,
) {
  final timestamp = DateTime.utc(2026);
  return CockpitWorkspaceResource(
    workspaceId: workspaceId,
    projectId: 'project-$workspaceId',
    checkoutId: 'checkout-$workspaceId',
    rootId: 'root-$workspaceId',
    canonicalPath: '/tmp/$workspaceId',
    filesystemIdentity: 'identity-$workspaceId',
    state: state,
    registeredAt: timestamp,
    updatedAt: timestamp,
  );
}
