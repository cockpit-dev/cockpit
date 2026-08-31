import 'package:vm_service/vm_service.dart';

Future<VmService> connectCockpitVmServicePlatform(Uri uri) =>
    Future<VmService>.error(
      UnsupportedError('The VM service is unavailable on web.'),
    );
