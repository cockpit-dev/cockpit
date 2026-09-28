import 'package:flutter/material.dart';

/// Reads the standard app settings every Flutter app already publishes
/// through its widget tree, so `describeApp` answers locale, theme, and
/// layout questions even when the application wires no [appStateProvider].
///
/// The walk starts at the [FlutterCockpitRoot] element, which sits above the
/// application's `MaterialApp`, and descends until it has seen the first
/// (outermost, application-level) `Localizations` and `Theme`. Text scale
/// comes from the enclosing `MediaQuery`, which the framework provides above
/// the root. Values are read on demand at command time, so they always
/// describe the live tree.
Map<String, Object?> cockpitDerivedAppState(Element rootElement) {
  Locale? locale;
  ThemeData? theme;

  var visited = 0;
  void visit(Element element) {
    if (locale != null && theme != null) return;
    if (visited >= _maximumVisitedElements) return;
    visited += 1;
    final widget = element.widget;
    if (widget is Localizations) {
      locale ??= widget.locale;
    } else if (widget is Theme) {
      theme ??= widget.data;
    }
    element.visitChildren(visit);
  }

  rootElement.visitChildren(visit);

  final mediaQuery = MediaQuery.maybeOf(rootElement);
  final effectiveTheme = theme;
  return <String, Object?>{
    if (locale case final value?) 'locale': value.toString(),
    if (effectiveTheme case final value?) 'brightness': value.brightness.name,
    if (effectiveTheme case final value?)
      'themeColor': _themeColorHex(value.colorScheme.primary),
    if (effectiveTheme case final value?) 'platform': value.platform.name,
    if (mediaQuery case final value?) 'textScale': value.textScaler.scale(1.0),
  };
}

const int _maximumVisitedElements = 2000;

String _themeColorHex(Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${rgb.toUpperCase()}';
}
