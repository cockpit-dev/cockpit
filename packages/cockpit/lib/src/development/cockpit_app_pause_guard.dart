import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../application/cockpit_application_service_exception.dart';
import 'cockpit_vm_network_profiler.dart' show CockpitVmServiceConnector;

/// Fails fast when the app behind a development session is paused at a
/// debugger.
///
/// Interactive and remote operations are served by an HTTP control plane that
/// runs on the app's root isolate. While that isolate is paused the control
/// plane stops responding, so every dial burns its full transport budget and
/// surfaces as an opaque timeout. The VM service stays responsive while the
/// app is paused, which makes it the authoritative pre-flight check: when the
/// isolate hosting the control plane is hard-paused, [ensureRunning] rejects
/// the operation with a structured `appPaused` error that names the recovery
/// path instead of entering the hung call.
abstract interface class CockpitAppPauseGuard {
  /// Throws [CockpitApplicationServiceException] with code `appPaused` when
  /// the app is paused. Never throws for any other reason: probe failures
  /// (unreachable VM service, probe timeout, release builds without a
  /// service) fail open and leave the operation's existing failure mode in
  /// place.
  Future<void> ensureRunning({required Uri vmServiceUri});
}

final class CockpitVmAppPauseGuard implements CockpitAppPauseGuard {
  CockpitVmAppPauseGuard({
    CockpitVmServiceConnector? connect,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _connect = connect ?? _defaultConnect;

  /// Pause kinds that freeze the app's control plane. `PauseStart` is the
  /// normal pre-`main` launch pause and `PausePostRequest` is a transient
  /// VM service evaluation state, so neither blocks operations.
  static const Set<String> _hardPauseKinds = <String>{
    EventKind.kPauseBreakpoint,
    EventKind.kPauseInterrupted,
    EventKind.kPauseException,
    EventKind.kPauseExit,
  };

  /// The engine-named root isolate of a Flutter application; it hosts the
  /// in-app control plane.
  static const String _rootIsolateName = 'main';

  /// Isolates that never host the control plane: the target VM's own service
  /// isolate and the DDS proxy isolate.
  static const Set<String> _infrastructureIsolateNames = <String>{
    'vm-service',
    'dds',
  };

  final CockpitVmServiceConnector _connect;
  final Duration probeTimeout;

  @override
  Future<void> ensureRunning({required Uri vmServiceUri}) async {
    final String? pausedKind;
    try {
      pausedKind = await _pausedKind(vmServiceUri).timeout(probeTimeout);
    } on Object {
      // The guard is a fast-path diagnostic. When the pause state cannot be
      // determined, proceed and keep the existing timeout failure mode.
      return;
    }
    if (pausedKind == null) return;
    throw CockpitApplicationServiceException(
      code: 'appPaused',
      message:
          'The app isolate is paused ($pausedKind), so the in-app control '
          'plane cannot answer. Resume the isolate (for example '
          '`dartq debug resume` or the debugger\'s resume control) or run '
          '`cockpit dev restart`, then retry.',
      details: <String, Object?>{'pauseKind': pausedKind},
    );
  }

  /// Returns the pause kind of the isolate that hosts the app's control
  /// plane, or `null` when that isolate is runnable or cannot be identified.
  ///
  /// The control plane runs on the app's root isolate (`main`). Background
  /// worker isolates — drift databases, `Isolate.run` pools — routinely keep
  /// running while the root isolate is paused at a debugger, so they must
  /// not keep the guard silent, and a paused worker must not block a healthy
  /// root isolate either.
  Future<String?> _pausedKind(Uri vmServiceUri) async {
    final service = await _connect(vmServiceUri);
    try {
      final vm = await service.getVM();
      final rootIsolateId = _rootIsolateId(vm.isolates ?? const <IsolateRef>[]);
      if (rootIsolateId == null) return null;
      final kind = await service
          .getIsolate(rootIsolateId)
          .then((isolate) => isolate.pauseEvent?.kind);
      return kind != null && _hardPauseKinds.contains(kind) ? kind : null;
    } finally {
      await service.dispose();
    }
  }

  /// Flutter's root isolate is engine-named `main`; plain Dart entrypoints
  /// fall back to the first user isolate because the root isolate is always
  /// created before any worker it spawns.
  String? _rootIsolateId(List<IsolateRef> isolates) {
    for (final isolate in isolates) {
      if (isolate.id != null && isolate.name == _rootIsolateName) {
        return isolate.id;
      }
    }
    for (final isolate in isolates) {
      if (isolate.id != null &&
          !_infrastructureIsolateNames.contains(isolate.name)) {
        return isolate.id;
      }
    }
    return null;
  }

  static Future<VmService> _defaultConnect(Uri uri) {
    return vmServiceConnectUri(uri.toString());
  }
}
