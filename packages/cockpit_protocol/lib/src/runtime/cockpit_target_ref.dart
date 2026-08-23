const int _cockpitHashMask = 0xffffffff;

/// Minimum opaque token length accepted for a live Flutter target reference.
///
/// Six base-36 characters keep routine selectors compact while avoiding the
/// unsafe one- or two-character prefixes that can be reassigned after a UI
/// transition. Callers extend the prefix when the mounted target set requires
/// more characters for uniqueness.
const int cockpitTargetRefMinimumLength = 6;

/// Returns the deterministic opaque token used by short live target refs.
///
/// The token carries no application data. Callers may expose the shortest
/// unique prefix for the current mounted target set and resolve it again
/// against the live tree before executing an action.
String cockpitTargetRefToken(String registrationId) {
  var fnv = 0x811c9dc5;
  var djb = 5381;
  for (final unit in registrationId.codeUnits) {
    fnv = ((fnv ^ unit) * 0x01000193) & _cockpitHashMask;
    djb = ((djb * 33) ^ unit) & _cockpitHashMask;
  }
  return '${fnv.toRadixString(36).padLeft(7, '0')}'
      '${djb.toRadixString(36).padLeft(7, '0')}';
}

/// Whether [ref] identifies [registrationId] by token prefix.
bool cockpitTargetRefMatches(String registrationId, String ref) {
  final normalized = ref.trim().toLowerCase();
  return normalized.length >= cockpitTargetRefMinimumLength &&
      cockpitTargetRefToken(registrationId).startsWith(normalized);
}
