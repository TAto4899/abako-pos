import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../theme/abako_colors.dart';
import '../widgets/abako_logo.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await sb.Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on sb.AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

  // ---------------- Escritorio ----------------

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
          height: 700,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: _greenPanelDesktop()),
              Expanded(flex: 6, child: _formPanelDesktop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _greenPanelDesktop() {
    return Container(
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
                'Tu inventario y tus ventas, en un solo lugar.',
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
                'Controla el stock, registra ventas y entiende tu negocio desde cualquier dispositivo.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.5,
                  color: AbakoColors.creamText.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 32),
              _salesPreviewCard(),
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
    );
  }

  Widget _salesPreviewCard() {
    const bars = [0.42, 0.60, 0.38, 0.74, 0.55, 0.90, 0.68];
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AbakoColors.cream,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ventas de hoy',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6B7A72),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F5EC),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  '▲ 12.4%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AbakoColors.accentGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r'$12,480',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w700,
              fontSize: 26,
              letterSpacing: -0.4,
              color: AbakoColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: bars
                  .asMap()
                  .entries
                  .map(
                    (e) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 36 * e.value,
                        decoration: BoxDecoration(
                          color: e.value == 0.90
                              ? AbakoColors.accentGreen
                              : (e.value == 0.74
                                    ? const Color(0xFFBCE6CC)
                                    : const Color(0xFFD9EFE1)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanelDesktop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 392),
          child: _loginForm(showHeading: true),
        ),
      ),
    );
  }

  // ---------------- Móvil ----------------

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
                const AbakoLogo(size: 36),
                const SizedBox(height: 24),
                Text(
                  'Hola de nuevo',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w600,
                    fontSize: 24,
                    color: AbakoColors.creamText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Administra tu inventario y ventas.',
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
              child: _loginForm(showHeading: false),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Formulario compartido ----------------

  Widget _loginForm({required bool showHeading}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeading) ...[
          Text(
            'Inicia sesión',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w600,
              fontSize: 28,
              letterSpacing: -0.4,
              color: AbakoColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresa tus datos para administrar tu inventario y ventas.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.5,
              color: AbakoColors.textMuted,
            ),
          ),
          const SizedBox(height: 26),
        ],
        _fieldLabel('Correo'),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration('tucorreo@negocio.com'),
        ),
        const SizedBox(height: 16),
        _fieldLabel('Contraseña'),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _signIn(),
          decoration: _inputDecoration('••••••••').copyWith(
            suffixIcon: TextButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: Text(
                _obscurePassword ? 'Mostrar' : 'Ocultar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AbakoColors.accentGreen,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _rememberMe,
                    activeColor: AbakoColors.accentGreen,
                    onChanged: (v) =>
                        setState(() => _rememberMe = v ?? _rememberMe),
                  ),
                  Text(
                    'Recordar sesión',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      color: AbakoColors.textLabel,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ForgotPasswordPage(),
                ),
              ),
              child: Text(
                '¿Olvidaste tu contraseña?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AbakoColors.accentGreen,
                ),
              ),
            ),
          ],
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _signIn,
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
                    'Iniciar sesión',
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

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AbakoColors.textLabel,
      ),
    ),
  );

  InputDecoration _inputDecoration(String hint) {
    OutlineInputBorder border(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 13,
      ),
      border: border(AbakoColors.inputBorder, 1.5),
      enabledBorder: border(AbakoColors.inputBorder, 1.5),
      focusedBorder: border(AbakoColors.accentGreen, 1.5),
    );
  }
}
