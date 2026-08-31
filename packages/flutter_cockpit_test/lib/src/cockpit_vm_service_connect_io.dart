import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service/utils.dart';

Future<VmService> connectCockpitVmServicePlatform(Uri uri) =>
    vmServiceConnectUri(
      convertToWebSocketUrl(serviceProtocolUrl: uri).toString(),
    );
