import 'package:vm_service/vm_service.dart';

import 'cockpit_vm_service_connect_io.dart'
    if (dart.library.html) 'cockpit_vm_service_connect_web.dart';

Future<VmService> connectCockpitVmService(Uri uri) =>
    connectCockpitVmServicePlatform(uri);
