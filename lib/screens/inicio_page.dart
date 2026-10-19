import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/product_avatar.dart';
import 'caja_page.dart';
import 'historial_ventas_page.dart';
import 'revision_page.dart';
import 'venta_detalle_page.dart';

const _diasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _fmtFecha(DateTime d) => '${_diasSemana[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}';

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

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _CajaBannerInfo {
  const _CajaBannerInfo(this.mensaje, this.urgente);
  final String mensaje;
  final bool urgente;
}

// Ver feature "Caja" (sesión 2026-08-29): acá solo se recuerda con un banner,
// no se bloquea nada (a diferencia de Punto de Venta, que si bloquea).
_CajaBannerInfo? _cajaBannerInfo(List<Caja> cajas, String? horarioCierre, DateTime ahora) {
  final abierta = cajaAbiertaDe(cajas);
  if (abierta == null) {
    return const _CajaBannerInfo('Todavía no abriste la caja hoy', false);
  }
  if (!_mismoDia(abierta.creadoEn, ahora)) {
    final f = abierta.creadoEn;
    return _CajaBannerInfo(
        'Quedó una caja sin cerrar del ${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}', true);
  }
  if (horaActualPaso(horarioCierre, ahora)) {
    return _CajaBannerInfo('Pasó la hora de cierre ($horarioCierre) y la caja sigue abierta', true);
  }
  return null;
}

const _ventasQuery = 'SELECT id, total, estado, creado_en FROM ventas';
const _movimientosQuery =
    'SELECT producto_id, cantidad, motivo, venta_id, creado_en FROM movimientos_stock';
const _productosQuery =
    'SELECT id, nombre, categoria, stock_minimo, activo, precio, costo FROM productos';
const _perfilesQuery = 'SELECT id, nombre FROM perfiles';
const _tiendaQuery =
    'SELECT nombre, notif_banner_revision, horario_cierre FROM configuracion_tienda ORDER BY creado_en LIMIT 1';

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

class _Movimiento {
  _Movimiento({
    required this.productoId,
    required this.cantidad,
    required this.motivo,
    required this.ventaId,
    required this.creadoEn,
  });
  final String productoId;
  final double cantidad;
  final String motivo;
  final String? ventaId;
  final DateTime creadoEn;

