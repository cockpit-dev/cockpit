import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_supervisor_run_projection.dart';

abstract interface class CockpitSupervisorRunEventSource {
  Future<CockpitSupervisorEventReplay> events(String runId, int afterSequence);

  Future<CockpitRunResource> run(String runId);

  Future<int> sequenceForEventId(String runId, String eventId);
}
