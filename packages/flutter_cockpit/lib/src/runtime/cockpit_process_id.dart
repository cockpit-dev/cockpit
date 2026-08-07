import 'cockpit_process_id_stub.dart'
    if (dart.library.io) 'cockpit_process_id_io.dart';

int? cockpitCurrentProcessId() => resolveCockpitCurrentProcessId();
