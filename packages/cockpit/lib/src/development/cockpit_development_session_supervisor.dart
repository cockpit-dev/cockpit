import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../bridge/cockpit_web_remote_session_bridge_server.dart';
import 'cockpit_development_session_handle.dart';
import 'cockpit_development_session_status.dart';
import 'cockpit_development_session_machine_launcher.dart';
import 'cockpit_flutter_run_machine_client.dart';
import 'cockpit_flutter_run_machine_event.dart';
import '../application/cockpit_compact_json.dart';
import '../session/cockpit_remote_session_handle.dart';

typedef CockpitRemoteReachabilityProbe = Future<bool> Function(Uri baseUri);
typedef CockpitRemoteControlReadinessProbe = Future<bool> Function(Uri baseUri);
typedef CockpitDevelopmentAppReachabilityProbe =
    Future<bool?> Function(CockpitDevelopmentSessionHandle handle);
typedef CockpitAppStopper = Future<void> Function(String appId);
typedef CockpitMachineClientConnector =
    Future<CockpitFlutterRunMachineClient> Function();
typedef CockpitSupervisorLogger = Future<void> Function(String message);
typedef CockpitVmServiceObserver = void Function(Uri uri);
typedef CockpitWebRemoteSessionBridgeServerFactory =
    CockpitWebRemoteSessionBridgeServer? Function({
      required CockpitDevelopmentSessionHandle handle,
    });

final class CockpitDevelopmentSessionSupervisor {
  CockpitDevelopmentSessionSupervisor({
    required CockpitDevelopmentSessionHandle initialHandle,
    required CockpitFlutterRunMachineClient? machineClient,
    required CockpitRemoteReachabilityProbe remoteReachabilityProbe,
    CockpitRemoteControlReadinessProbe? remoteControlReadinessProbe,
    CockpitDevelopmentAppReachabilityProbe? appReachabilityProbe,
    CockpitMachineClientConnector? machineClientConnector,
    CockpitAppStopper? appStopper,
    CockpitSupervisorLogger? logger,
    CockpitVmServiceObserver? vmServiceObserver,
    CockpitWebRemoteSessionBridgeServerFactory? webBridgeServerFactory,
    DateTime Function()? now,
    InternetAddress? bindAddress,
    int bindPort = 0,
    bool bindControlPlane = true,
    Duration settleTimeout = const Duration(seconds: 30),
    Duration? startupSettleTimeout,
    Duration settlePollInterval = const Duration(milliseconds: 500),
    Duration settleProbeTimeout = const Duration(seconds: 2),
  }) : _handle = initialHandle,
       _machineClient = machineClient,
       _remoteReachabilityProbe = remoteReachabilityProbe,
       _remoteControlReadinessProbe =
           remoteControlReadinessProbe ?? remoteReachabilityProbe,
       _appReachabilityProbe = appReachabilityProbe,
       _machineClientConnector = machineClientConnector,
       _appStopper = appStopper,
       _logger = logger,
       _vmServiceObserver = vmServiceObserver,
       _webBridgeServerFactory =
           webBridgeServerFactory ?? cockpitCreateWebRemoteSessionBridgeServer,
       _now = now ?? DateTime.now,
       _bindAddress = bindAddress ?? InternetAddress.loopbackIPv4,
       _bindPort = bindPort,
       _bindControlPlane = bindControlPlane,
       _settleTimeout = settleTimeout,
       _startupSettleTimeout = startupSettleTimeout ?? settleTimeout,
       _settlePollInterval = settlePollInterval,
       _settleProbeTimeout = settleProbeTimeout,
       _status = CockpitDevelopmentSessionStatus(
         developmentSessionId: initialHandle.developmentSessionId,
         state: CockpitDevelopmentSessionState.starting,
         appReachable: null,
         remoteSessionReachable: false,
         reloadGeneration: initialHandle.reloadGeneration,
         lastStatusAt: (now ?? DateTime.now)().toUtc(),
       );