  static _Movimiento fromRow(dynamic row) => _Movimiento(
        productoId: row['producto_id'] as String,
        cantidad: double.tryParse('${row['cantidad']}') ?? 0,
        motivo: row['motivo'] as String,
        ventaId: row['venta_id'] as String?,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

class _ProductoInicio {
  _ProductoInicio({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.stockMinimo,
    required this.activo,
    required this.precio,
    required this.costo,
  });
  final String id;
  final String nombre;
  final String categoria;
  final double stockMinimo;
  final bool activo;
  final double precio;
  final double costo;

  static _ProductoInicio fromRow(dynamic row) => _ProductoInicio(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        categoria: (row['categoria'] as String?)?.isNotEmpty == true
            ? row['categoria'] as String
            : 'Otros',
        stockMinimo: double.tryParse('${row['stock_minimo']}') ?? 0,
        activo: row['activo'] == null ? true : _asBool(row['activo']),
        precio: double.tryParse('${row['precio']}') ?? 0,
        costo: double.tryParse('${row['costo']}') ?? 0,
      );
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  bool _semanas = false; // false = últimos 7 días, true = últimas 4 semanas

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(_ventasQuery),
          builder: (context, ventasSnap) {
            if (!ventasSnap.hasData) return const Center(child: CircularProgressIndicator());
            return StreamBuilder<ResultSet>(
              stream: db.watch(_movimientosQuery),
              builder: (context, movSnap) {
                if (!movSnap.hasData) return const Center(child: CircularProgressIndicator());
                return StreamBuilder<ResultSet>(
                  stream: db.watch(_productosQuery),
                  builder: (context, prodSnap) {
                    if (!prodSnap.hasData) return const Center(child: CircularProgressIndicator());

                    final ventas = ventasSnap.data!.map(_Venta.fromRow).toList();
                    final movimientos = movSnap.data!.map(_Movimiento.fromRow).toList();
                    final productos = prodSnap.data!.map(_ProductoInicio.fromRow).toList();

                    final datos = _DashboardData.compute(ventas, movimientos, productos, _semanas);

                    return StreamBuilder<ResultSet>(
                      stream: db.watch(_perfilesQuery),
                      builder: (context, perfilSnap) {
                        final userId = sb.Supabase.instance.client.auth.currentUser?.id;
                        String? nombreUsuario;
                        if (perfilSnap.hasData) {
                          final fila = perfilSnap.data!
                              .where((r) => r['id'] == userId)
                              .firstOrNull;
                          final n = fila?['nombre'] as String?;
                          if (n != null && n.isNotEmpty) nombreUsuario = n;
                        }

                        return StreamBuilder<ResultSet>(
                          stream: db.watch(_tiendaQuery),
                          builder: (context, tiendaSnap) {
                            var nombreTienda = 'Tienda Centro';
                            var bannerHabilitado = true;
                            String? horarioCierre;
                            if (tiendaSnap.hasData && tiendaSnap.data!.isNotEmpty) {
                              final fila = tiendaSnap.data!.first;
                              nombreTienda = fila['nombre'] as String? ?? 'Tienda Centro';
                              bannerHabilitado = _asBool(fila['notif_banner_revision']);
                              horarioCierre = fila['horario_cierre'] as String?;
                            }

                            return StreamBuilder<ResultSet>(
                              stream: db.watch(cajasQuery),
                              builder: (context, cajasSnap) {
                                final cajaBanner = cajasSnap.hasData
                                    ? _cajaBannerInfo(
                                        cajasSnap.data!.map(Caja.fromRow).toList(), horarioCierre, DateTime.now())
                                    : null;

                                return isDesktop
                                    ? _DesktopInicio(
                                        datos: datos,
                                        semanas: _semanas,
                                        nombreUsuario: nombreUsuario,
                                        nombreTienda: nombreTienda,
                                        bannerHabilitado: bannerHabilitado,
                                        cajaBanner: cajaBanner,
                                        onRangoChanged: (v) => setState(() => _semanas = v),
                                      )
                                    : _MobileInicio(
                                        datos: datos,
                                        semanas: _semanas,
                                        nombreUsuario: nombreUsuario,
                                        nombreTienda: nombreTienda,
                                        bannerHabilitado: bannerHabilitado,
                                        cajaBanner: cajaBanner,
                                        onRangoChanged: (v) => setState(() => _semanas = v),
                                      );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cálculo de métricas (todo en Dart, PowerSync no replica vistas agregadas)
// ---------------------------------------------------------------------------

class _BarraChart {
  const _BarraChart(this.label, this.valor);
  final String label;
  final double valor;
}

class _VendidoTop {
  const _VendidoTop(this.nombre, this.unidades);
  final String nombre;
  final double unidades;
}

class _AlertaStock {
  const _AlertaStock(this.nombre, this.stockActual, this.stockMinimo);
  final String nombre;
  final double stockActual;
  final double stockMinimo;
  bool get agotado => stockActual <= 0;
}

class _DashboardData {
  _DashboardData({
    required this.totalHoy,
    required this.totalAyer,
    required this.ticketsHoy,
    required this.ticketsAyer,
    required this.vendidosHoy,
    required this.vendidosAyer,
    required this.gananciaHoy,
    required this.gananciaAyer,
    required this.serie,
    required this.masVendidosHoy,
    required this.ventasRecientes,
    required this.alertasStock,
    required this.pendientesRevision,
  });

  final double totalHoy;
  final double totalAyer;
  final int ticketsHoy;
  final int ticketsAyer;
  final double vendidosHoy;
  final double vendidosAyer;
  final double gananciaHoy;
  final double gananciaAyer;
  final List<_BarraChart> serie;
  final List<_VendidoTop> masVendidosHoy;
  final List<_Venta> ventasRecientes;
  final List<_AlertaStock> alertasStock;
  final int pendientesRevision;

  double get ticketPromedioHoy => ticketsHoy == 0 ? 0 : totalHoy / ticketsHoy;
  double get ticketPromedioAyer => ticketsAyer == 0 ? 0 : totalAyer / ticketsAyer;

  static _DashboardData compute(
    List<_Venta> ventas,
    List<_Movimiento> movimientos,
    List<_ProductoInicio> productos,
    bool semanas,
  ) {
    final ahora = DateTime.now();
    final ayer = ahora.subtract(const Duration(days: 1));

    // Una venta anulada no cuenta en ninguna estadística (pero sigue visible
    // en "Ventas recientes", con badge, para trazabilidad) — ver flujo de
    // anulación en venta_detalle_page.dart.
    final anuladaIds = ventas.where((v) => v.estado == 'anulada').map((v) => v.id).toSet();
    final ventasValidas = ventas.where((v) => !anuladaIds.contains(v.id)).toList();
    final movimientosValidos =
        movimientos.where((m) => m.ventaId == null || !anuladaIds.contains(m.ventaId)).toList();

    final ventasHoy = ventasValidas.where((v) => _mismoDia(v.creadoEn, ahora)).toList();
    final ventasAyer = ventasValidas.where((v) => _mismoDia(v.creadoEn, ayer)).toList();
    final totalHoy = ventasHoy.fold(0.0, (t, v) => t + v.total);
    final totalAyer = ventasAyer.fold(0.0, (t, v) => t + v.total);

    final ventasMotivo = movimientosValidos.where((m) => m.motivo == 'venta');
    double unidadesEn(DateTime dia) => ventasMotivo
        .where((m) => _mismoDia(m.creadoEn, dia))
        .fold(0.0, (t, m) => t - m.cantidad);
    final vendidosHoy = unidadesEn(ahora);
    final vendidosAyer = unidadesEn(ayer);

    // Ganancia = precio de venta − costo, por unidad vendida. Igual que el
    // resto de la app (ver Punto de Venta), se valoriza con el costo/precio
    // ACTUAL del producto, no hay costo histórico guardado por línea.
    final margenPorId = {for (final p in productos) p.id: p.precio - p.costo};
    double gananciaEn(DateTime dia) => ventasMotivo
        .where((m) => _mismoDia(m.creadoEn, dia))
        .fold(0.0, (t, m) => t - m.cantidad * (margenPorId[m.productoId] ?? 0));
    final gananciaHoy = gananciaEn(ahora);
    final gananciaAyer = gananciaEn(ayer);

    // Serie del gráfico: últimos 7 días o últimas 4 ventanas de 7 días.
    final serie = <_BarraChart>[];
    if (semanas) {
      for (var w = 3; w >= 0; w--) {
        final fin = ahora.subtract(Duration(days: 7 * w));
        final inicio = fin.subtract(const Duration(days: 6));
        final total = ventasValidas
            .where((v) =>
                !v.creadoEn.isBefore(DateTime(inicio.year, inicio.month, inicio.day)) &&
                v.creadoEn.isBefore(DateTime(fin.year, fin.month, fin.day + 1)))
            .fold(0.0, (t, v) => t + v.total);
        serie.add(_BarraChart(w == 0 ? 'Esta sem.' : '-$w sem', total));
      }
    } else {
      for (var d = 6; d >= 0; d--) {
        final dia = ahora.subtract(Duration(days: d));
        final total = ventasValidas
            .where((v) => _mismoDia(v.creadoEn, dia))
            .fold(0.0, (t, v) => t + v.total);
        serie.add(_BarraChart(_diasSemana[dia.weekday - 1].substring(0, 3), total));
      }
    }

    final nombrePorId = {for (final p in productos) p.id: p.nombre};
    final unidadesPorProducto = <String, double>{};
    for (final m in ventasMotivo.where((m) => _mismoDia(m.creadoEn, ahora))) {
      unidadesPorProducto[m.productoId] = (unidadesPorProducto[m.productoId] ?? 0) - m.cantidad;
    }
    final masVendidosHoy = unidadesPorProducto.entries
        .map((e) => _VendidoTop(nombrePorId[e.key] ?? 'Producto', e.value))
        .toList()
      ..sort((a, b) => b.unidades.compareTo(a.unidades));

    final ventasRecientes = List<_Venta>.from(ventas)
      ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

    final stockPorProducto = <String, double>{};
    for (final m in movimientos) {
      stockPorProducto[m.productoId] = (stockPorProducto[m.productoId] ?? 0) + m.cantidad;
    }
    final alertasStock = productos
        .where((p) => p.activo)
        .map((p) => _AlertaStock(p.nombre, stockPorProducto[p.id] ?? 0, p.stockMinimo))
        .where((a) => a.stockActual <= 0 || a.stockActual <= a.stockMinimo)
        .toList()
      ..sort((a, b) {
        if (a.agotado != b.agotado) return a.agotado ? -1 : 1;
        return a.stockActual.compareTo(b.stockActual);
      });

    return _DashboardData(
      totalHoy: totalHoy,
      totalAyer: totalAyer,
      ticketsHoy: ventasHoy.length,
      ticketsAyer: ventasAyer.length,
      vendidosHoy: vendidosHoy,
      vendidosAyer: vendidosAyer,
      gananciaHoy: gananciaHoy,
      gananciaAyer: gananciaAyer,
      serie: serie,
      masVendidosHoy: masVendidosHoy.take(5).toList(),
      ventasRecientes: ventasRecientes.take(8).toList(),
      alertasStock: alertasStock.take(5).toList(),
      pendientesRevision: ventas.where((v) => v.estado == 'pendiente_revision').length,
    );
  }
}

// ---------------------------------------------------------------------------
// Escritorio
// ---------------------------------------------------------------------------

class _DesktopInicio extends StatelessWidget {
  const _DesktopInicio({
    required this.datos,
    required this.semanas,
    required this.nombreUsuario,
    required this.nombreTienda,
    required this.bannerHabilitado,
    required this.cajaBanner,
    required this.onRangoChanged,
  });
  final _DashboardData datos;
  final bool semanas;
  final String? nombreUsuario;
  final String nombreTienda;
  final bool bannerHabilitado;
  final _CajaBannerInfo? cajaBanner;
  final ValueChanged<bool> onRangoChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Saludo(nombreUsuario: nombreUsuario, nombreTienda: nombreTienda),
            if (cajaBanner != null) ...[
              const SizedBox(height: 18),
              _CajaBanner(info: cajaBanner!),
            ],
            if (bannerHabilitado && datos.pendientesRevision > 0) ...[
              const SizedBox(height: 18),
              _RevisionBanner(cantidad: datos.pendientesRevision),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    label: 'Ventas de hoy',
                    value: _fmtMoney(datos.totalHoy),
                    hoy: datos.totalHoy,
                    ayer: datos.totalAyer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiTile(
                    label: 'Tickets',
                    value: '${datos.ticketsHoy}',
                    hoy: datos.ticketsHoy.toDouble(),
                    ayer: datos.ticketsAyer.toDouble(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiTile(
                    label: 'Ticket promedio',
                    value: _fmtMoney(datos.ticketPromedioHoy),
                    hoy: datos.ticketPromedioHoy,
                    ayer: datos.ticketPromedioAyer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiTile(
                    label: 'Productos vendidos',
                    value: _fmtQty(datos.vendidosHoy),
                    hoy: datos.vendidosHoy,
                    ayer: datos.vendidosAyer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiTile(
                    label: 'Ganancia de hoy',
                    value: _fmtMoney(datos.gananciaHoy),
                    hoy: datos.gananciaHoy,
                    ayer: datos.gananciaAyer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Ventas',
                                      style: GoogleFonts.bricolageGrotesque(
                                          fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.textDark)),
                                ),
                                _RangoToggle(semanas: semanas, onChanged: onRangoChanged),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _BarChart(serie: datos.serie),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DashboardCard(
                        child: _MasVendidosList(items: datos.masVendidosHoy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardCard(child: _VentasRecientesList(ventas: datos.ventasRecientes)),
                      const SizedBox(height: 16),
                      _DashboardCard(child: _AlertasStockList(alertas: datos.alertasStock)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Móvil
// ---------------------------------------------------------------------------

class _MobileInicio extends StatelessWidget {
  const _MobileInicio({
    required this.datos,
    required this.semanas,
    required this.nombreUsuario,
    required this.nombreTienda,
    required this.bannerHabilitado,
    required this.cajaBanner,
    required this.onRangoChanged,
  });
  final _DashboardData datos;
  final bool semanas;
  final String? nombreUsuario;
  final String nombreTienda;
  final bool bannerHabilitado;
  final _CajaBannerInfo? cajaBanner;
  final ValueChanged<bool> onRangoChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AbakoColors.panelGreen,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 18),
          child: _Saludo(dark: true, nombreUsuario: nombreUsuario, nombreTienda: nombreTienda),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cajaBanner != null) ...[
                  _CajaBanner(info: cajaBanner!),
                  const SizedBox(height: 16),
                ],
                if (bannerHabilitado && datos.pendientesRevision > 0) ...[
                  _RevisionBanner(cantidad: datos.pendientesRevision),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _KpiTile(
                        label: 'Ventas de hoy',
                        value: _fmtMoney(datos.totalHoy),
                        hoy: datos.totalHoy,
                        ayer: datos.totalAyer,
                        width: 168,
                      ),
                      _KpiTile(
                        label: 'Tickets',
                        value: '${datos.ticketsHoy}',
                        hoy: datos.ticketsHoy.toDouble(),
                        ayer: datos.ticketsAyer.toDouble(),
                        width: 130,
                      ),
                      _KpiTile(
                        label: 'Ticket promedio',
                        value: _fmtMoney(datos.ticketPromedioHoy),
                        hoy: datos.ticketPromedioHoy,
                        ayer: datos.ticketPromedioAyer,
                        width: 168,
                      ),
                      _KpiTile(
                        label: 'Prod. vendidos',
                        value: _fmtQty(datos.vendidosHoy),
                        hoy: datos.vendidosHoy,
                        ayer: datos.vendidosAyer,
                        width: 150,
                      ),
                      _KpiTile(
                        label: 'Ganancia de hoy',
                        value: _fmtMoney(datos.gananciaHoy),
                        hoy: datos.gananciaHoy,
                        ayer: datos.gananciaAyer,
                        width: 168,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DashboardCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Ventas',
                                style: GoogleFonts.bricolageGrotesque(
                                    fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
                          ),
                          _RangoToggle(semanas: semanas, onChanged: onRangoChanged),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BarChart(serie: datos.serie),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DashboardCard(child: _MasVendidosList(items: datos.masVendidosHoy)),
                const SizedBox(height: 16),
                _DashboardCard(child: _VentasRecientesList(ventas: datos.ventasRecientes)),
                const SizedBox(height: 16),
                _DashboardCard(child: _AlertasStockList(alertas: datos.alertasStock)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compartidos
// ---------------------------------------------------------------------------

class _RevisionBanner extends StatelessWidget {
  const _RevisionBanner({required this.cantidad});
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AbakoColors.statusAgotadoBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RevisionPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: AbakoColors.statusAgotadoText, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cantidad == 1
                      ? '1 venta necesita revisión por sobregiro de stock'
                      : '$cantidad ventas necesitan revisión por sobregiro de stock',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.statusAgotadoText),
                ),
              ),
              Text('Ver',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AbakoColors.statusAgotadoText)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: AbakoColors.statusAgotadoText, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _CajaBanner extends StatelessWidget {
  const _CajaBanner({required this.info});
  final _CajaBannerInfo info;

  @override
  Widget build(BuildContext context) {
    final bg = info.urgente ? AbakoColors.statusAgotadoBg : AbakoColors.statusBajoBg;
    final fg = info.urgente ? AbakoColors.statusAgotadoText : AbakoColors.statusBajoText;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: AbakoColors.creamOuter,
            appBar: AppBar(
              backgroundColor: AbakoColors.panelGreen,
              foregroundColor: AbakoColors.creamText,
              elevation: 0,
              title: Text('Caja',
                  style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.creamText)),
            ),
            body: const CajaPage(),
          ),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.point_of_sale_outlined, color: fg, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(info.mensaje,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
              ),
              Text('Ir', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: fg, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Saludo extends StatelessWidget {
  const _Saludo({this.dark = false, required this.nombreUsuario, required this.nombreTienda});
  final bool dark;
  final String? nombreUsuario;
  final String nombreTienda;

  @override
  Widget build(BuildContext context) {
    final email = sb.Supabase.instance.client.auth.currentUser?.email ?? '';
    final nombre = nombreUsuario ?? (email.contains('@') ? email.split('@').first : email);
    final textColor = dark ? AbakoColors.creamText : AbakoColors.textDark;
    final mutedColor = dark ? AbakoColors.creamText.withValues(alpha: 0.75) : AbakoColors.textFaint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hola, $nombre',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: dark ? 21 : 27, color: textColor)),
        const SizedBox(height: 3),
        Text('$nombreTienda · ${_fmtFecha(DateTime.now())}',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: mutedColor)),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, required this.hoy, required this.ayer, this.width});
  final String label;
  final String value;
  final double hoy;
  final double ayer;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final bool? subio = ayer == 0 && hoy == 0 ? null : (ayer == 0 ? true : hoy >= ayer);
    final String delta = ayer == 0
        ? (hoy == 0 ? '—' : 'nuevo')
        : '${hoy >= ayer ? '+' : ''}${(((hoy - ayer) / ayer) * 100).round()}%';

    final card = Container(
      margin: width != null ? const EdgeInsets.only(right: 12) : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
          // El valor y el delta van apilados (no en una Row) para que el
          // número nunca compita por ancho con el badge "nuevo"/"+X%" — con
          // montos grandes esa combinación no entraba en el ancho fijo de
          // la tarjeta en mobile y el valor se veía truncado ("$13,...").
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w700, fontSize: 22, color: AbakoColors.textDark)),
              const SizedBox(height: 3),
              Text(delta,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: subio == null
                          ? AbakoColors.textFaint
                          : (subio ? AbakoColors.statusOkText : AbakoColors.statusAgotadoText))),
            ],
          ),
        ],
      ),
    );

    return width != null ? SizedBox(width: width, child: card) : card;
  }
}

class _RangoToggle extends StatelessWidget {
  const _RangoToggle({required this.semanas, required this.onChanged});
  final bool semanas;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget opt(String label, bool value) {
      final selected = semanas == value;
      return Material(
        color: selected ? AbakoColors.accentGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AbakoColors.textLabel)),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AbakoColors.cream,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AbakoColors.inputBorder, width: 1.5),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [opt('7 días', false), opt('4 semanas', true)]),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.serie});
  final List<_BarraChart> serie;

  @override
  Widget build(BuildContext context) {
    final maxValor = serie.fold(0.0, (m, b) => b.valor > m ? b.valor : m);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in serie)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      b.valor == 0 ? '' : _fmtMoney(b.valor),
                      style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AbakoColors.textFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: maxValor == 0 ? 4 : (b.valor / maxValor) * 92 + 4,
                      decoration: BoxDecoration(
                        color: AbakoColors.accentGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(b.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AbakoColors.textFaint)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MasVendidosList extends StatelessWidget {
  const _MasVendidosList({required this.items});
  final List<_VendidoTop> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Más vendidos hoy',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text('Todavía no hay ventas hoy.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: colorOf(it.nombre), borderRadius: BorderRadius.circular(9)),
                    alignment: Alignment.center,
                    child: Text(monoOf(it.nombre),
                        style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(it.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                  ),
                  Text('${_fmtQty(it.unidades)} un.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5, fontWeight: FontWeight.w600, color: AbakoColors.textFaint)),
                ],
              ),
            ),
      ],
    );
  }
}

class _VentasRecientesList extends StatelessWidget {
  const _VentasRecientesList({required this.ventas});
  final List<_Venta> ventas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Ventas recientes',
                  style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistorialVentasPage()),
              ),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero),
              child: Text('Ver todas',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AbakoColors.accentGreenHover)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (ventas.isEmpty)
          Text('Todavía no hay ventas registradas.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final v in ventas)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => VentaDetallePage(ventaId: v.id)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_fmtHora(v.creadoEn),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
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
                        style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w700, fontSize: 14, color: AbakoColors.textDark)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: AbakoColors.textFaint),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  String _fmtHora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _AlertasStockList extends StatelessWidget {
  const _AlertasStockList({required this.alertas});
  final List<_AlertaStock> alertas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alertas de stock',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 14),
        if (alertas.isEmpty)
          Text('Todo el stock está en orden.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final a in alertas)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: a.agotado ? AbakoColors.statusAgotadoDot : AbakoColors.statusBajoDot,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(a.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: a.agotado ? AbakoColors.statusAgotadoBg : AbakoColors.statusBajoBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      a.agotado ? 'Agotado' : '${_fmtQty(a.stockActual)} un.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: a.agotado ? AbakoColors.statusAgotadoText : AbakoColors.statusBajoText),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
