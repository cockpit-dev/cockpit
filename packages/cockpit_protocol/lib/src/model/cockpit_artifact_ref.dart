final class CockpitArtifactRef {
  /// Creates a CockpitArtifactRef.
  const CockpitArtifactRef({required this.role, required this.relativePath});

  final String role;
  final String relativePath;

  /// Encodes this CockpitArtifactRef as a JSON object.
  Map<String, Object?> toJson() => {'role': role, 'relativePath': relativePath};

  /// Decodes a CockpitArtifactRef from a JSON object.
  factory CockpitArtifactRef.fromJson(Map<String, Object?> json) {
    return CockpitArtifactRef(
      role: json['role']! as String,
      relativePath: json['relativePath']! as String,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitArtifactRef &&
            other.role == role &&
            other.relativePath == relativePath;
  }

  @override
  int get hashCode => Object.hash(role, relativePath);
}
