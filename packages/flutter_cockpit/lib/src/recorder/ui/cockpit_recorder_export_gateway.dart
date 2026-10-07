import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/services.dart';

/// Where the recorder panel persists an exported flow bundle.
///
/// The panel's save affordance goes through an injected gateway so hosts can
/// route YAML into their own storage (app documents, a share sheet, a remote
/// sink) without the panel knowing about any of them.
abstract interface class CockpitRecorderExportGateway {
  /// Persists [bundle] and returns the location or message to surface.
  Future<String> persist(CockpitRecordedFlowBundle bundle);
}

/// Default gateway writing the bundle's [CockpitRecordedFlowBundle.caseYaml]
/// to `<directory>/<caseId>.yaml` with `dart:io`.
///
/// The directory comes from [directoryResolver]; the default is the system
/// temp directory, which needs no permissions and no `path_provider`
/// dependency. Hosts that want a durable location inject a resolver for
/// their own directory.
final class CockpitRecorderFileExportGateway
    implements CockpitRecorderExportGateway {
  /// Creates a file-writing gateway over [directoryResolver].
  CockpitRecorderFileExportGateway({String Function()? directoryResolver})
    : _directoryResolver =
          directoryResolver ?? (() => Directory.systemTemp.path);

  final String Function() _directoryResolver;

  @override
  Future<String> persist(CockpitRecordedFlowBundle bundle) async {
    final caseId = bundle.caseDocument['id'];
    if (caseId is! String || caseId.isEmpty) {
      throw StateError('The export bundle carries no case id.');
    }
    final directory = Directory(_resolveDirectoryPath());
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$caseId.yaml');
    await file.writeAsString(bundle.caseYaml, flush: true);
    return file.path;
  }

  /// Strips trailing separators so the joined path never contains a doubled
  /// one, whatever the resolver returns.
  String _resolveDirectoryPath() {
    var path = _directoryResolver();
    while (path.endsWith(Platform.pathSeparator) && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}

/// Copies exported case YAML to the system clipboard. Used directly by the
/// panel — not a gateway implementation, because clipboard writes settle on
/// their own and need no persistence routing.
Future<void> cockpitRecorderClipboardCopy(String caseYaml) {
  return Clipboard.setData(ClipboardData(text: caseYaml));
}
