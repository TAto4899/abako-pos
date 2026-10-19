import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/abako_colors.dart';

String _fmtMoney(num n) {
  final rounded = n.round();
  final s = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return (rounded < 0 ? '-\$' : '\$') + buf.toString();
}

final _sonidoVenta = AudioPlayer();

const _duracionVisible = Duration(milliseconds: 1600);

/// Popup de confirmación de venta: tarjeta centrada con animación de
/// entrada (scale+fade), check verde y sonido, se cierra sola después de
/// [_duracionVisible] o al tocar la pantalla. Reemplaza al SnackBar de texto
/// que se usaba antes en `venta_page.dart`.
Future<void> mostrarVentaConfirmada(BuildContext context, {required double total}) async {
  unawaited(
    _sonidoVenta.play(AssetSource('sounds/venta_confirmada.wav')).catchError((_) {
      // Sin audio (ej. dispositivo silenciado o sin salida) no debe romper
      // el flujo de venta — el popup visual sigue funcionando igual.
    }),
  );
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Venta confirmada',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => _VentaConfirmadaCard(total: total),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curva = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curva, child: child),
      );
    },
  );
}

class _VentaConfirmadaCard extends StatefulWidget {
  const _VentaConfirmadaCard({required this.total});

  final double total;

  @override
  State<_VentaConfirmadaCard> createState() => _VentaConfirmadaCardState();
}

class _VentaConfirmadaCardState extends State<_VentaConfirmadaCard> {
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(_duracionVisible, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
          decoration: BoxDecoration(
            color: AbakoColors.cream,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 28, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AbakoColors.statusOkBg, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AbakoColors.accentGreen, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                '¡Venta registrada!',
                style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: AbakoColors.textDark),
              ),
              const SizedBox(height: 6),
              Text(
                _fmtMoney(widget.total),
                style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800, color: AbakoColors.accentGreen),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
