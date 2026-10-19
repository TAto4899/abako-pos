import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'powersync_config.dart';

class SupabaseConnector extends PowerSyncBackendConnector {
  final PowerSyncDatabase db;

  SupabaseConnector(this.db);

  Map<String, String> get _headers {
    final accessToken = sb.Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer ${accessToken ?? supabaseAnonKey}',
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    };
  }

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = sb.Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return null;
    }
    return PowerSyncCredentials(
      endpoint: powerSyncEndpoint,
      token: session.accessToken,
      expiresAt: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
          : null,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    for (final op in transaction.crud) {
      final rowUrl = '$supabaseRestUrl/${op.table}?id=eq.${op.id}';

      http.Response response;
      switch (op.op) {
        case UpdateType.put:
          response = await http.post(
            Uri.parse('$supabaseRestUrl/${op.table}'),
            headers: _headers,
            body: jsonEncode({'id': op.id, ...?op.opData}),
          );
          // Un 409 de clave duplicada en un `put` significa que esta fila ya
          // se subió antes (ej. la app se cerró justo después de que Postgres
          // la recibiera pero antes de que el cliente marcara la transacción
          // como completa) — no es un error real, tratarlo como éxito evita
          // que quede bloqueada toda la cola de subida detrás. No se usa
          // upsert genérico acá a propósito: movimientos_stock/pagos_venta
          // son append-only también a nivel de RLS (sin permiso de UPDATE),
          // y un upsert real necesitaría ese permiso.
          if (response.statusCode == 409) {
            continue;
          }
          break;
        case UpdateType.patch:
          response = await http.patch(
            Uri.parse(rowUrl),
            headers: _headers,
            body: jsonEncode(op.opData),
          );
          break;
        case UpdateType.delete:
          response = await http.delete(
            Uri.parse(rowUrl),
            headers: _headers,
          );
          break;
      }

      if (response.statusCode >= 300) {
        throw Exception(
          'PostgREST ${op.op} en ${op.table} falló '
          '(${response.statusCode}): ${response.body}',
        );
      }
    }

    await transaction.complete();
  }
}
