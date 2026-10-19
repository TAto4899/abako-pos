import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
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

const _ventasQuery = 'SELECT id, total, estado, creado_en FROM ventas';

class _Venta {
  _Venta({required this.id, required this.total, required this.estado, required this.creadoEn});
  final String id;
  final double total;
  final String estado;
  final DateTime creadoEn;

  static _Venta fromRow(dynamic row) => _Venta(
        id: row['id'] as String,
        total: double.tryParse('${row['total']}') ?? 0,
        estado: row['estado'] as String,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

class RevisionPage extends StatelessWidget {
  const RevisionPage({super.key});

  Future<void> _abrirDetalle(BuildContext context, String ventaId) async {
    final revisada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VentaDetallePage(ventaId: ventaId)),
    );
    if (revisada == true && context.mounted) {
      mostrarSnack(context, 'Venta marcada como revisada');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.creamOuter,
      appBar: AppBar(
        backgroundColor: AbakoColors.panelGreen,
        foregroundColor: AbakoColors.creamText,
        elevation: 0,
        title: Text('Ventas pendientes de revisión',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.creamText)),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(_ventasQuery),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final ventas = snap.data!
              .map(_Venta.fromRow)
              .where((v) => v.estado == 'pendiente_revision')
              .toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          if (ventas.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 40, color: AbakoColors.statusOkText),
                    const SizedBox(height: 12),
                    Text('No hay ventas pendientes de revisión.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(color: AbakoColors.textFaint, fontSize: 14)),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ventas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final v = ventas[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _abrirDetalle(context, v.id),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFECEAE3)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Container(width: 5, color: AbakoColors.statusAgotadoDot),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AbakoColors.statusAgotadoBg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.error_outline, color: AbakoColors.statusAgotadoText, size: 20),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_fmtFechaHora(v.creadoEn),
                                            style: GoogleFonts.plusJakartaSans(
                                                fontSize: 13.5, fontWeight: FontWeight.w700, color: AbakoColors.textDark)),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AbakoColors.statusAgotadoBg,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text('Sobregiro de stock',
                                              style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 11, fontWeight: FontWeight.w700, color: AbakoColors.statusAgotadoText)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_fmtMoney(v.total),
                                          style: GoogleFonts.bricolageGrotesque(
                                              fontWeight: FontWeight.w700, fontSize: 15, color: AbakoColors.textDark)),
                                      const Icon(Icons.chevron_right, color: AbakoColors.textFaint, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
