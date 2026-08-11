import 'package:flutter/services.dart';

final class CockpitKeyEventRequest {
  const CockpitKeyEventRequest({
    required this.logicalKey,
    this.physicalKey,
    this.character,
  });

  factory CockpitKeyEventRequest.fromJson(Map<String, Object?> json) {
    final logical = _requireLogicalKey(json['logicalKey']);
    return CockpitKeyEventRequest(
      logicalKey: logical,
      physicalKey:
          _maybePhysicalKey(json['physicalKey']) ??
          _maybePhysicalKey(json['logicalKey']),
      character: json['character'] as String?,
    );
  }

  final LogicalKeyboardKey logicalKey;
  final PhysicalKeyboardKey? physicalKey;
  final String? character;

  Map<String, Object?> toJson() => <String, Object?>{
    'logicalKey': logicalKey.debugName ?? logicalKey.keyLabel,
    if (physicalKey != null) 'physicalKey': physicalKey!.debugName,
    if (character != null) 'character': character,
  };

  static LogicalKeyboardKey _requireLogicalKey(Object? raw) {
    final resolved = _maybeLogicalKey(raw);
    if (resolved == null) {
      throw ArgumentError.value(
        raw,
        'logicalKey',
        'Unsupported logical key. Use a known Flutter logical key name or keyId.',
      );
    }
    return resolved;
  }

  static LogicalKeyboardKey? _maybeLogicalKey(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is LogicalKeyboardKey) {
      return raw;
    }
    if (raw is num) {
      return LogicalKeyboardKey.findKeyByKeyId(raw.toInt()) ??
          LogicalKeyboardKey(raw.toInt());
    }
    if (raw is String) {
      final trimmed = raw.trim().toLowerCase();
      if (trimmed.isEmpty) {
        return null;
      }
      if (trimmed.startsWith('0x')) {
        final keyId = int.tryParse(trimmed.substring(2), radix: 16);
        if (keyId != null) {
          return LogicalKeyboardKey.findKeyByKeyId(keyId) ??
              LogicalKeyboardKey(keyId);
        }
      }
      final normalized = _normalizeKeyName(trimmed);
      for (final key in LogicalKeyboardKey.knownLogicalKeys) {
        final debugName = _normalizeKeyName(key.debugName);
        if (debugName == normalized) {
          return key;
        }
        final label = _normalizeKeyName(key.keyLabel);
        if (label.isNotEmpty && label == normalized) {
          return key;
        }
      }
    }
    return null;
  }

  static PhysicalKeyboardKey? _maybePhysicalKey(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is PhysicalKeyboardKey) {
      return raw;
    }
    if (raw is num) {
      return PhysicalKeyboardKey.findKeyByCode(raw.toInt()) ??
          PhysicalKeyboardKey(raw.toInt());
    }
    if (raw is String) {
      final trimmed = raw.trim().toLowerCase();
      if (trimmed.isEmpty) {
        return null;
      }
      if (trimmed.startsWith('0x')) {
        final usage = int.tryParse(trimmed.substring(2), radix: 16);
        if (usage != null) {
          return PhysicalKeyboardKey.findKeyByCode(usage) ??
              PhysicalKeyboardKey(usage);
        }
      }
      final normalized = _normalizeKeyName(trimmed);
      for (final key in PhysicalKeyboardKey.knownPhysicalKeys) {
        final debugName = _normalizeKeyName(key.debugName);
        if (debugName == normalized) {
          return key;
        }
      }
    }
    return null;
  }

  static String _normalizeKeyName(String? value) {
    return value?.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '') ?? '';
  }
}
