import 'package:collection/collection.dart';

enum CockpitTextInputAction {
  done,
  next,
  previous,
  search,
  send,
  go,
  newline,
  none,
  unspecified,
  continueAction,
  emergencyCall,
  join,
  route;

  static CockpitTextInputAction? maybeFromJson(Object? json) {
    if (json == null) {
      return null;
    }
    if (json is CockpitTextInputAction) {
      return json;
    }
    if (json is String) {
      final normalized = json.trim();
      if (normalized.isEmpty) {
        return null;
      }
      for (final value in values) {
        if (value.name.toLowerCase() == normalized.toLowerCase()) {
          return value;
        }
      }
    }
    return null;
  }
}

final class CockpitTextInputRequest {
  /// Creates a CockpitTextInputRequest.
  const CockpitTextInputRequest({
    this.text,
    this.selectionBase,
    this.selectionExtent,
    this.composingBase,
    this.composingExtent,
    this.inputAction,
    this.requestFocus = true,
    this.clearExisting = false,
  });

  final String? text;
  final int? selectionBase;
  final int? selectionExtent;

  /// UTF-16 composing range used by IMEs and platform text input.
  ///
  /// A collapsed or invalid range means that composing text is not active.
  final int? composingBase;
  final int? composingExtent;
  final CockpitTextInputAction? inputAction;
  final bool requestFocus;
  final bool clearExisting;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  bool get hasEditingMutation =>
      text != null ||
      clearExisting ||
      selectionBase != null ||
      selectionExtent != null ||
      composingBase != null ||
      composingExtent != null;

  /// Encodes this CockpitTextInputRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'selectionBase': selectionBase,
    'selectionExtent': selectionExtent,
    'composingBase': composingBase,
    'composingExtent': composingExtent,
    'inputAction': inputAction?.name,
    'requestFocus': requestFocus,
    'clearExisting': clearExisting,
  };

  /// Decodes a CockpitTextInputRequest from a JSON object.
  factory CockpitTextInputRequest.fromJson(Map<String, Object?> json) {
    return CockpitTextInputRequest(
      text: json['text'] as String?,
      selectionBase: json['selectionBase'] as int?,
      selectionExtent: json['selectionExtent'] as int?,
      composingBase: json['composingBase'] as int?,
      composingExtent: json['composingExtent'] as int?,
      inputAction: CockpitTextInputAction.maybeFromJson(json['inputAction']),
      requestFocus: json['requestFocus'] as bool? ?? true,
      clearExisting: json['clearExisting'] as bool? ?? false,
    );
  }

  /// Returns a copy of this CockpitTextInputRequest with supplied fields replaced.
  CockpitTextInputRequest copyWith({
    String? text,
    int? selectionBase,
    int? selectionExtent,
    int? composingBase,
    int? composingExtent,
    CockpitTextInputAction? inputAction,
    bool? requestFocus,
    bool? clearExisting,
    bool clearText = false,
    bool clearSelectionBase = false,
    bool clearSelectionExtent = false,
    bool clearComposingBase = false,
    bool clearComposingExtent = false,
    bool clearInputAction = false,
  }) {
    return CockpitTextInputRequest(
      text: clearText ? null : (text ?? this.text),
      selectionBase: clearSelectionBase
          ? null
          : (selectionBase ?? this.selectionBase),
      selectionExtent: clearSelectionExtent
          ? null
          : (selectionExtent ?? this.selectionExtent),
      composingBase: clearComposingBase
          ? null
          : (composingBase ?? this.composingBase),
      composingExtent: clearComposingExtent
          ? null
          : (composingExtent ?? this.composingExtent),
      inputAction: clearInputAction ? null : (inputAction ?? this.inputAction),
      requestFocus: requestFocus ?? this.requestFocus,
      clearExisting: clearExisting ?? this.clearExisting,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitTextInputRequest &&
            _mapEquality.equals(other.toJson(), toJson());
  }

  @override
  int get hashCode => _mapEquality.hash(toJson());
}
