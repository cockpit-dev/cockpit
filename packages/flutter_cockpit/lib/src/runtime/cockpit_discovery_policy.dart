import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cockpit_target.dart';

typedef CockpitDiscoveryElementPredicate = bool Function(Element element);
typedef CockpitDiscoveryStringExtractor = String? Function(Element element);
typedef CockpitTapHandlerResolver =
    CockpitTapHandler? Function(Element element);
typedef CockpitLongPressHandlerResolver =
    CockpitLongPressHandler? Function(Element element);
typedef CockpitDoubleTapHandlerResolver =
    CockpitDoubleTapHandler? Function(Element element);
typedef CockpitEnterTextHandlerResolver =
    CockpitEnterTextHandler? Function(Element element);
typedef CockpitTextInputHandlerResolver =
    CockpitTextInputHandler? Function(Element element);

final class CockpitDiscoveryPolicy {
  const CockpitDiscoveryPolicy({
    this.isInteractiveWidget,
    this.shouldStopTraversal,
    this.isIgnoredSubtree,
    this.isScrollableBoundary,
    this.extractText,
    this.extractSemanticId,
    this.extractTooltip,
    this.extractKey,
    this.tapHandlerForElement,
    this.longPressHandlerForElement,
    this.doubleTapHandlerForElement,
    this.enterTextHandlerForElement,
    this.textInputHandlerForElement,
  });

  factory CockpitDiscoveryPolicy.material({
    CockpitDiscoveryElementPredicate? isInteractiveWidget,
    CockpitDiscoveryElementPredicate? shouldStopTraversal,
    CockpitDiscoveryElementPredicate? isIgnoredSubtree,
    CockpitDiscoveryElementPredicate? isScrollableBoundary,
    CockpitDiscoveryStringExtractor? extractText,
    CockpitDiscoveryStringExtractor? extractSemanticId,
    CockpitDiscoveryStringExtractor? extractTooltip,
    CockpitDiscoveryStringExtractor? extractKey,
    CockpitTapHandlerResolver? tapHandlerForElement,
    CockpitLongPressHandlerResolver? longPressHandlerForElement,
    CockpitDoubleTapHandlerResolver? doubleTapHandlerForElement,
    CockpitEnterTextHandlerResolver? enterTextHandlerForElement,
    CockpitTextInputHandlerResolver? textInputHandlerForElement,
  }) {
    return CockpitDiscoveryPolicy(
      isInteractiveWidget: (element) =>
          _matchesStandardFlutterInteractiveWidget(element) ||
          (isInteractiveWidget?.call(element) ?? false),
      shouldStopTraversal: shouldStopTraversal,
      isIgnoredSubtree: isIgnoredSubtree,
      isScrollableBoundary: isScrollableBoundary,
      extractText: extractText,
      extractSemanticId: extractSemanticId,
      extractTooltip: extractTooltip,
      extractKey: extractKey,
      tapHandlerForElement: tapHandlerForElement,
      longPressHandlerForElement: longPressHandlerForElement,
      doubleTapHandlerForElement: doubleTapHandlerForElement,
      enterTextHandlerForElement: enterTextHandlerForElement,
      textInputHandlerForElement: textInputHandlerForElement,
    );
  }

  final CockpitDiscoveryElementPredicate? isInteractiveWidget;
  final CockpitDiscoveryElementPredicate? shouldStopTraversal;
  final CockpitDiscoveryElementPredicate? isIgnoredSubtree;
  final CockpitDiscoveryElementPredicate? isScrollableBoundary;
  final CockpitDiscoveryStringExtractor? extractText;
  final CockpitDiscoveryStringExtractor? extractSemanticId;
  final CockpitDiscoveryStringExtractor? extractTooltip;
  final CockpitDiscoveryStringExtractor? extractKey;
  final CockpitTapHandlerResolver? tapHandlerForElement;
  final CockpitLongPressHandlerResolver? longPressHandlerForElement;
  final CockpitDoubleTapHandlerResolver? doubleTapHandlerForElement;
  final CockpitEnterTextHandlerResolver? enterTextHandlerForElement;
  final CockpitTextInputHandlerResolver? textInputHandlerForElement;

