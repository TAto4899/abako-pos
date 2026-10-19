import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth_gate.dart';
import 'powersync_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await sb.Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    // Implicit flow (no PKCE): la app no usa OAuth, y el link de recuperación
    // de contraseña lo tiene que poder completar un navegador cualquiera, no
    // solo este mismo dispositivo (PKCE ata el code a un verifier local).
    authOptions: const sb.FlutterAuthClientOptions(
      authFlowType: sb.AuthFlowType.implicit,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock / Ventas',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const AuthGate(),
    );
  }
}