  CockpitDevelopmentSessionHandle _handle;
  CockpitFlutterRunMachineClient? _machineClient;
  final CockpitRemoteReachabilityProbe _remoteReachabilityProbe;
  final CockpitRemoteControlReadinessProbe _remoteControlReadinessProbe;
  final CockpitDevelopmentAppReachabilityProbe? _appReachabilityProbe;
  final CockpitMachineClientConnector? _machineClientConnector;
  final CockpitAppStopper? _appStopper;
  final CockpitSupervisorLogger? _logger;
  final CockpitVmServiceObserver? _vmServiceObserver;
  final CockpitWebRemoteSessionBridgeServerFactory _webBridgeServerFactory;
  final DateTime Function() _now;
  final InternetAddress _bindAddress;
  final int _bindPort;
  final bool _bindControlPlane;
  final Duration _settleTimeout;
  final Duration _startupSettleTimeout;
  final Duration _settlePollInterval;
  final Duration _settleProbeTimeout;
  CockpitDevelopmentSessionStatus _status;
  final Completer<void> _doneCompleter = Completer<void>();
  HttpServer? _server;
  CockpitWebRemoteSessionBridgeServer? _webBridgeServer;
  StreamSubscription<CockpitFlutterRunMachineEvent>? _eventSubscription;
  StreamSubscription<HttpRequest>? _requestSubscription;
  Future<bool>? _pendingStartupSettle;
  Future<CockpitFlutterRunMachineClient>? _machineClientConnectFuture;
  bool _explicitStopRequested = false;
  bool _detachRequested = false;
  bool _controlPlaneClosed = false;
  bool _resourcesDisposed = false;
  bool _appStartedObserved = false;

  Future<void> start() async {
    if (_handle.platform == 'web') {
      final bridge = _webBridgeServerFactory(handle: _handle);
      if (bridge != null) {
        await bridge.start();
        _webBridgeServer = bridge;
        _handle = _handle.copyWith(appBaseUrl: bridge.baseUri.toString());
      }
    }
    if (_bindControlPlane) {
      _server = await HttpServer.bind(_bindAddress, _bindPort);
      _handle = _handle.copyWith(
        supervisorBaseUrl: Uri(
          scheme: 'http',
          host: _server!.address.host,
          port: _server!.port,
        ).toString(),
      );
      _requestSubscription = _server!.listen(_handleHttpRequest);
    }
    _subscribeToMachineClient(_machineClient);
    _log(
      'supervisor started control_plane=${_handle.supervisorBaseUrl} '
      'app_base=${_handle.appBaseUrl}',
    );
    _beginStartupRecovery();
  }

