import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('theme toggle always inverts the effective brightness', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themeProvider.notifier);

    notifier.set(ThemeMode.system);
    notifier.toggle(Brightness.dark);
    expect(container.read(themeProvider), ThemeMode.light);

    notifier.set(ThemeMode.system);
    notifier.toggle(Brightness.light);
    expect(container.read(themeProvider), ThemeMode.dark);
  });

  test('interactive theme geometry uses rounded superellipses', () {
    final theme = ConsoleTheme.build(Brightness.dark);
    final inputBorder = theme.inputDecorationTheme.border;
    final buttonShape = theme.filledButtonTheme.style?.shape?.resolve(
      const <WidgetState>{},
    );

    expect(inputBorder, isA<ShapedInputBorder>());
    expect(
      (inputBorder! as ShapedInputBorder).shape,
      isA<RoundedSuperellipseBorder>(),
    );
    expect(buttonShape, isA<RoundedSuperellipseBorder>());
  });

  test('button states resolve correctly in light and dark themes', () {
    for (final brightness in Brightness.values) {
      final colors = ConsoleColors(brightness);
      final theme = ConsoleTheme.build(brightness);
      final filled = theme.filledButtonTheme.style!;
      final outlined = theme.outlinedButtonTheme.style!;
      final text = theme.textButtonTheme.style!;

      expect(
        filled.backgroundColor?.resolve(const <WidgetState>{}),
        colors.action,
      );
      expect(
        filled.backgroundColor?.resolve(const <WidgetState>{
          WidgetState.hovered,
        }),
        colors.actionHover,
      );
      expect(
        filled.backgroundColor?.resolve(const <WidgetState>{
          WidgetState.pressed,
        }),
        colors.actionActive,
      );
      expect(
        filled.foregroundColor?.resolve(const <WidgetState>{}),
        colors.actionFg,
      );
      expect(
        outlined.side?.resolve(const <WidgetState>{WidgetState.focused}),
        BorderSide(color: colors.borderFocus, width: 1.5),
      );
      expect(
        text.overlayColor?.resolve(const <WidgetState>{WidgetState.focused}),
        colors.accentSubtle,
      );
    }
  });

  test('semantic text colors stay readable in light and dark themes', () {
    for (final brightness in Brightness.values) {
      final colors = ConsoleColors(brightness);

      expect(
        _contrast(colors.inkPrimary, colors.surface1),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness primary text',
      );
      expect(
        _contrast(colors.inkSecondary, colors.surface1),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness secondary text',
      );
      expect(
        _contrast(colors.inkTertiary, colors.surface1),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness tertiary and placeholder text',
      );
      expect(
        _contrast(colors.inkDisabled, colors.surface3),
        greaterThanOrEqualTo(3),
        reason: '$brightness disabled control content',
      );
      expect(
        _contrast(colors.accent, colors.accentFg),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness accent foreground',
      );
      expect(
        _contrast(colors.action, colors.actionFg),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness primary action',
      );
      expect(
        _contrast(colors.actionHover, colors.actionFg),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness hovered primary action',
      );
    }
  });

  testWidgets('single-line form controls use the shared control height', (
    tester,
  ) async {
    const textKey = ValueKey('text');
    const plainTextKey = ValueKey('plain-text');
    const dropdownKey = ValueKey('dropdown');
    const plainDropdownKey = ValueKey('plain-dropdown');
    const valueKey = ValueKey('value');
    const filledButtonKey = ValueKey('filled-button');
    const outlinedButtonKey = ValueKey('outlined-button');

    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.build(Brightness.dark),
        home: Scaffold(
          body: Column(
            children: [
              const ConsoleTextField(
                key: textKey,
                label: 'Project directory',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              const ConsoleTextField(key: plainTextKey),
              ConsoleDropdownField<String>(
                key: dropdownKey,
                initialValue: 'project',
                label: 'Allowed folder',
                prefixIcon: const Icon(Icons.folder_outlined),
                items: const [
                  DropdownMenuItem(value: 'project', child: Text('Project')),
                ],
                onChanged: (_) {},
              ),
              ConsoleDropdownField<String>(
                key: plainDropdownKey,
                initialValue: 'project',
                items: const [
                  DropdownMenuItem(value: 'project', child: Text('Project')),
                ],
                onChanged: (_) {},
              ),
              const ConsoleFieldValue(
                key: valueKey,
                label: 'Suite contents',
                child: Text('All cases in this suite'),
              ),
              FilledButton(
                key: filledButtonKey,
                onPressed: () {},
                child: const Text('Add project'),
              ),
              OutlinedButton(
                key: outlinedButtonKey,
                onPressed: () {},
                child: const Text('Find apps'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(plainTextKey)).height,
      ConsoleControlStyle.height,
    );
    expect(
      tester.getSize(find.byKey(plainDropdownKey)).height,
      ConsoleControlStyle.height,
    );
    for (final entry in <String, Key>{
      'filled button': filledButtonKey,
      'outlined button': outlinedButtonKey,
    }.entries) {
      expect(
        tester.getSize(find.byKey(entry.value)).height,
        ConsoleControlStyle.height,
        reason: entry.key,
      );
    }

    final visibleFieldSurfaces = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.foregroundPainter.runtimeType.toString() ==
              '_InputBorderPainter',
    );
    expect(visibleFieldSurfaces, findsNWidgets(5));
    expect([
      for (var index = 0; index < 5; index += 1)
        tester.getSize(visibleFieldSurfaces.at(index)).height,
    ], List<double>.filled(5, ConsoleControlStyle.height));

    expect(find.text('Project directory'), findsOneWidget);
    expect(find.text('Allowed folder'), findsOneWidget);
    for (final textField in tester.widgetList<TextField>(
      find.byType(TextField),
    )) {
      expect(textField.decoration?.labelText, isNull);
    }
  });

  testWidgets('primary icon buttons share the filled action palette', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = ConsoleTheme.build(brightness);
      final colors = ConsoleColors(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ConsolePrimaryIconButton(
              onPressed: () {},
              icon: const Icon(Icons.power),
              tooltip: 'Power',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.power))).color,
        colors.actionFg,
        reason: '$brightness filled icon button',
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(
        button.style?.backgroundColor?.resolve(const <WidgetState>{}),
        colors.action,
      );
    }
  });

  testWidgets('multiline fields can grow beyond the single-line height', (
    tester,
  ) async {
    const multilineKey = ValueKey('multiline');

    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.build(Brightness.dark),
        home: const Scaffold(
          body: ConsoleTextArea(
            key: multilineKey,
            minLines: 3,
            maxLines: 3,
            label: 'Inputs',
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(multilineKey)).height,
      greaterThan(ConsoleControlStyle.height),
    );
  });
}

double _contrast(Color first, Color second) {
  final firstLuminance = _luminance(first);
  final secondLuminance = _luminance(second);
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) => color.computeLuminance();
