import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../theme/abako_colors.dart';
import '../widgets/abako_logo.dart';

/// El link de recuperación lleva a una páginita web aparte (no a la app) que
/// completa el cambio de contraseña: C:\dev\pos_stock_reset_page, hosteada en
/// Netlify Drop.
const _resetPasswordPageUrl = 'https://celebrated-caramel-e51394.netlify.app';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _sent = false;

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await sb.Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: _resetPasswordPageUrl,
      );
      if (mounted) setState(() => _sent = true);
    } on sb.AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.creamOuter,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              child: Center(
                child: isDesktop ? _buildDesktop() : _buildMobile(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktop() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 32),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        color: AbakoColors.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: SizedBox(
          height: 620,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  color: AbakoColors.panelGreen,
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const AbakoLogo(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recupera el acceso en segundos.',
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w600,
                              fontSize: 34,
                              height: 1.1,
                              letterSpacing: -0.4,
                              color: AbakoColors.creamText,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Te enviaremos un enlace seguro para que crees una contraseña nueva.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              height: 1.5,
                              color: AbakoColors.creamText.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '© 2026 Abako · Hecho para tu negocio',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AbakoColors.creamText.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 40, 56, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 392),
                      child: _form(showHeading: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AbakoColors.panelGreen,
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AbakoColors.creamText.withValues(
                      alpha: 0.8,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: Text(
                    'Volver',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '¿Olvidaste tu contraseña?',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    color: AbakoColors.creamText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Te enviaremos un enlace para restablecerla.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AbakoColors.creamText.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
              decoration: const BoxDecoration(
                color: AbakoColors.cream,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                ),
              ),
              child: _form(showHeading: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form({required bool showHeading}) {
    if (_sent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Revisa tu correo',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w600,
              fontSize: 26,
              color: AbakoColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Te enviamos un enlace a ${_emailController.text.trim()} para que restablezcas tu contraseña.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14.5,
              height: 1.5,
              color: AbakoColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '← Volver a iniciar sesión',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AbakoColors.accentGreen,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: AbakoColors.textMuted,
            ),
            child: Text(
              '← Volver a iniciar sesión',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '¿Olvidaste tu contraseña?',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w600,
              fontSize: 28,
              letterSpacing: -0.4,
              color: AbakoColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresa tu correo y te enviaremos un enlace para restablecerla.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.5,
              color: AbakoColors.textMuted,
            ),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          'Correo',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AbakoColors.textLabel,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            hintText: 'tucorreo@negocio.com',
            hintStyle: GoogleFonts.plusJakartaSans(
              color: AbakoColors.placeholder,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AbakoColors.inputBorder,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AbakoColors.inputBorder,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AbakoColors.accentGreen,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.red.shade700,
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: AbakoColors.accentGreen,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Enviar enlace',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