  CockpitDiscoveryPolicy copyWith({
    CockpitDiscoveryElementPredicate? isInteractiveWidget,
    CockpitDiscoveryElementPredicate? shouldStopTraversal,
    CockpitDiscoveryElementPredicate? isIgnoredSubtree,
    CockpitDiscoveryElementPredicate? isScrollableBoundary,
    CockpitDiscoveryStringExtractor? extractText,
    CockpitDiscoveryStringExtractor? extractSemanticId,
    CockpitDiscoveryStringExtractor? extractTooltip,
    CockpitDiscoveryStringExtractor? extractKey,
    CockpitTapHandlerResolver? tapHandlerForElement,
    CockpitLongPressHandlerResolver? longPressHandlerForElement,
    CockpitDoubleTapHandlerResolver? doubleTapHandlerForElement,
    CockpitEnterTextHandlerResolver? enterTextHandlerForElement,
    CockpitTextInputHandlerResolver? textInputHandlerForElement,
  }) {
    return CockpitDiscoveryPolicy(
      isInteractiveWidget: isInteractiveWidget ?? this.isInteractiveWidget,
      shouldStopTraversal: shouldStopTraversal ?? this.shouldStopTraversal,
      isIgnoredSubtree: isIgnoredSubtree ?? this.isIgnoredSubtree,
      isScrollableBoundary: isScrollableBoundary ?? this.isScrollableBoundary,
      extractText: extractText ?? this.extractText,
      extractSemanticId: extractSemanticId ?? this.extractSemanticId,
      extractTooltip: extractTooltip ?? this.extractTooltip,
      extractKey: extractKey ?? this.extractKey,
      tapHandlerForElement: tapHandlerForElement ?? this.tapHandlerForElement,
      longPressHandlerForElement:
          longPressHandlerForElement ?? this.longPressHandlerForElement,
      doubleTapHandlerForElement:
          doubleTapHandlerForElement ?? this.doubleTapHandlerForElement,
      enterTextHandlerForElement:
          enterTextHandlerForElement ?? this.enterTextHandlerForElement,
      textInputHandlerForElement:
          textInputHandlerForElement ?? this.textInputHandlerForElement,
    );
  }

  bool matchesInteractiveWidget(Element element) {
    return isInteractiveWidget?.call(element) ?? false;
  }

  bool stopsTraversal(Element element) {
    return shouldStopTraversal?.call(element) ?? false;
  }

  bool ignoresSubtree(Element element) {
    return isIgnoredSubtree?.call(element) ?? false;
  }

  bool marksScrollableBoundary(Element element) {
    return isScrollableBoundary?.call(element) ?? false;
  }
}

bool _matchesStandardFlutterInteractiveWidget(Element element) {
  final widget = element.widget;
  return widget is ButtonStyleButton ||
      widget is IconButton ||
      widget is FloatingActionButton ||
      widget is ListTile ||
      widget is InkWell ||
      widget is GestureDetector ||
      widget is ActionChip ||
      widget is ChoiceChip ||
      widget is FilterChip ||
      widget is InputChip ||
      widget is Checkbox ||
      widget is CheckboxListTile ||
      widget is Switch ||
      widget is SwitchListTile ||
      widget is Radio ||
      widget is RadioListTile ||
      widget is Slider ||
      widget is RangeSlider ||
      widget is ToggleButtons ||
      widget is SegmentedButton<Object?> ||
      widget is TextField ||
      widget is TextFormField ||
      widget is EditableText ||
      widget is PopupMenuButton<Object?> ||
      widget is DropdownButton<Object?> ||
      widget is DropdownButtonFormField<Object?> ||
      widget is CupertinoButton ||
      widget is CupertinoListTile ||
      widget is CupertinoCheckbox ||
      widget is CupertinoSwitch ||
      widget is CupertinoRadio<Object?> ||
      widget is CupertinoSlider ||
      widget is CupertinoTextField ||
      widget is CupertinoSearchTextField ||
      widget is CupertinoSegmentedControl<Object> ||
      widget is CupertinoSlidingSegmentedControl<Object>;
}
