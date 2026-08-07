import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:flutter/material.dart';

/// Canonical single-line form controls for Cockpit Console.
///
/// Every component in this file consumes [ConsoleControlStyle], so screens
/// describe field meaning while the shared layer owns labels, density, padding,
/// borders, supporting text, and icon constraints.
/// A single-line text input with the shared Console control geometry.
final class ConsoleTextField extends StatelessWidget {
  const ConsoleTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.supportingText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? supportingText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return _ConsoleFieldFrame(
      label: label,
      supportingText: supportingText,
      errorText: errorText,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        minLines: 1,
        maxLines: 1,
        style: style,
        decoration: ConsoleControlStyle.field(
          hint: hint,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// A multiline form input using the same label, border, padding, and state
/// vocabulary as [ConsoleTextField] while allowing its surface to grow.
final class ConsoleTextArea extends StatelessWidget {
  const ConsoleTextArea({
    super.key,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.minLines = 2,
    this.maxLines = 4,
    this.style,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.supportingText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final int minLines;
  final int maxLines;
  final TextStyle? style;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? supportingText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return _ConsoleFieldFrame(
      label: label,
      supportingText: supportingText,
      errorText: errorText,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        minLines: minLines,
        maxLines: maxLines,
        style: style,
        decoration: ConsoleControlStyle.textArea(
          hint: hint,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// A dropdown selector with the same height and internal alignment as text
/// fields and standard buttons.
final class ConsoleDropdownField<T> extends StatelessWidget {
  const ConsoleDropdownField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.supportingText,
    this.errorText,
    this.hint,
    this.enabled = true,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? supportingText;
  final String? errorText;
  final Widget? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _ConsoleFieldFrame(
      label: label,
      supportingText: supportingText,
      errorText: errorText,
      child: DropdownButtonFormField<T>(
        initialValue: initialValue,
        isExpanded: true,
        decoration: ConsoleControlStyle.field(
          hint: hintText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        hint: hint,
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// A read-only value rendered with the same geometry as editable fields.
final class ConsoleFieldValue extends StatelessWidget {
  const ConsoleFieldValue({
    super.key,
    required this.child,
    this.label,
    this.prefixIcon,
    this.suffixIcon,
    this.supportingText,
    this.errorText,
  });

  final Widget child;
  final String? label;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? supportingText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return _ConsoleFieldFrame(
      label: label,
      supportingText: supportingText,
      errorText: errorText,
      child: InputDecorator(
        decoration: ConsoleControlStyle.field(
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        child: child,
      ),
    );
  }
}

/// A 40px icon action aligned with a Console form control.
final class ConsoleFieldIconButton extends StatelessWidget {
  const ConsoleFieldIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: ConsoleControlStyle.fieldIconButtonStyle(),
    );
  }
}

final class _ConsoleFieldFrame extends StatelessWidget {
  const _ConsoleFieldFrame({
    required this.child,
    this.label,
    this.supportingText,
    this.errorText,
  });

  final Widget child;
  final String? label;
  final String? supportingText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (label == null && supportingText == null && errorText == null) {
      return child;
    }
    final theme = Theme.of(context);
    final support = errorText ?? supportingText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          ExcludeSemantics(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: ConsoleControlStyle.labelGap),
        ],
        Semantics(container: true, label: label, child: child),
        if (support != null) ...[
          const SizedBox(height: ConsoleControlStyle.supportGap),
          Text(
            support,
            style: theme.textTheme.bodySmall?.copyWith(
              color: errorText == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
