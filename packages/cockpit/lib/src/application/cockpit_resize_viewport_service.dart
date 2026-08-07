import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_interactive_session_lock.dart';

typedef CockpitRemoteViewportResize =
    Future<CockpitViewportResizeResult> Function(
      Uri baseUri,
      CockpitViewportResizeRequest request,
    );

final class CockpitResizeViewportRequest {
  const CockpitResizeViewportRequest({
    required this.app,
    required this.width,
    required this.height,
  });

  final CockpitAppHandle app;
  final int width;
  final int height;
}

final class CockpitResizeViewportService {
  CockpitResizeViewportService({
    CockpitRemoteViewportResize? resize,
    CockpitInteractiveSessionLock? sessionLock,
  }) : _resize =
           resize ??
           ((baseUri, request) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).resizeViewport(request)),
       _sessionLock = sessionLock ?? CockpitInteractiveSessionLock();

  final CockpitRemoteViewportResize _resize;
  final CockpitInteractiveSessionLock _sessionLock;

  Future<CockpitViewportResizeResult> resize(
    CockpitResizeViewportRequest request,
  ) {
    final resizeRequest = CockpitViewportResizeRequest(
      width: request.width,
      height: request.height,
    );
    return _sessionLock.run(
      request.app.baseUrl,
      () => _resize(request.app.baseUri, resizeRequest),
    );
  }
}
