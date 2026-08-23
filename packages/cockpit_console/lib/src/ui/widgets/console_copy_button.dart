import 'dart:async';

import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum ConsoleCopyButtonVariant { icon, labeled }

final class ConsoleCopyButton extends StatefulWidget {
  const ConsoleCopyButton({
    required this.text,
    required this.copyLabel,
    required this.copiedLabel,
    this.icon = LucideIcons.copy,
    this.variant = ConsoleCopyButtonVariant.icon,
    this.iconSize = 14,
    super.key,
  });

  final String text;
  final String copyLabel;
  final String copiedLabel;
  final IconData icon;
  final ConsoleCopyButtonVariant variant;
  final double iconSize;

  @override
  State<ConsoleCopyButton> createState() => _ConsoleCopyButtonState();
}

enum _CopyState { idle, copied, failed }

final class _ConsoleCopyButtonState extends State<ConsoleCopyButton> {
  Timer? _resetTimer;
  _CopyState _state = _CopyState.idle;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
      _setTemporaryState(_CopyState.copied);
    } on Object {
      _setTemporaryState(_CopyState.failed);
    }
  }

  void _setTemporaryState(_CopyState state) {
    if (!mounted) return;
    _resetTimer?.cancel();
    setState(() => _state = state);
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _state = _CopyState.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_state) {
      _CopyState.idle => widget.copyLabel,
      _CopyState.copied => widget.copiedLabel,
      _CopyState.failed => context.t.common.copyFailed,
    };
    final icon = switch (_state) {
      _CopyState.idle => widget.icon,
      _CopyState.copied => LucideIcons.check,
      _CopyState.failed => LucideIcons.circleAlert,
    };
    final onPressed = widget.text.isEmpty ? null : _copy;

    return switch (widget.variant) {
      ConsoleCopyButtonVariant.icon => IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: widget.iconSize),
      ),
      ConsoleCopyButtonVariant.labeled => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: widget.iconSize),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    };
  }
}
