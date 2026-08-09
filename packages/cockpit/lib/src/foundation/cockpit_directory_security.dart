final class CockpitDirectorySecurity {
  const CockpitDirectorySecurity({
    required this.posixApplicable,
    required this.ownerVerified,
    required this.unsafeWritable,
    bool? ownerTrusted,
    this.mode,
  }) : ownerTrusted = ownerTrusted ?? ownerVerified;

  final bool posixApplicable;
  final bool ownerVerified;
  final bool ownerTrusted;
  final bool unsafeWritable;
  final int? mode;
}

abstract interface class CockpitWindowsSecurityProvider {
  Future<CockpitDirectorySecurity> inspect(String canonicalPath);
}
