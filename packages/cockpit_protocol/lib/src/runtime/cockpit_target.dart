import 'dart:async';

import 'package:collection/collection.dart';

import '../control/cockpit_command_type.dart';
import 'cockpit_control_state.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_target_geometry.dart';
import 'cockpit_text_input_request.dart';

typedef CockpitTapHandler = FutureOr<void> Function();
typedef CockpitLongPressHandler = FutureOr<void> Function();
typedef CockpitDoubleTapHandler = FutureOr<void> Function();
typedef CockpitEnterTextHandler = FutureOr<void> Function(String text);
typedef CockpitTextInputHandler =
    FutureOr<void> Function(CockpitTextInputRequest request);
typedef CockpitSemanticActionHandler = FutureOr<void> Function();
typedef CockpitDiagnosticNodeProvider = Object? Function();
typedef CockpitTargetGeometryProvider = CockpitTargetGeometry? Function();

final class CockpitTarget {
  /// Creates a CockpitTarget.
  const CockpitTarget({
    required this.registrationId,
    this.cockpitId,
    this.semanticId,
    this.keyValue,
    this.text,
    this.textParts = const <String>{},
    this.tooltip,
    this.typeName,
    this.path,
    this.scrollablePath,
    this.scrollableKeyValue,
    this.scrollableTypeName,
    required this.routeName,
    this.isVisible = true,
    this.supportedCommands = const <CockpitCommandType>{},
    this.control,
    this.locatorAncestors = const <CockpitSnapshotAncestor>[],
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.onEnterText,
    this.onTextInput,
    this.onSemanticTap,
    this.onSemanticLongPress,
    this.onSemanticEnterText,
    this.onSemanticTextInput,
    this.onSemanticShowOnScreen,
    this.onSemanticIncrease,
    this.onSemanticDecrease,
    this.onSemanticDismiss,
    this.diagnosticNodeProvider,
    this.geometryProvider,
  });

  final String registrationId;
  final String? cockpitId;
  final String? semanticId;
  final String? keyValue;
  final String? text;
  final Set<String> textParts;
  final String? tooltip;
  final String? typeName;
  final String? path;
  final String? scrollablePath;
  final String? scrollableKeyValue;
  final String? scrollableTypeName;
  final String routeName;
  final bool isVisible;
  final Set<CockpitCommandType> supportedCommands;
  final CockpitControlState? control;
  final List<CockpitSnapshotAncestor> locatorAncestors;
  final CockpitTapHandler? onTap;
  final CockpitLongPressHandler? onLongPress;
  final CockpitDoubleTapHandler? onDoubleTap;
  final CockpitEnterTextHandler? onEnterText;
  final CockpitTextInputHandler? onTextInput;
  final CockpitTapHandler? onSemanticTap;
  final CockpitLongPressHandler? onSemanticLongPress;
  final CockpitEnterTextHandler? onSemanticEnterText;
  final CockpitTextInputHandler? onSemanticTextInput;
  final CockpitSemanticActionHandler? onSemanticShowOnScreen;
  final CockpitSemanticActionHandler? onSemanticIncrease;
  final CockpitSemanticActionHandler? onSemanticDecrease;
  final CockpitSemanticActionHandler? onSemanticDismiss;
  final CockpitDiagnosticNodeProvider? diagnosticNodeProvider;
  final CockpitTargetGeometryProvider? geometryProvider;

  static const SetEquality<CockpitCommandType> _commandSetEquality =
      SetEquality<CockpitCommandType>();
  static const SetEquality<String> _textPartSetEquality = SetEquality<String>();

  String? get displayLabel =>
      cockpitId ?? semanticId ?? text ?? tooltip ?? keyValue ?? typeName;

  CockpitSnapshotTarget toSnapshotTarget() {
    return CockpitSnapshotTarget(
      registrationId: registrationId,
      cockpitId: cockpitId,
      semanticId: semanticId,
      keyValue: keyValue,
      text: text,
      textParts: textParts.toList(growable: false),
      tooltip: tooltip,
      typeName: typeName,
      path: path,
      scrollablePath: scrollablePath,
      scrollableKeyValue: scrollableKeyValue,
      scrollableTypeName: scrollableTypeName,
      routeName: routeName,
      supportedCommands: supportedCommands.toList(growable: false),
      control: control,
      ancestors: locatorAncestors,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitTarget &&
            other.registrationId == registrationId &&
            other.cockpitId == cockpitId &&
            other.semanticId == semanticId &&
            other.keyValue == keyValue &&
            other.text == text &&
            _textPartSetEquality.equals(other.textParts, textParts) &&
            other.tooltip == tooltip &&
            other.typeName == typeName &&
            other.path == path &&
            other.scrollablePath == scrollablePath &&
            other.scrollableKeyValue == scrollableKeyValue &&
            other.scrollableTypeName == scrollableTypeName &&
            other.routeName == routeName &&
            other.isVisible == isVisible &&
            other.control == control &&
            other.diagnosticNodeProvider == diagnosticNodeProvider &&
            _commandSetEquality.equals(
              other.supportedCommands,
              supportedCommands,
            );
  }

  @override
  int get hashCode => Object.hash(
    registrationId,
    cockpitId,
    semanticId,
    keyValue,
    text,
    _textPartSetEquality.hash(textParts),
    tooltip,
    typeName,
    path,
    scrollablePath,
    scrollableKeyValue,
    scrollableTypeName,
    routeName,
    isVisible,
    control,
    diagnosticNodeProvider,
    _commandSetEquality.hash(supportedCommands),
  );
}