  Future<void> dispose() async {
    _controlPlaneClosed = true;
    await _disposeResources();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  Future<CockpitDevelopmentSessionStatus> currentStatus() async => _status;

  Future<CockpitDevelopmentSessionHandle> currentHandle() async => _handle;

  Future<void> get done => _doneCompleter.future;

  Future<CockpitDevelopmentSessionStatus> waitForStartupRecovery({
    Duration? maximumWait,
  }) async {
    final pending = _pendingStartupSettle;
    if (pending != null) {
      if (maximumWait == null) {
        await pending;
      } else {
        await Future.any<void>(<Future<void>>[
          pending.then((_) {}),
          Future<void>.delayed(maximumWait),
        ]);
      }
    }
    return _status;
  }

  Future<CockpitDevelopmentSessionStatus> refreshStartupRecovery({
    Duration maximumWait = Duration.zero,
  }) async {
    if (_status.state == CockpitDevelopmentSessionState.starting &&
        _pendingStartupSettle == null) {
      _beginStartupRecovery();
    }
    if (maximumWait <= Duration.zero) return _status;
    return waitForStartupRecovery(maximumWait: maximumWait);
  }

  Future<CockpitDevelopmentSessionStatus> refreshAppReachability() async {
    final reachable = await _probeAppReachability();
    final resolved =
        _status.state == CockpitDevelopmentSessionState.ready &&
            _status.remoteSessionReachable
        ? true
        : reachable;
    final exited = resolved == false && !_status.remoteSessionReachable;
    if (resolved != _status.appReachable ||
        (exited && _status.state != CockpitDevelopmentSessionState.failed)) {
      _setStatus(
        _status.copyWith(
          state: exited ? CockpitDevelopmentSessionState.failed : _status.state,
          appReachable: resolved,
          lastError: exited
              ? 'Application process is not running.'
              : _status.lastError,
        ),
      );
    }
    return _status;
  }

  Future<void> bindRemoteSession(
    CockpitRemoteSessionHandle remoteSessionHandle,
  ) async {
    _handle = _handle.copyWith(
      appBaseUrl: remoteSessionHandle.baseUrl,
      remoteSessionHandle: remoteSessionHandle,
    );
    _setStatus(
      _status.copyWith(
        state: CockpitDevelopmentSessionState.starting,
        lastError: null,
      ),
    );
    _log(
      'bound remote session app_id=${remoteSessionHandle.appId} '
      'base_url=${remoteSessionHandle.baseUrl}',
    );
    _beginStartupRecovery();
  }

  void bindMachineClient(CockpitFlutterRunMachineClient machineClient) {
    if (identical(_machineClient, machineClient)) {
      return;
    }
    final previousSubscription = _eventSubscription;
    if (previousSubscription != null) {
      _eventSubscription = null;
      unawaited(previousSubscription.cancel());
    }
    _machineClient = machineClient;
    _subscribeToMachineClient(machineClient);
    _log('bound machine client');
  }

  void reportStartupFailure(Object error) {
    final fallbackError = error is CockpitDevelopmentSessionFallbackException
        ? error
        : null;
    final remoteSessionHandle = fallbackError?.remoteSessionHandle;
    if (remoteSessionHandle != null) {
      _handle = _handle.copyWith(
        appBaseUrl: remoteSessionHandle.baseUrl,
        remoteSessionHandle: remoteSessionHandle,
      );
    }
    _log('startup failure error=$error');
    _setStatus(
      _status.copyWith(
        state: CockpitDevelopmentSessionState.failed,
        appReachable: remoteSessionHandle != null,
        remoteSessionReachable: remoteSessionHandle != null,
        lastError: _startupFailureMessage(error),
      ),
    );
  }

  Future<void> waitForState(
    CockpitDevelopmentSessionState state, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = _now().add(timeout);
    while (_status.state != state) {
      if (_now().isAfter(deadline)) {
        throw TimeoutException(
          'Supervisor never reached ${state.jsonValue}.',
          timeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String _startupFailureMessage(Object error) {
    if (error is CockpitDevelopmentSessionFallbackException) {
      return '[${error.code}] ${error.message}';
    }
    return '$error';
  }

  Future<CockpitDevelopmentSessionStatus> reload(
    CockpitDevelopmentReloadMode mode,
  ) async {
    final machineClient = await _requireMachineClient();
    final appId = machineClient.currentAppId ?? _handle.appId;
    _setStatus(
      _status.copyWith(
        state: mode == CockpitDevelopmentReloadMode.hotReload
            ? CockpitDevelopmentSessionState.reloading
            : CockpitDevelopmentSessionState.restarting,
        lastReloadMode: mode,
        lastError: null,
      ),
    );
    _log('reload requested mode=${mode.jsonValue}');

    try {
      switch (mode) {
        case CockpitDevelopmentReloadMode.hotReload:
          await machineClient.hotReload(appId: appId);
        case CockpitDevelopmentReloadMode.hotRestart:
          await machineClient.hotRestart(appId: appId);
      }
      final settled = await _settleReadyState(
        lastReloadMode: mode,
        bumpGeneration: true,
      );
      if (!settled) {
        throw StateError(
          _status.lastError ?? 'Remote session did not recover.',
        );
      }
      _log('reload completed mode=${mode.jsonValue}');
      return _status;
    } on Object catch (error) {
      _log('reload failed mode=${mode.jsonValue} error=$error');
      final appStillReady =
          machineClient.lastExitCode == null &&
          _status.appReachable == true &&
          _status.remoteSessionReachable;
      _setStatus(
        _status.copyWith(
          state: appStillReady
              ? CockpitDevelopmentSessionState.ready
              : _status.state == CockpitDevelopmentSessionState.failed
              ? CockpitDevelopmentSessionState.failed
              : CockpitDevelopmentSessionState.starting,
          lastReloadMode: mode,
          lastReloadSucceeded: false,
          lastError: error is StateError ? error.message : '$error',
        ),
      );
      rethrow;
    }
  }

  Future<CockpitDevelopmentSessionStatus> stop({
    bool closeControlPlane = true,
  }) async {
    _explicitStopRequested = true;
    _log('stop requested close_control_plane=$closeControlPlane');
    final remoteAppId = _handle.remoteSessionHandle?.effectivePlatformAppId;
    final machineClient = _machineClient;
    if (machineClient != null) {
      try {
        await Future.any<Object?>(<Future<Object?>>[
          machineClient.stop(
            appId: machineClient.currentAppId ?? _handle.appId,
          ),
          Future<Object?>.delayed(const Duration(milliseconds: 200)),
        ]);
      } on Object {
        // The process may already be gone.
      }
    }
    if (_appStopper != null && remoteAppId != null && remoteAppId.isNotEmpty) {
      try {
        await _appStopper.call(remoteAppId);
      } on Object {
        // Best effort desktop shutdown only.
      }
    }
    _setStatus(
      _status.copyWith(
        state: CockpitDevelopmentSessionState.stopped,
        appReachable: false,
        remoteSessionReachable: false,
      ),
    );
    if (closeControlPlane) {
      await _closeControlPlane();
    }
    return _status;
  }

  Future<void> detach() async {
    if (_controlPlaneClosed) {
      return;
    }
    _detachRequested = true;
    _log('detach requested');
    final machineClient = _machineClient;
    final appId = machineClient?.currentAppId ?? _handle.appId;
    var detached = false;
    if (machineClient != null && appId.isNotEmpty) {
      try {
        final result = await machineClient
            .detach(appId: appId)
            .timeout(const Duration(seconds: 2));
        detached = result == true;
        if (!detached) {
          _log('detach rejected by Flutter machine client');
        }
      } on Object catch (error) {
        _log('detach failed error=$error');
      }
    }
    _controlPlaneClosed = true;
    await _disposeResources(
      terminateMachineProcess: machineClient != null && appId.isEmpty,
    );
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  void _handleMachineEvent(CockpitFlutterRunMachineEvent event) {
    switch (event.kind) {
      case CockpitFlutterRunMachineEventKind.appStart:
        _appStartedObserved = true;
        final startedAppId = event.params?['appId'] as String?;
        if (startedAppId != null && startedAppId.isNotEmpty) {
          _bindMachineAppId(startedAppId);
        }
        _log('machine event app.start app_id=${startedAppId ?? _handle.appId}');
        _beginStartupRecovery();
      case CockpitFlutterRunMachineEventKind.appDebugPort:
        final wsUri = event.params?['wsUri'] as String?;
        if (wsUri != null) {
          final uri = Uri.parse(wsUri);
          _handle = _handle.copyWith(vmServiceUri: uri);
          try {
            _vmServiceObserver?.call(uri);
          } on Object {
            // Optional diagnostics must not affect Flutter machine events.
          }
        }
        _log('machine event app.debugPort ws_uri=${wsUri ?? ''}');
      case CockpitFlutterRunMachineEventKind.appStarted:
        _appStartedObserved = true;
        _log('machine event app.started');
        _beginStartupRecovery();
      case CockpitFlutterRunMachineEventKind.appStop:
        final error = event.params?['error'] as String?;
        _log('machine event app.stop error=${error ?? ''}');
        if (_detachRequested) {
          break;
        }
        if (!_explicitStopRequested &&
            _status.state == CockpitDevelopmentSessionState.starting &&
            _handle.remoteSessionHandle == null) {
          _setStatus(
            _status.copyWith(
              state: CockpitDevelopmentSessionState.starting,
              appReachable: false,
              remoteSessionReachable: false,
              lastError: error ?? _status.lastError,
            ),
          );
          break;
        }
        _setStatus(
          _status.copyWith(
            state: _explicitStopRequested
                ? CockpitDevelopmentSessionState.stopped
                : error == null
                ? CockpitDevelopmentSessionState.stopped
                : CockpitDevelopmentSessionState.failed,
            appReachable: false,
            remoteSessionReachable: false,
            lastError: error ?? _status.lastError,
          ),
        );
      case CockpitFlutterRunMachineEventKind.stderr:
        _log('machine stderr ${event.message ?? ''}');
        _setStatus(_status.copyWith(lastError: event.message));
      case CockpitFlutterRunMachineEventKind.processExit:
        _log('machine exit code=${event.exitCode?.toString() ?? ''}');
        if (_detachRequested) {
          break;
        }
        final exitError = event.exitCode == null
            ? _status.lastError
            : 'flutter run exited with code ${event.exitCode}';
        if (!_explicitStopRequested &&
            _status.state == CockpitDevelopmentSessionState.starting &&
            _handle.remoteSessionHandle == null) {
          _setStatus(
            _status.copyWith(
              state: CockpitDevelopmentSessionState.starting,
              appReachable: false,
              remoteSessionReachable: false,
              lastError: exitError,
            ),
          );
          break;
        }
        _setStatus(
          _status.copyWith(
            state: _explicitStopRequested
                ? CockpitDevelopmentSessionState.stopped
                : CockpitDevelopmentSessionState.failed,
            appReachable: false,
            remoteSessionReachable: false,
            lastError: exitError,
          ),
        );
      case CockpitFlutterRunMachineEventKind.daemonConnected:
        _log('machine event daemon.connected');
      case CockpitFlutterRunMachineEventKind.appProgress:
        if (event.message case final message? when message.isNotEmpty) {
          _log('machine progress $message');
        }
      case CockpitFlutterRunMachineEventKind.daemonLogMessage:
        if (event.message case final message? when message.isNotEmpty) {
          _log('machine log $message');
        }
      case CockpitFlutterRunMachineEventKind.stdout:
        if (event.message case final message? when message.isNotEmpty) {
          _log('machine stdout $message');
        }
      case CockpitFlutterRunMachineEventKind.request:
      case CockpitFlutterRunMachineEventKind.response:
      case CockpitFlutterRunMachineEventKind.unknown:
        break;
    }
  }

  Future<bool> _settleReadyState({
    CockpitDevelopmentReloadMode? lastReloadMode,
    required bool bumpGeneration,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _settleTimeout;
    _log(
      'settle begin '
      'mode=${lastReloadMode?.jsonValue ?? 'startup'} '
      'base_url=${_handle.baseUri} '
      'timeout_ms=${effectiveTimeout.inMilliseconds}',
    );
    final deadline = _now().add(effectiveTimeout);
    var remoteReachable = false;
    var remoteControlReady = false;
    var ready = false;
    var stableRemoteReachableChecks = 0;
    var stableRemoteControlReadyChecks = 0;

    while (!ready && _now().isBefore(deadline)) {
      remoteReachable = await _runSettleProbe(
        label: 'remote_reachability',
        probe: () => _remoteReachabilityProbe(_handle.baseUri),
      );
      stableRemoteReachableChecks = remoteReachable
          ? stableRemoteReachableChecks + 1
          : 0;
      remoteControlReady = remoteReachable
          ? await _runSettleProbe(
              label: 'remote_control_readiness',
              probe: () => _remoteControlReadinessProbe(_handle.baseUri),
            )
          : false;
      stableRemoteControlReadyChecks = remoteReachable && remoteControlReady
          ? stableRemoteControlReadyChecks + 1
          : 0;
      ready =
          stableRemoteReachableChecks >= 2 &&
          stableRemoteControlReadyChecks >= 2;
      if (!ready) {
        await Future<void>.delayed(_settlePollInterval);
      }
    }

    if (bumpGeneration && ready) {
      _handle = _handle.copyWith(
        reloadGeneration: _handle.reloadGeneration + 1,
        lastReloadAt: _now().toUtc(),
      );
    }
    final appReachability = ready ? true : await _probeAppReachability();
    final appReachable = appReachability == true;
    final appExited = appReachability == false;
    _setStatus(
      _status.copyWith(
        state: ready
            ? CockpitDevelopmentSessionState.ready
            : appExited
            ? CockpitDevelopmentSessionState.failed
            : CockpitDevelopmentSessionState.starting,
        appReachable: ready ? true : appReachability,
        remoteSessionReachable: remoteReachable,
        reloadGeneration: _handle.reloadGeneration,
        lastReloadMode: lastReloadMode ?? _status.lastReloadMode,
        lastReloadSucceeded: ready,
        lastError: ready
            ? null
            : appExited
            ? 'Application process is not running.'
            : appReachable
            ? remoteReachable && !remoteControlReady
                  ? 'Application is running and the Cockpit bridge is reachable, but control readiness is still reconnecting.'
                  : 'Application is running while the Cockpit bridge reconnects.'
            : remoteReachable && !remoteControlReady
            ? 'Cockpit bridge is reachable but control readiness is still reconnecting.'
            : 'Cockpit bridge is reconnecting; application reachability is not confirmed.',
      ),
    );
    _log(
      'settle end state=${_status.state.jsonValue} '
      'app_reachable=${_status.appReachable} '
      'remote_reachable=${_status.remoteSessionReachable} '
      'control_ready=$remoteControlReady '
      'error=${_status.lastError ?? ''}',
    );
    _pendingStartupSettle = null;
    return ready;
  }

  Future<bool?> _probeAppReachability() async {
    final machineClient = _machineClient;
    if (machineClient?.lastExitCode != null) return false;
    final probe = _appReachabilityProbe;
    if (probe != null) {
      try {
        final result = await probe(_handle).timeout(_settleProbeTimeout);
        if (result != null) return result;
      } on Object catch (error) {
        _log('app reachability probe failed error=$error');
      }
    }
    return _appStartedObserved ? true : null;
  }

  Future<bool> _runSettleProbe({
    required String label,
    required Future<bool> Function() probe,
  }) async {
    try {
      return await probe().timeout(_settleProbeTimeout);
    } on TimeoutException {
      _log(
        'settle probe timeout label=$label '
        'timeout_ms=${_settleProbeTimeout.inMilliseconds}',
      );
      return false;
    } on Object catch (error) {
      _log('settle probe failed label=$label error=$error');
      return false;
    }
  }

  Future<CockpitFlutterRunMachineClient> _requireMachineClient() async {
    final existing = _machineClient;
    if (existing != null) {
      return existing;
    }
    final connected = await _ensureMachineClientConnected(
      updateStatusOnFailure: true,
    );
    if (connected == null) {
      throw StateError('Development attach is unavailable for this session.');
    }
    return connected;
  }

  void _beginStartupRecovery() {
    if (!_canProbeRemoteSession) {
      return;
    }
    _pendingStartupSettle ??= _settleReadyState(
      bumpGeneration: false,
      timeout: _startupSettleTimeout,
    );
  }

  bool get _canProbeRemoteSession {
    return _handle.remoteSessionHandle != null;
  }

  Future<CockpitFlutterRunMachineClient?> _ensureMachineClientConnected({
    required bool updateStatusOnFailure,
  }) {
    final existing = _machineClient;
    if (existing != null) {
      return Future<CockpitFlutterRunMachineClient?>.value(existing);
    }
    final connector = _machineClientConnector;
    if (connector == null) {
      return Future<CockpitFlutterRunMachineClient?>.value(null);
    }
    final pending = _machineClientConnectFuture;
    if (pending != null) {
      return pending;
    }
    final future = connector()
        .then((client) async {
          if (_controlPlaneClosed) {
            final appId = client.currentAppId;
            var terminateMachineProcess = appId == null || appId.isEmpty;
            if (appId != null && appId.isNotEmpty) {
              try {
                await client
                    .detach(appId: appId)
                    .timeout(const Duration(seconds: 2));
                terminateMachineProcess = false;
              } on Object {
                // The supervisor is already closing; preserve the app and
                // abandon only this replacement control connection.
                terminateMachineProcess = false;
              }
            }
            await client.dispose(terminateProcess: terminateMachineProcess);
            throw StateError('Development supervisor closed during attach.');
          }
          _machineClient = client;
          _subscribeToMachineClient(client);
          _machineClientConnectFuture = null;
          return client;
        })
        .catchError((Object error) {
          _machineClientConnectFuture = null;
          if (updateStatusOnFailure) {
            _setStatus(
              _status.copyWith(
                state: CockpitDevelopmentSessionState.starting,
                lastError: '$error',
              ),
            );
          }
          throw error;
        });
    _machineClientConnectFuture = future;
    return future;
  }

  void _subscribeToMachineClient(CockpitFlutterRunMachineClient? client) {
    if (client == null || _eventSubscription != null) {
      return;
    }
    final currentAppId = client.currentAppId;
    if (currentAppId != null && currentAppId.isNotEmpty) {
      _appStartedObserved = true;
      _bindMachineAppId(currentAppId);
    }
    final currentVmServiceUri = client.currentVmServiceUri;
    if (currentVmServiceUri != null) {
      _handle = _handle.copyWith(vmServiceUri: currentVmServiceUri);
    }
    _eventSubscription = client.events.listen(_handleMachineEvent);
  }

  void _bindMachineAppId(String appId) {
    _handle = _handle.copyWith(
      appId: appId,
      remoteSessionHandle: _handle.remoteSessionHandle?.copyWith(appId: appId),
    );
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      switch ('${request.method} ${request.uri.path}') {
        case 'GET /health':
          await _writeJson(request.response, _status.toJson());
        case 'GET /status':
          await _writeJson(request.response, <String, Object?>{
            'status': _status.toJson(),
            'handle': _handle.toJson(),
          });
        case 'POST /reload':
          final payload = await _readJsonBody(request);
          final mode = CockpitDevelopmentReloadMode.fromJson(
            payload['mode'] ?? 'hot_reload',
          );
          final status = await reload(mode);
          await _writeJson(request.response, <String, Object?>{
            'status': status.toJson(),
            'handle': _handle.toJson(),
          });
        case 'POST /restart':
          final status = await reload(CockpitDevelopmentReloadMode.hotRestart);
          await _writeJson(request.response, <String, Object?>{
            'status': status.toJson(),
            'handle': _handle.toJson(),
          });
        case 'POST /stop':
          final status = await stop(closeControlPlane: false);
          await _writeJson(request.response, <String, Object?>{
            'status': status.toJson(),
            'handle': _handle.toJson(),
          });
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 50),
            ).then((_) => _closeControlPlane()),
          );
        default:
          request.response.statusCode = HttpStatus.notFound;
          await _writeJson(request.response, <String, Object?>{
            'error': 'not_found',
          });
      }
    } catch (error) {
      _log('http ${request.method} ${request.uri.path} failed error=$error');
      request.response.statusCode = HttpStatus.internalServerError;
      await _writeJson(request.response, <String, Object?>{'error': '$error'});
    } finally {
      await request.response.close();
    }
  }

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    final payload = await utf8.decoder.bind(request).join();
    if (payload.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(payload);
    if (decoded is! Map<Object?, Object?>) {
      throw StateError('Supervisor request body must be a JSON object.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, Object?> payload,
  ) async {
    response.headers.contentType = ContentType.json;
    response.write(cockpitCompactJsonText(payload));
  }

  void _setStatus(CockpitDevelopmentSessionStatus status) {
    if (_status != status) {
      _log(
        'status ${_status.state.jsonValue} -> ${status.state.jsonValue} '
        'app=${status.appReachable} remote=${status.remoteSessionReachable} '
        'reload_generation=${status.reloadGeneration} '
        'error=${status.lastError ?? ''}',
      );
    }
    _status = status.copyWith(lastStatusAt: _now().toUtc());
  }

  Future<void> _closeControlPlane() async {
    if (_controlPlaneClosed) {
      return;
    }
    _controlPlaneClosed = true;
    await _disposeResources();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  Future<void> _disposeResources({bool terminateMachineProcess = true}) async {
    if (_resourcesDisposed) {
      return;
    }
    _resourcesDisposed = true;
    await _eventSubscription?.cancel();
    await _requestSubscription?.cancel();
    await _server?.close(force: true);
    await _webBridgeServer?.close();
    await _machineClient?.dispose(terminateProcess: terminateMachineProcess);
  }

  void _log(String message) {
    final logger = _logger;
    if (logger == null) {
      return;
    }
    unawaited(logger(message));
  }
}
