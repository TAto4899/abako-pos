import 'package:flutter/material.dart';

/// Paleta del diseño "Abako" (claude.ai/design, compartido 2026-07-28).
class AbakoColors {
  AbakoColors._();

  static const panelGreen = Color(0xFF1C5238);
  static const accentGreen = Color(0xFF1B9C5A);
  static const accentGreenHover = Color(0xFF17854D);
  static const logoGreen = Color(0xFF27C26C);

  static const cream = Color(0xFFFBFAF7);
  static const creamOuter = Color(0xFFE9E7DF);
  static const creamText = Color(0xFFF4F1E8);

  static const textDark = Color(0xFF1A2620);
  static const textLabel = Color(0xFF3A463F);
  static const textMuted = Color(0xFF6B7A72);
  static const textFaint = Color(0xFF8A877C);

  static const inputBorder = Color(0xFFE3E0D8);
  static const placeholder = Color(0xFFA6AFA9);

  static const statusOkBg = Color(0xFFE6F5EC);
  static const statusOkText = Color(0xFF147A45);
  static const statusBajoBg = Color(0xFFFBEFD6);
  static const statusBajoText = Color(0xFFB07A12);
  static const statusBajoDot = Color(0xFFE0A23B);
  static const statusAgotadoBg = Color(0xFFFBECEA);
  static const statusAgotadoText = Color(0xFFB0453B);
  static const statusAgotadoDot = Color(0xFFC0453B);

  /// Paleta para los íconos-avatar de producto (iniciales sobre color), tal
  /// cual el diseño Abako. El color de cada producto se deriva de su nombre
  /// (hash estable), no se guarda como columna en la base.
  static const productAvatarPalette = [
    Color(0xFFC0453B),
    Color(0xFF4F93B0),
    Color(0xFF4FA877),
    Color(0xFF8A5A3C),
    Color(0xFFE0A23B),
    Color(0xFFC98A4B),
    Color(0xFFD9702A),
    Color(0xFF5A8FB0),
    Color(0xFFC9A24B),
    Color(0xFFA89A66),
    Color(0xFF7A5A4B),
    Color(0xFFB58A3C),
    Color(0xFFCE7C96),
    Color(0xFF4FA0A8),
    Color(0xFF6FA877),
    Color(0xFF5577A8),
  ];
}
