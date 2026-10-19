import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'db.dart';
import 'screens/login_page.dart';
import 'shell/app_shell.dart';
import 'widgets/biometric_lock_screen.dart';

// Umbral acordado con Franco (2026-09-01): si la app estuvo en segundo plano
// menos que esto, no se pide huella al volver; si estuvo más, sí.
const _umbralInactividad = Duration(minutes: 5);

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _localAuth = LocalAuthentication();
  DateTime? _pausadaEn;
  bool _bloqueada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _haySesion => sb.Supabase.instance.client.auth.currentSession != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `hidden` (minimizar en desktop) y `paused` (fondo en Android) se
    // tratan igual como "se fue a segundo plano".
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_haySesion) _pausadaEn ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final pausadaEn = _pausadaEn;
      _pausadaEn = null;
      if (!_haySesion || pausadaEn == null) return;
      if (DateTime.now().difference(pausadaEn) >= _umbralInactividad) {
        _pedirBiometria();
      }
    }
  }

  Future<void> _pedirBiometria() async {
    try {
      // Sin biometría configurada en el dispositivo, se deja entrar igual
      // (decisión de Franco 2026-09-01) — el gate ni se muestra.
      final disponible = await _localAuth.canCheckBiometrics;
      if (!disponible) return;
      if (mounted) setState(() => _bloqueada = true);
      final ok = await _localAuth.authenticate(
        localizedReason: 'Confirmá tu identidad para volver a la app',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok && mounted) setState(() => _bloqueada = false);
    } catch (_) {
      // Sensor no disponible / error de plataforma: no se bloquea el acceso.
      if (mounted) setState(() => _bloqueada = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<sb.AuthState>(
      stream: sb.Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = sb.Supabase.instance.client.auth.currentSession;
        if (session == null) {
          _bloqueada = false;
          return const LoginPage();
        }
        if (_bloqueada) {
          return BiometricLockScreen(onReintentar: _pedirBiometria);
        }
        return FutureBuilder<void>(
          future: openDatabase(),
          builder: (context, dbSnapshot) {
            if (dbSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return const AppShell();
          },
        );
      },
    );
  }
}
