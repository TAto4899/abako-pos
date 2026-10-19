import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/product_avatar.dart';

const _uuid = Uuid();

String _fmtQty(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

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

const _ventasQuery = 'SELECT id, deposito_id, total, estado, creado_en FROM ventas';
const _movimientosQuery =
    'SELECT producto_id, cantidad, motivo, venta_id, creado_en FROM movimientos_stock';
const _productosQuery = 'SELECT id, nombre FROM productos';
const _pagosQuery =
    'SELECT venta_id, metodo, monto, efectivo_recibido, vuelto FROM pagos_venta';

class _Venta {
  _Venta({
    required this.id,
    required this.depositoId,
    required this.total,
    required this.estado,
    required this.creadoEn,
  });
  final String id;
  final String depositoId;
  final double total;
  final String estado;
  final DateTime creadoEn;

  static _Venta fromRow(dynamic row) => _Venta(
        id: row['id'] as String,
        depositoId: row['deposito_id'] as String,
        total: double.tryParse('${row['total']}') ?? 0,
        estado: row['estado'] as String,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

class _Movimiento {
  _Movimiento({
    required this.productoId,
    required this.cantidad,
    required this.motivo,
    required this.ventaId,
  });
  final String productoId;
  final double cantidad;
  final String motivo;
  final String? ventaId;

  static _Movimiento fromRow(dynamic row) => _Movimiento(
        productoId: row['producto_id'] as String,
        cantidad: double.tryParse('${row['cantidad']}') ?? 0,
        motivo: row['motivo'] as String,
        ventaId: row['venta_id'] as String?,
      );
}

class _Pago {
  _Pago({required this.ventaId, required this.metodo, required this.monto, this.efectivoRecibido, this.vuelto});
  final String ventaId;
  final String metodo;
  final double monto;
  final double? efectivoRecibido;
  final double? vuelto;

  static _Pago fromRow(dynamic row) => _Pago(
        ventaId: row['venta_id'] as String,
        metodo: row['metodo'] as String,
        monto: double.tryParse('${row['monto']}') ?? 0,
        efectivoRecibido: row['efectivo_recibido'] == null
            ? null
            : double.tryParse('${row['efectivo_recibido']}'),
        vuelto: row['vuelto'] == null ? null : double.tryParse('${row['vuelto']}'),
      );
}

/// Una línea vendida (solo para mostrar qué incluía el ticket).
class _LineaVenta {
  const _LineaVenta({required this.productoId, required this.cantidad});
  final String productoId;
  final double cantidad;
}

/// Detalle de una venta: productos, pagos y, según el estado, marcarla como
/// revisada (sobregiro) o anularla completa.
///
/// Anular una venta repone TODO el stock que vendió (motivo `anulacion`, no
/// `devolucion` — así no se mezcla con la sección "Devoluciones" de Reportes,
/// que sigue siendo solo para devoluciones físicas genuinas) y la excluye de
/// ahí en más de todas las estadísticas (Inicio/Reportes/Caja). Si el cliente
/// se queda con parte de los productos, esos se cargan como una venta nueva
/// aparte en Vender — no se automatiza ese "re-facturado" a propósito.
class VentaDetallePage extends StatefulWidget {
  const VentaDetallePage({super.key, required this.ventaId});
  final String ventaId;

  @override
  State<VentaDetallePage> createState() => _VentaDetallePageState();
}

class _VentaDetallePageState extends State<VentaDetallePage> {
  bool _guardando = false;

  Future<void> _marcarRevisada() async {
    setState(() => _guardando = true);
    try {
      await db.execute("UPDATE ventas SET estado = 'revisada' WHERE id = ?", [widget.ventaId]);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _anularVenta(_Venta venta, List<_LineaVenta> lineas) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular esta venta?'),
        content: const Text(
            'Se repone todo el stock vendido y deja de contar en las estadísticas (Inicio, Reportes, Caja). '
            'Si el cliente se queda con parte de los productos, cargalos como una venta nueva en Vender.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AbakoColors.statusAgotadoText),
            child: const Text('Anular venta'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _guardando = true);
    try {
      final ahora = DateTime.now().toIso8601String();
      await db.writeTransaction((tx) async {
        for (final l in lineas) {
          await tx.execute(
            '''INSERT INTO movimientos_stock
               (id, producto_id, deposito_id, cantidad, motivo, venta_id, creado_en)
               VALUES (?, ?, ?, ?, 'anulacion', ?, ?)''',
            [_uuid.v4(), l.productoId, venta.depositoId, l.cantidad, venta.id, ahora],
          );
        }
        await tx.execute("UPDATE ventas SET estado = 'anulada' WHERE id = ?", [venta.id]);
      });
      if (mounted) mostrarSnack(context, 'Venta anulada');
    } finally {
      if (mounted) setState(() => _guardando = false);
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
        title: Text('Detalle de venta',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.creamText)),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(_ventasQuery),
        builder: (context, ventasSnap) {
          if (!ventasSnap.hasData) return const Center(child: CircularProgressIndicator());
          final ventas = ventasSnap.data!.map(_Venta.fromRow).toList();
          final venta = ventas.where((v) => v.id == widget.ventaId).firstOrNull;
          if (venta == null) {
            return Center(
              child: Text('Esta venta ya no existe.',
                  style: GoogleFonts.plusJakartaSans(color: AbakoColors.textFaint)),
            );
          }

          return StreamBuilder<ResultSet>(
            stream: db.watch(_movimientosQuery),
            builder: (context, movSnap) {
              if (!movSnap.hasData) return const Center(child: CircularProgressIndicator());
              final movimientos = movSnap.data!.map(_Movimiento.fromRow).toList();

              return StreamBuilder<ResultSet>(
                stream: db.watch(_productosQuery),
                builder: (context, prodSnap) {
                  if (!prodSnap.hasData) return const Center(child: CircularProgressIndicator());
                  final nombrePorId = {
                    for (final row in prodSnap.data!) row['id'] as String: row['nombre'] as String,
                  };

                  return StreamBuilder<ResultSet>(
                    stream: db.watch(_pagosQuery),
                    builder: (context, pagosSnap) {
                      if (!pagosSnap.hasData) return const Center(child: CircularProgressIndicator());
                      final pagos = pagosSnap.data!
                          .map(_Pago.fromRow)
                          .where((p) => p.ventaId == widget.ventaId)
                          .toList();

                      final ventaMovs = movimientos.where((m) => m.ventaId == widget.ventaId);
                      final ventaMovsPorProducto = <String, double>{};
                      for (final m in ventaMovs.where((m) => m.motivo == 'venta')) {
                        ventaMovsPorProducto[m.productoId] = (ventaMovsPorProducto[m.productoId] ?? 0) + m.cantidad;
                      }
                      // cantidad = -e.value: el movimiento original es negativo
                      // (sale stock), así que esto es a la vez "vendida" (para
                      // mostrar) y la cantidad exacta a insertar como
                      // 'anulacion' para reponer el stock por completo.
                      final lineas = ventaMovsPorProducto.entries
                          .map((e) => _LineaVenta(productoId: e.key, cantidad: -e.value))
                          .toList();

                      final stockPorProducto = <String, double>{};
                      for (final m in movimientos) {
                        stockPorProducto[m.productoId] = (stockPorProducto[m.productoId] ?? 0) + m.cantidad;
                      }

                      return _DetalleBody(
                        venta: venta,
                        lineas: lineas,
                        nombrePorId: nombrePorId,
                        stockPorProducto: stockPorProducto,
                        pagos: pagos,
                        guardando: _guardando,
                        onMarcarRevisada: venta.estado == 'pendiente_revision' ? _marcarRevisada : null,
                        onAnular: venta.estado == 'anulada' ? null : () => _anularVenta(venta, lineas),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DetalleBody extends StatelessWidget {
  const _DetalleBody({
    required this.venta,
    required this.lineas,
    required this.nombrePorId,
    required this.stockPorProducto,
    required this.pagos,
    required this.guardando,
    required this.onMarcarRevisada,
    required this.onAnular,
  });

  final _Venta venta;
  final List<_LineaVenta> lineas;
  final Map<String, String> nombrePorId;
  final Map<String, double> stockPorProducto;
  final List<_Pago> pagos;
  final bool guardando;
  final VoidCallback? onMarcarRevisada;
  final VoidCallback? onAnular;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtFechaHora(venta.creadoEn),
                          style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.textDark)),
                      const SizedBox(height: 6),
                      Text(_fmtMoney(venta.total),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AbakoColors.textFaint)),
                    ],
                  ),
                ),
                _EstadoBadge(estado: venta.estado),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Productos de esta venta',
                    style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 15, color: AbakoColors.textDark)),
                const SizedBox(height: 12),
                for (final l in lineas)
                  _LineaRow(
                    nombre: nombrePorId[l.productoId] ?? 'Producto',
                    cantidad: l.cantidad,
                    stockActual: stockPorProducto[l.productoId] ?? 0,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pagos',
                    style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 15, color: AbakoColors.textDark)),
                const SizedBox(height: 12),
                if (pagos.isEmpty)
                  Text('Sin datos de pago registrados.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
                else
                  for (final p in pagos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(_iconoMetodo(p.metodo), size: 17, color: AbakoColors.textFaint),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              p.metodo == 'Efectivo' && p.efectivoRecibido != null
                                  ? '${p.metodo} (recibido ${_fmtMoney(p.efectivoRecibido!)}, vuelto ${_fmtMoney(p.vuelto ?? 0)})'
                                  : p.metodo,
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textLabel),
                            ),
                          ),
                          Text(_fmtMoney(p.monto),
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AbakoColors.textDark)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          if (onMarcarRevisada != null) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: guardando ? null : onMarcarRevisada,
              style: FilledButton.styleFrom(
                backgroundColor: AbakoColors.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: guardando
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Marcar como revisada',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
            ),
          ],
          if (onAnular != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: guardando ? null : onAnular,
              style: OutlinedButton.styleFrom(
                foregroundColor: AbakoColors.statusAgotadoText,
                side: BorderSide(color: AbakoColors.statusAgotadoText, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: guardando
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AbakoColors.statusAgotadoText))
                  : Text('Anular venta',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _iconoMetodo(String metodo) {
  switch (metodo) {
    case 'Efectivo':
      return Icons.payments_outlined;
    case 'Tarjeta':
      return Icons.credit_card;
    default:
      return Icons.account_balance_outlined;
  }
}

class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge({required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;
    switch (estado) {
      case 'revisada':
        bg = AbakoColors.statusOkBg;
        fg = AbakoColors.statusOkText;
        icon = Icons.check_circle_outline;
        label = 'Revisada';
      case 'pendiente_revision':
        bg = AbakoColors.statusAgotadoBg;
        fg = AbakoColors.statusAgotadoText;
        icon = Icons.error_outline;
        label = 'Pendiente';
      case 'anulada':
        bg = AbakoColors.creamOuter;
        fg = AbakoColors.textMuted;
        icon = Icons.block_outlined;
        label = 'Anulada';
      default:
        bg = AbakoColors.creamOuter;
        fg = AbakoColors.textMuted;
        icon = Icons.check_outlined;
        label = 'Completada';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _LineaRow extends StatelessWidget {
  const _LineaRow({
    required this.nombre,
    required this.cantidad,
    required this.stockActual,
  });
  final String nombre;
  final double cantidad;
  final double stockActual;

  @override
  Widget build(BuildContext context) {
    final causante = stockActual < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: colorOf(nombre), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(monoOf(nombre),
                style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nombre,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                Text('Vendidas: ${_fmtQty(cantidad)}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: causante ? AbakoColors.statusAgotadoBg : AbakoColors.statusOkBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              'Stock: ${_fmtQty(stockActual)}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: causante ? AbakoColors.statusAgotadoText : AbakoColors.statusOkText),
            ),
          ),
        ],
      ),
    );
  }
}
