import 'package:cockpit_protocol/cockpit_protocol.dart';

void main() {
  final viewport = CockpitViewportResizeRequest.fromJson(
    const <String, Object?>{'width': 800, 'height': 600},
  );
  final failedRequests = CockpitNetworkQuery(
    onlyFailures: true,
    uriContains: '/api/',
  );

  print(viewport.toJson());
  print(failedRequests.toJson());
}
