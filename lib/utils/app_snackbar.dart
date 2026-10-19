import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/abako_colors.dart';

enum SnackKind { exito, error, info }

/// Snackbar con el estilo visual del resto de la app (mismos colores que las
/// tarjetas de estado/badges — statusOkBg, statusAgotadoBg, statusBajoBg) en
/// vez del gris genérico de Material. Usar en toda acción que confirme o
/// falle: guardar, eliminar, registrar una venta, abrir/cerrar caja, etc.
void mostrarSnack(BuildContext context, String mensaje, {SnackKind kind = SnackKind.exito}) {
  final Color bg;
  final Color fg;
  final IconData icono;
  switch (kind) {
    case SnackKind.exito:
      bg = AbakoColors.statusOkBg;
      fg = AbakoColors.statusOkText;
      icono = Icons.check_circle_outline;
    case SnackKind.error:
      bg = AbakoColors.statusAgotadoBg;
      fg = AbakoColors.statusAgotadoText;
      icono = Icons.error_outline;
    case SnackKind.info:
      bg = AbakoColors.statusBajoBg;
      fg = AbakoColors.statusBajoText;
      icono = Icons.info_outline;
  }

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icono, color: fg, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(mensaje,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      ),
    );
}
