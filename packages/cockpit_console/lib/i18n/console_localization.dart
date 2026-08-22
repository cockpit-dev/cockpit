import 'strings.g.dart';

/// Configures locale-specific behavior before the application starts.
Future<void> initializeConsoleLocalization() async {
  await LocaleSettings.setPluralResolver(
    locale: AppLocale.zhCn,
    cardinalResolver: _resolveChineseCardinal,
  );
  await LocaleSettings.useDeviceLocale();
}

String _resolveChineseCardinal(
  num _, {
  String? zero,
  String? one,
  String? two,
  String? few,
  String? many,
  String? other,
}) {
  final value = other ?? one ?? zero ?? two ?? few ?? many;
  if (value == null) {
    throw StateError('A Chinese cardinal translation must define a value.');
  }
  return value;
}
