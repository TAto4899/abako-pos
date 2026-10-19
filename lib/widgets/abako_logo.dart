import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/abako_colors.dart';

/// Ícono cuadrado con 3 "puntos sobre línea" + wordmark "Stock y Ventas".
class AbakoLogo extends StatelessWidget {
  const AbakoLogo({super.key, this.dark = true, this.size = 40});

  /// true = sobre fondo verde (texto/ícono claros), false = sobre fondo claro.
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dotPositions = [0.14, 0.62, 0.36];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.symmetric(horizontal: size * 0.2),
          decoration: BoxDecoration(
            color: AbakoColors.logoGreen,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: dotPositions
                .map(
                  (pos) => Padding(
                    padding: EdgeInsets.symmetric(vertical: size * 0.045),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: size * 0.09,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(size * 0.05),
                          ),
                        ),
                        Positioned(
                          left: size * pos,
                          top: -size * 0.06,
                          child: Container(
                            width: size * 0.19,
                            height: size * 0.19,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SizedBox(width: size * 0.28),
        // Flexible + maxLines/ellipsis como red de seguridad: "Stock y
        // Ventas" es bastante más largo que "Abako" y este logo se usa en
        // contextos angostos (sidebar de 236px) donde antes no hacía falta.
        Flexible(
          child: Text(
            'Stock y Ventas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w700,
              fontSize: size * 0.4,
              letterSpacing: -0.2,
              color: dark ? AbakoColors.creamText : AbakoColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}
