import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;

import '../db.dart';
import '../theme/abako_colors.dart';
import 'venta_detalle_page.dart';

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

String _fmtFechaHora(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm $hh:$min';
}

const _ventasQuery = 'SELECT id, total, estado, cliente_id, creado_en FROM ventas';
const _clientesQuery = 'SELECT id, nombre FROM clientes';

class _Venta {
  _Venta({required this.id, required this.total, required this.estado, required this.clienteId, required this.creadoEn});
  final String id;
  final double total;
  final String estado;
  final String? clienteId;
  final DateTime creadoEn;

  static _Venta fromRow(dynamic row) => _Venta(
        id: row['id'] as String,
        total: double.tryParse('${row['total']}') ?? 0,
        estado: row['estado'] as String,
        clienteId: row['cliente_id'] as String?,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

/// Buscador/lista de TODO el historial de ventas — a diferencia de "Ventas
/// recientes" en Inicio (últimas 8) o el historial dentro del detalle de un
/// Cliente (solo sus compras), acá se puede encontrar cualquier ticket viejo.
class HistorialVentasPage extends StatefulWidget {
  const HistorialVentasPage({super.key});

  @override
  State<HistorialVentasPage> createState() => _HistorialVentasPageState();
}

class _HistorialVentasPageState extends State<HistorialVentasPage> {
  final _buscarCtrl = TextEditingController();
  DateTimeRange? _rango;

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 5),
      lastDate: ahora,
      initialDateRange: _rango ?? DateTimeRange(start: ahora.subtract(const Duration(days: 6)), end: ahora),
    );
    if (elegido != null) setState(() => _rango = elegido);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.creamOuter,
      appBar: AppBar(
        backgroundColor: AbakoColors.panelGreen,
        foregroundColor: AbakoColors.creamText,
        elevation: 0,
        title: Text('Historial de ventas',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.creamText)),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(_ventasQuery),
        builder: (context, ventasSnap) {
          if (!ventasSnap.hasData) return const Center(child: CircularProgressIndicator());
          final ventas = ventasSnap.data!.map(_Venta.fromRow).toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          return StreamBuilder<ResultSet>(
            stream: db.watch(_clientesQuery),
            builder: (context, clientesSnap) {
              final nombrePorCliente = {
                for (final row in clientesSnap.data?.toList() ?? const []) row['id'] as String: row['nombre'] as String,
              };

              final q = _buscarCtrl.text.trim().toLowerCase();
              final rango = _rango;
              final filtradas = ventas.where((v) {
                if (rango != null) {
                  final finInclusivo = DateTime(rango.end.year, rango.end.month, rango.end.day).add(const Duration(days: 1));
                  if (v.creadoEn.isBefore(DateTime(rango.start.year, rango.start.month, rango.start.day)) ||
                      !v.creadoEn.isBefore(finInclusivo)) {
                    return false;
                  }
                }
                if (q.isEmpty) return true;
                final nombre = nombrePorCliente[v.clienteId]?.toLowerCase() ?? '';
                return nombre.contains(q) || _fmtMoney(v.total).contains(q);
              }).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buscarCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Buscar por cliente o monto...',
                              hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: _elegirRango,
                          icon: Icon(Icons.calendar_month_outlined, color: rango != null ? AbakoColors.accentGreen : AbakoColors.textMuted),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(color: rango != null ? AbakoColors.accentGreen : AbakoColors.inputBorder, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rango != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text(
                              '${rango.start.day.toString().padLeft(2, '0')}/${rango.start.month.toString().padLeft(2, '0')} – ${rango.end.day.toString().padLeft(2, '0')}/${rango.end.month.toString().padLeft(2, '0')}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12.5)),
                          onDeleted: () => setState(() => _rango = null),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AbakoColors.inputBorder),
                        ),
                      ),
                    ),
                  Expanded(
                    child: filtradas.isEmpty
                        ? Center(
                            child: Text('No se encontraron ventas.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtradas.length,
                            itemBuilder: (context, i) {
                              final v = filtradas[i];
                              final nombreCliente = nombrePorCliente[v.clienteId];
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => VentaDetallePage(ventaId: v.id)),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFECEAE3)), borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(_fmtFechaHora(v.creadoEn),
                                                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                                              if (nombreCliente != null)
                                                Text(nombreCliente, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint)),
                                              if (v.estado == 'pendiente_revision')
                                                Text('Pendiente de revisión',
                                                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.statusAgotadoText)),
                                              if (v.estado == 'anulada')
                                                Text('Anulada',
                                                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textMuted)),
                                            ],
                                          ),
                                        ),
                                        Text(_fmtMoney(v.total),
                                            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 14, color: AbakoColors.textDark)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right, size: 16, color: AbakoColors.textFaint),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
