abstract interface class CockpitTestDocument {
  String get schemaVersion;

  String get kind;

  String get id;

  String? get name;

  /// Encodes this CockpitTestDocument as a JSON object.
  Map<String, Object?> toJson();
}
