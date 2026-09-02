import '../application/cockpit_list_launch_targets_service.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';

/// Selects one Flutter device after machine discovery.
///
/// Selection is deliberately strict: a host platform is never preferred over
/// a connected simulator or physical device. Callers may omit filters only
/// when discovery returned exactly one candidate.
CockpitLaunchTarget cockpitSelectFlutterDevice(
  Iterable<CockpitLaunchTarget> discovered, {
  String? deviceId,
  String? platform,
}) {
  final requestedDevice = _normalized(deviceId);
  final requestedPlatform = _normalized(platform);
  final candidates = discovered
      .where(
        (target) =>
            (requestedDevice == null || target.id == requestedDevice) &&
            (requestedPlatform == null || target.platform == requestedPlatform),
      )
      .toList(growable: false);

  if (candidates.length == 1) return candidates.single;

  final filter = <String>[
    if (requestedPlatform != null) 'platform $requestedPlatform',
    if (requestedDevice != null) 'device $requestedDevice',
  ].join(', ');
  if (candidates.isEmpty) {
    final suffix = filter.isEmpty ? '' : ' for $filter';
    throw CockpitSupervisorClientException(
      code: 'deviceNotFound',
      message:
          'No Flutter device matched$suffix. Run `cockpit target discover`, '
          'connect or boot the intended device, then pass its exact id with '
          '`cockpit dev start --device <id>`.',
    );
  }

  final rows = candidates.take(12).map(_describe).join('; ');
  final omitted = candidates.length > 12 ? '; ...' : '';
  throw CockpitSupervisorClientException(
    code: 'deviceAmbiguous',
    message:
        'Multiple Flutter devices are available. Run `cockpit target discover` '
        'and choose one exact id; never rely on a platform default. '
        'Available: $rows$omitted. Then run '
        '`cockpit dev start --device <id>`.',
  );
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _describe(CockpitLaunchTarget target) {
  final kind = target.emulator
      ? 'emulator'
      : target.ephemeral
      ? 'temporary'
      : 'device';
  final sdk = target.sdk == null || target.sdk!.trim().isEmpty
      ? ''
      : ', ${target.sdk}';
  return '${target.id} (${target.name}, ${target.platform}, $kind$sdk)';
}
