import 'package:flutter/material.dart';

import '../theme/abako_colors.dart';

/// Iniciales para el ícono-avatar de un producto, mismo criterio que el
/// diseño Abako: primeras letras de las dos primeras palabras del nombre.
String monoOf(String nombre) {
  final words = nombre.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return '·';
  final first = words.first;
  final a = first.substring(0, 1);
  final b = words.length > 1 && words[1].isNotEmpty
      ? words[1].substring(0, 1)
      : (first.length > 1 ? first.substring(1, 2) : '');
  return (a + b).toUpperCase();
}

/// Color estable para el ícono-avatar de un producto, derivado del nombre
/// (no se persiste en la base).
Color colorOf(String nombre) {
  final palette = AbakoColors.productAvatarPalette;
  return palette[nombre.hashCode.abs() % palette.length];
}
