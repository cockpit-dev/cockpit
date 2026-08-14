import 'package:flutter/material.dart';

/// Cockpit Console design tokens.
///
/// Linear / Vercel inspired palette: a dark-first surface system built on
/// near-black neutrals with a single blue accent and status-specific hues.
/// All values are hand-tuned for the Flutter color pipeline (sRGB).
final class ConsolePalette {
  const ConsolePalette._();

  // ── Dark surface ramp (background to highest container) ──────────────
  static const Color darkBg = Color(0xFF08090A);
  static const Color darkSurface = Color(0xFF0D0E11);
  static const Color darkSurface1 = Color(0xFF121317);
  static const Color darkSurface2 = Color(0xFF181A1F);
  static const Color darkSurface3 = Color(0xFF202227);
  static const Color darkSurfaceHover = Color(0xFF25272D);

  // ── Dark ink ─────────────────────────────────────────────────────────
  static const Color darkInkPrimary = Color(0xFFEDEDEF);
  static const Color darkInkSecondary = Color(0xFF9B9DA3);
  static const Color darkInkTertiary = Color(0xFF7F8187);
  static const Color darkInkDisabled = Color(0xFF797B82);

  // ── Dark borders ─────────────────────────────────────────────────────
  static const Color darkBorder = Color(0xFF26272B);
  static const Color darkBorderHover = Color(0xFF34363B);
  static const Color darkBorderFocus = Color(0xFF3D3F45);

  // ── Light surface ramp ───────────────────────────────────────────────
  static const Color lightBg = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface1 = Color(0xFFF5F5F6);
  static const Color lightSurface2 = Color(0xFFECECEE);
  static const Color lightSurface3 = Color(0xFFE2E2E5);
  static const Color lightSurfaceHover = Color(0xFFDFDFE2);

  // ── Light ink ────────────────────────────────────────────────────────
  static const Color lightInkPrimary = Color(0xFF1A1A1C);
  static const Color lightInkSecondary = Color(0xFF5F6168);
  static const Color lightInkTertiary = Color(0xFF6A6C73);
  static const Color lightInkDisabled = Color(0xFF74767D);

  // ── Light borders ────────────────────────────────────────────────────
  static const Color lightBorder = Color(0xFFE0E0E3);
  static const Color lightBorderHover = Color(0xFFD0D0D4);
  static const Color lightBorderFocus = Color(0xFFC0C0C5);

  // ── Accent (blue) ────────────────────────────────────────────────────
  static const Color accent = Color(0xFF5B8DEF);
  static const Color accentHover = Color(0xFF7BA1F2);
  static const Color accentActive = Color(0xFF4A7DD8);
  static const Color accentFg = Color(0xFF08090A);
  static const Color accentSubtle = Color(0xFF1A2B48);
  static const Color accentSubtleFg = Color(0xFF7BA1F2);

  // ── Status: success (green) ──────────────────────────────────────────
  static const Color success = Color(0xFF4CB782);
  static const Color successSubtle = Color(0xFF123326);
  static const Color successFg = Color(0xFF4CB782);

  // ── Status: warning (amber) ──────────────────────────────────────────
  static const Color warning = Color(0xFFF0A93C);
  static const Color warningSubtle = Color(0xFF33260E);
  static const Color warningFg = Color(0xFFF0A93C);

  // ── Status: error (red) ──────────────────────────────────────────────
  static const Color error = Color(0xFFE5534B);
  static const Color errorSubtle = Color(0xFF321815);
  static const Color errorFg = Color(0xFFE5534B);

  // ── Status: info ─────────────────────────────────────────────────────
  static const Color info = Color(0xFF5B8DEF);
  static const Color infoSubtle = Color(0xFF1A2B48);
  static const Color infoFg = Color(0xFF5B8DEF);

  // ── Run lifecycle colors ─────────────────────────────────────────────
  static const Color runPending = Color(0xFF9B9DA3);
  static const Color runRunning = Color(0xFF5B8DEF);
  static const Color runPassed = Color(0xFF4CB782);
  static const Color runFailed = Color(0xFFE5534B);
  static const Color runBlocked = Color(0xFFF0A93C);
  static const Color runCancelled = Color(0xFF6B6D73);
}
