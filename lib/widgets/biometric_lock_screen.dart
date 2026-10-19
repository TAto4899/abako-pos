import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../theme/abako_colors.dart';

/// Pantalla que tapa el resto de la app mientras se pide/reintenta la
/// autenticación biométrica (ver `auth_gate.dart`). Solo llega a mostrarse
/// si el dispositivo tiene biometría configurada — si no, el gate deja
/// entrar directo, sin pasar por acá.
class BiometricLockScreen extends StatelessWidget {
  const BiometricLockScreen({super.key, required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.panelGreen,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.fingerprint, color: Colors.white, size: 46),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Confirmá tu identidad',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 22, color: AbakoColors.creamText),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pasó un rato desde la última vez que usaste la app.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.4, color: AbakoColors.creamText.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onReintentar,
                      style: FilledButton.styleFrom(
                        backgroundColor: AbakoColors.accentGreen,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Desbloquear',
                        style: GoogleFonts.plusJakartaSans(fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => sb.Supabase.instance.client.auth.signOut(),
                    child: Text(
                      'Cerrar sesión',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.creamText.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
