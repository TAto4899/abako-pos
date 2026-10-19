import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/product_avatar.dart';
import 'historial_ventas_page.dart';

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

String _fmtDiaCorto(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

const _ventasQuery = 'SELECT id, total, estado, creado_en FROM ventas';
const _movimientosQuery =
    'SELECT producto_id, cantidad, motivo, venta_id, creado_en FROM movimientos_stock';
const _productosQuery = 'SELECT id, nombre, categoria, precio, costo FROM productos';
const _pagosQuery = 'SELECT venta_id, metodo, monto, creado_en FROM pagos_venta';
const _cajasQuery =
    'SELECT id, monto_cierre_esperado, monto_cierre_real, diferencia, estado, cerrada_en FROM cajas';

enum _Periodo { hoy, siete, treinta, mes, anio, personalizado }

const _mesesCortos = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

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

class _Producto {
  _Producto({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.costo,
  });
  final String id;
  final String nombre;
  final String categoria;
  final double precio;
  final double costo;

  static _Producto fromRow(dynamic row) => _Producto(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        categoria: (row['categoria'] as String?)?.isNotEmpty == true ? row['categoria'] as String : 'Otros',
        precio: double.tryParse('${row['precio']}') ?? 0,
        costo: double.tryParse('${row['costo']}') ?? 0,
      );
}

class _Pago {
  _Pago({required this.ventaId, required this.metodo, required this.monto, required this.creadoEn});
  final String ventaId;
  final String metodo;
  final double monto;
  final DateTime creadoEn;

  static _Pago fromRow(dynamic row) => _Pago(
        ventaId: row['venta_id'] as String,
        metodo: row['metodo'] as String,
        monto: double.tryParse('${row['monto']}') ?? 0,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

/// Un cierre de caja (solo se cuentan las cerradas — una caja `abierta` no
/// tiene diferencia todavía). Se filtra por `cerrada_en`, no por `creado_en`,
/// porque lo que importa acá es cuándo se detectó la diferencia, no cuándo
/// se abrió la caja.
class _CajaCierre {
  const _CajaCierre({required this.esperado, required this.real, required this.diferencia, required this.cerradaEn});
  final double esperado;
  final double real;
  final double diferencia;
  final DateTime cerradaEn;

  static _CajaCierre? fromRow(dynamic row) {
    if (row['estado'] != 'cerrada' || row['cerrada_en'] == null) return null;
    return _CajaCierre(
      esperado: double.tryParse('${row['monto_cierre_esperado']}') ?? 0,
      real: double.tryParse('${row['monto_cierre_real']}') ?? 0,
      diferencia: double.tryParse('${row['diferencia']}') ?? 0,
      cerradaEn: DateTime.parse(row['cerrada_en'] as String),
    );
  }
}

class _Rango {
  const _Rango(this.start, this.end, this.prevStart, this.prevEnd);
  final DateTime start; // inclusive
  final DateTime end; // exclusivo
  final DateTime prevStart;
  final DateTime prevEnd;

  bool contiene(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  bool contienePrev(DateTime d) => !d.isBefore(prevStart) && d.isBefore(prevEnd);
}

// El "período anterior" para comparar KPIs es siempre una ventana rolling de
// la misma duración inmediatamente antes del inicio del rango actual (no mes
// calendario anterior) — misma simplificación deliberada que ya usa Inicio
// para "últimas 4 semanas" (evita la complejidad de calendarios/semanas ISO).
_Rango _calcularRango(_Periodo p, DateTime ahora, DateTimeRange? personalizado) {
  final hoyInicio = DateTime(ahora.year, ahora.month, ahora.day);
  final finExclusivo = hoyInicio.add(const Duration(days: 1));
  late DateTime start;
  late DateTime end;
  switch (p) {
    case _Periodo.hoy:
      start = hoyInicio;
      end = finExclusivo;
    case _Periodo.siete:
      start = hoyInicio.subtract(const Duration(days: 6));
      end = finExclusivo;
    case _Periodo.treinta:
      start = hoyInicio.subtract(const Duration(days: 29));
      end = finExclusivo;
    case _Periodo.mes:
      start = DateTime(ahora.year, ahora.month, 1);
      end = finExclusivo;
    case _Periodo.anio:
      start = DateTime(ahora.year, 1, 1);
      end = finExclusivo;
    case _Periodo.personalizado:
      final r = personalizado ?? DateTimeRange(start: hoyInicio.subtract(const Duration(days: 6)), end: hoyInicio);
      start = DateTime(r.start.year, r.start.month, r.start.day);
      // showDateRangePicker devuelve fechas sin hora, ambas inclusive — se sube
      // el fin al día siguiente para que el rango [start, end) incluya el día
      // final completo.
      end = DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1));
  }
  final dur = end.difference(start);
  return _Rango(start, end, start.subtract(dur), start);
}

class _Bucket {
  const _Bucket(this.label, this.valor);
  final String label;
  final double valor;
}

List<_Bucket> _construirBuckets(_Rango rango, List<_Venta> ventas) {
  final totalDias = rango.end.difference(rango.start).inDays;
  final buckets = <_Bucket>[];

  double totalEntre(DateTime a, DateTime b) => ventas
      .where((v) => !v.creadoEn.isBefore(a) && v.creadoEn.isBefore(b))
      .fold(0.0, (t, v) => t + v.total);

  if (totalDias <= 10) {
    for (var d = 0; d < totalDias; d++) {
      final diaInicio = rango.start.add(Duration(days: d));
      final diaFin = diaInicio.add(const Duration(days: 1));
      buckets.add(_Bucket(_fmtDiaCorto(diaInicio), totalEntre(diaInicio, diaFin)));
    }
  } else if (totalDias <= 70) {
    var cursor = rango.start;
    while (cursor.isBefore(rango.end)) {
      final siguiente = cursor.add(const Duration(days: 7));
      final ventanaFin = siguiente.isBefore(rango.end) ? siguiente : rango.end;
      buckets.add(_Bucket(_fmtDiaCorto(cursor), totalEntre(cursor, ventanaFin)));
      cursor = ventanaFin;
    }
  } else {
    // Rangos largos (Este año, personalizado amplio): un bucket por mes
    // calendario en vez de por semana, para no amontonar decenas de barras.
    var cursor = rango.start;
    while (cursor.isBefore(rango.end)) {
      final siguienteMes = DateTime(cursor.year, cursor.month + 1, 1);
      final ventanaFin = siguienteMes.isBefore(rango.end) ? siguienteMes : rango.end;
      buckets.add(_Bucket(_mesesCortos[cursor.month - 1], totalEntre(cursor, ventanaFin)));
      cursor = ventanaFin;
    }
  }
  return buckets;
}

class _CategoriaTotal {
  const _CategoriaTotal(this.categoria, this.monto);
  final String categoria;
  final double monto;
}

class _ProductoTop {
  const _ProductoTop(this.nombre, this.unidades);
  final String nombre;
  final double unidades;
}

class _MetodoTotal {
  const _MetodoTotal(this.metodo, this.monto);
  final String metodo;
  final double monto;
}

class _DevolucionItem {
  const _DevolucionItem(this.nombre, this.cantidad, this.creadoEn);
  final String nombre;
  final double cantidad;
  final DateTime creadoEn;
}

class _ReportData {
  _ReportData({
    required this.ventasTotal,
    required this.ventasTotalPrev,
    required this.tickets,
    required this.ticketsPrev,
    required this.productosVendidos,
    required this.productosVendidosPrev,
    required this.devolucionesMonto,
    required this.devolucionesMontoPrev,
    required this.ganancia,
    required this.gananciaPrev,
    required this.serie,
    required this.porCategoria,
    required this.masVendidos,
    required this.porMetodo,
    required this.devoluciones,
    required this.cajasCerradas,
    required this.cajasConDiferencia,
    required this.diferenciaCajaTotal,
  });

  final double ventasTotal, ventasTotalPrev;
  final int tickets, ticketsPrev;
  final double productosVendidos, productosVendidosPrev;
  final double devolucionesMonto, devolucionesMontoPrev;
  final double ganancia, gananciaPrev;
  final List<_Bucket> serie;
  final List<_CategoriaTotal> porCategoria;
  final List<_ProductoTop> masVendidos;
  final List<_MetodoTotal> porMetodo;
  final List<_DevolucionItem> devoluciones;
  final List<_CajaCierre> cajasCerradas;
  final int cajasConDiferencia;
  final double diferenciaCajaTotal;

  double get ticketPromedio => tickets == 0 ? 0 : ventasTotal / tickets;
  double get ticketPromedioPrev => ticketsPrev == 0 ? 0 : ventasTotalPrev / ticketsPrev;

  static _ReportData compute(
    _Rango rango,
    List<_Venta> ventas,
    List<_Movimiento> movimientos,
    List<_Producto> productos,
    List<_Pago> pagos,
    List<_CajaCierre> cajas,
  ) {
    final precioPorId = {for (final p in productos) p.id: p.precio};
    final margenPorId = {for (final p in productos) p.id: p.precio - p.costo};
    final nombrePorId = {for (final p in productos) p.id: p.nombre};
    final categoriaPorId = {for (final p in productos) p.id: p.categoria};

    // Una venta anulada no cuenta en ningún reporte — ver flujo de anulación
    // en venta_detalle_page.dart.
    final anuladaIds = ventas.where((v) => v.estado == 'anulada').map((v) => v.id).toSet();
    final ventasValidas = ventas.where((v) => !anuladaIds.contains(v.id)).toList();

    final ventasActual = ventasValidas.where((v) => rango.contiene(v.creadoEn)).toList();
    final ventasPrev = ventasValidas.where((v) => rango.contienePrev(v.creadoEn)).toList();
    final ventasTotal = ventasActual.fold(0.0, (t, v) => t + v.total);
    final ventasTotalPrev = ventasPrev.fold(0.0, (t, v) => t + v.total);

    final ventasMov = movimientos.where(
        (m) => m.motivo == 'venta' && (m.ventaId == null || !anuladaIds.contains(m.ventaId)));
    final ventasMovActual = ventasMov.where((m) => rango.contiene(m.creadoEn)).toList();
    final ventasMovPrev = ventasMov.where((m) => rango.contienePrev(m.creadoEn)).toList();
    final productosVendidos = ventasMovActual.fold(0.0, (t, m) => t - m.cantidad);
    final productosVendidosPrev = ventasMovPrev.fold(0.0, (t, m) => t - m.cantidad);

    final devolucionesMov = movimientos.where((m) => m.motivo == 'devolucion');
    final devolucionesActual = devolucionesMov.where((m) => rango.contiene(m.creadoEn)).toList();
    final devolucionesPrev = devolucionesMov.where((m) => rango.contienePrev(m.creadoEn)).toList();
    // Aproximación: se valoriza con el precio ACTUAL del producto (no hay
    // precio histórico por línea guardado), igual que "Ventas por categoría"
    // más abajo. Puede diferir un poco si el precio cambió desde la venta.
    double valorizar(Iterable<_Movimiento> movs) =>
        movs.fold(0.0, (t, m) => t + m.cantidad * (precioPorId[m.productoId] ?? 0));
    final devolucionesMonto = valorizar(devolucionesActual);
    final devolucionesMontoPrev = valorizar(devolucionesPrev);

    // Ganancia = precio de venta − costo, por unidad vendida. Misma
    // aproximación de precio/costo ACTUAL de arriba (no hay costo histórico
    // por línea de venta).
    double gananciaDe(Iterable<_Movimiento> movs) =>
        movs.fold(0.0, (t, m) => t - m.cantidad * (margenPorId[m.productoId] ?? 0));
    final ganancia = gananciaDe(ventasMovActual);
    final gananciaPrev = gananciaDe(ventasMovPrev);

    final serie = _construirBuckets(rango, ventasActual);

    final categoriaMap = <String, double>{};
    for (final m in ventasMovActual) {
      final cat = categoriaPorId[m.productoId] ?? 'Otros';
      final monto = -m.cantidad * (precioPorId[m.productoId] ?? 0);
      categoriaMap[cat] = (categoriaMap[cat] ?? 0) + monto;
    }
    final porCategoria = categoriaMap.entries.map((e) => _CategoriaTotal(e.key, e.value)).toList()
      ..sort((a, b) => b.monto.compareTo(a.monto));

    final unidadesPorProducto = <String, double>{};
    for (final m in ventasMovActual) {
      unidadesPorProducto[m.productoId] = (unidadesPorProducto[m.productoId] ?? 0) - m.cantidad;
    }
    final masVendidos = unidadesPorProducto.entries
        .map((e) => _ProductoTop(nombrePorId[e.key] ?? 'Producto', e.value))
        .toList()
      ..sort((a, b) => b.unidades.compareTo(a.unidades));

    final pagosActual = pagos.where((p) => rango.contiene(p.creadoEn) && !anuladaIds.contains(p.ventaId));
    final metodoMap = <String, double>{};
    for (final p in pagosActual) {
      metodoMap[p.metodo] = (metodoMap[p.metodo] ?? 0) + p.monto;
    }
    final porMetodo = metodoMap.entries.map((e) => _MetodoTotal(e.key, e.value)).toList()
      ..sort((a, b) => b.monto.compareTo(a.monto));

    final devoluciones = devolucionesActual
        .map((m) => _DevolucionItem(nombrePorId[m.productoId] ?? 'Producto', m.cantidad, m.creadoEn))
        .toList()
      ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

    final cajasActual = cajas.where((c) => rango.contiene(c.cerradaEn)).toList()
      ..sort((a, b) => b.cerradaEn.compareTo(a.cerradaEn));
    final cajasConDiferencia = cajasActual.where((c) => c.diferencia != 0).length;
    final diferenciaCajaTotal = cajasActual.fold(0.0, (t, c) => t + c.diferencia);

    return _ReportData(
      ventasTotal: ventasTotal,
      ventasTotalPrev: ventasTotalPrev,
      tickets: ventasActual.length,
      ticketsPrev: ventasPrev.length,
      productosVendidos: productosVendidos,
      productosVendidosPrev: productosVendidosPrev,
      devolucionesMonto: devolucionesMonto,
      devolucionesMontoPrev: devolucionesMontoPrev,
      ganancia: ganancia,
      gananciaPrev: gananciaPrev,
      serie: serie,
      porCategoria: porCategoria,
      masVendidos: masVendidos.take(5).toList(),
      porMetodo: porMetodo,
      devoluciones: devoluciones.take(8).toList(),
      cajasCerradas: cajasActual,
      cajasConDiferencia: cajasConDiferencia,
      diferenciaCajaTotal: diferenciaCajaTotal,
    );
  }
}

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  _Periodo _periodo = _Periodo.siete;
  DateTimeRange? _rangoPersonalizado;

  Future<void> _elegirPeriodo(_Periodo p) async {
    if (p == _Periodo.personalizado) {
      final ahora = DateTime.now();
      final elegido = await showDateRangePicker(
        context: context,
        firstDate: DateTime(ahora.year - 5),
        lastDate: ahora,
        initialDateRange: _rangoPersonalizado ??
            DateTimeRange(start: ahora.subtract(const Duration(days: 6)), end: ahora),
      );
      if (elegido != null) {
        setState(() {
          _periodo = p;
          _rangoPersonalizado = elegido;
        });
      }
      return;
    }
    setState(() => _periodo = p);
  }

  @override
  Widget build(BuildContext context) {
    final rango = _calcularRango(_periodo, DateTime.now(), _rangoPersonalizado);
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
                    return StreamBuilder<ResultSet>(
                      stream: db.watch(_pagosQuery),
                      builder: (context, pagosSnap) {
                        if (!pagosSnap.hasData) return const Center(child: CircularProgressIndicator());
                        return StreamBuilder<ResultSet>(
                          stream: db.watch(_cajasQuery),
                          builder: (context, cajasSnap) {
                            if (!cajasSnap.hasData) return const Center(child: CircularProgressIndicator());

                            final datos = _ReportData.compute(
                              rango,
                              ventasSnap.data!.map(_Venta.fromRow).toList(),
                              movSnap.data!.map(_Movimiento.fromRow).toList(),
                              prodSnap.data!.map(_Producto.fromRow).toList(),
                              pagosSnap.data!.map(_Pago.fromRow).toList(),
                              cajasSnap.data!.map(_CajaCierre.fromRow).whereType<_CajaCierre>().toList(),
                            );

                            return isDesktop
                                ? _DesktopReportes(
                                    datos: datos,
                                    periodo: _periodo,
                                    rangoPersonalizado: _rangoPersonalizado,
                                    onPeriodoChanged: _elegirPeriodo,
                                  )
                                : _MobileReportes(
                                    datos: datos,
                                    periodo: _periodo,
                                    rangoPersonalizado: _rangoPersonalizado,
                                    onPeriodoChanged: _elegirPeriodo,
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

class _DesktopReportes extends StatelessWidget {
  const _DesktopReportes({
    required this.datos,
    required this.periodo,
    required this.rangoPersonalizado,
    required this.onPeriodoChanged,
  });
  final _ReportData datos;
  final _Periodo periodo;
  final DateTimeRange? rangoPersonalizado;
  final void Function(_Periodo) onPeriodoChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Reportes',
                      style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 24, color: AbakoColors.textDark)),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistorialVentasPage())),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AbakoColors.textLabel,
                    side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: Text('Ver todas las ventas', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PeriodoToggle(periodo: periodo, rangoPersonalizado: rangoPersonalizado, onChanged: onPeriodoChanged),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _KpiTile(label: 'Ventas totales', value: _fmtMoney(datos.ventasTotal), hoy: datos.ventasTotal, ayer: datos.ventasTotalPrev)),
                const SizedBox(width: 16),
                Expanded(child: _KpiTile(label: 'Tickets', value: '${datos.tickets}', hoy: datos.tickets.toDouble(), ayer: datos.ticketsPrev.toDouble())),
                const SizedBox(width: 16),
                Expanded(child: _KpiTile(label: 'Ticket promedio', value: _fmtMoney(datos.ticketPromedio), hoy: datos.ticketPromedio, ayer: datos.ticketPromedioPrev)),
                const SizedBox(width: 16),
                Expanded(child: _KpiTile(label: 'Ganancia', value: _fmtMoney(datos.ganancia), hoy: datos.ganancia, ayer: datos.gananciaPrev)),
                const SizedBox(width: 16),
                Expanded(child: _KpiTile(label: 'Devoluciones', value: _fmtMoney(datos.devolucionesMonto), hoy: datos.devolucionesMonto, ayer: datos.devolucionesMontoPrev, invertirColor: true)),
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
                      if (datos.serie.length > 1) ...[
                        _DashboardCard(child: _SerieChart(serie: datos.serie)),
                        const SizedBox(height: 16),
                      ],
                      _DashboardCard(child: _CategoriaList(items: datos.porCategoria)),
                      const SizedBox(height: 16),
                      _DashboardCard(child: _MasVendidosList(items: datos.masVendidos)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardCard(child: _MetodoList(items: datos.porMetodo)),
                      const SizedBox(height: 16),
                      _DashboardCard(
                        child: _CajaSection(
                          cajas: datos.cajasCerradas,
                          conDiferencia: datos.cajasConDiferencia,
                          diferenciaTotal: datos.diferenciaCajaTotal,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DashboardCard(child: _DevolucionesList(items: datos.devoluciones)),
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

class _MobileReportes extends StatelessWidget {
  const _MobileReportes({
    required this.datos,
    required this.periodo,
    required this.rangoPersonalizado,
    required this.onPeriodoChanged,
  });
  final _ReportData datos;
  final _Periodo periodo;
  final DateTimeRange? rangoPersonalizado;
  final void Function(_Periodo) onPeriodoChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Reportes',
                      style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 21, color: AbakoColors.textDark)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistorialVentasPage())),
                  icon: const Icon(Icons.receipt_long_outlined, size: 21, color: AbakoColors.textLabel),
                  tooltip: 'Ver todas las ventas',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PeriodoToggle(periodo: periodo, rangoPersonalizado: rangoPersonalizado, onChanged: onPeriodoChanged),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _KpiTile(label: 'Ventas totales', value: _fmtMoney(datos.ventasTotal), hoy: datos.ventasTotal, ayer: datos.ventasTotalPrev, width: 168),
                  _KpiTile(label: 'Tickets', value: '${datos.tickets}', hoy: datos.tickets.toDouble(), ayer: datos.ticketsPrev.toDouble(), width: 130),
                  _KpiTile(label: 'Ticket promedio', value: _fmtMoney(datos.ticketPromedio), hoy: datos.ticketPromedio, ayer: datos.ticketPromedioPrev, width: 168),
                  _KpiTile(label: 'Ganancia', value: _fmtMoney(datos.ganancia), hoy: datos.ganancia, ayer: datos.gananciaPrev, width: 150),
                  _KpiTile(label: 'Devoluciones', value: _fmtMoney(datos.devolucionesMonto), hoy: datos.devolucionesMonto, ayer: datos.devolucionesMontoPrev, width: 150, invertirColor: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (datos.serie.length > 1) ...[
              _DashboardCard(child: _SerieChart(serie: datos.serie)),
              const SizedBox(height: 16),
            ],
            _DashboardCard(child: _CategoriaList(items: datos.porCategoria)),
            const SizedBox(height: 16),
            _DashboardCard(child: _MasVendidosList(items: datos.masVendidos)),
            const SizedBox(height: 16),
            _DashboardCard(child: _MetodoList(items: datos.porMetodo)),
            const SizedBox(height: 16),
            _DashboardCard(
              child: _CajaSection(
                cajas: datos.cajasCerradas,
                conDiferencia: datos.cajasConDiferencia,
                diferenciaTotal: datos.diferenciaCajaTotal,
              ),
            ),
            const SizedBox(height: 16),
            _DashboardCard(child: _DevolucionesList(items: datos.devoluciones)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compartidos
// ---------------------------------------------------------------------------

class _PeriodoToggle extends StatelessWidget {
  const _PeriodoToggle({required this.periodo, required this.rangoPersonalizado, required this.onChanged});
  final _Periodo periodo;
  final DateTimeRange? rangoPersonalizado;
  final void Function(_Periodo) onChanged;

  @override
  Widget build(BuildContext context) {
    final opciones = [
      (_Periodo.hoy, 'Hoy'),
      (_Periodo.siete, '7 días'),
      (_Periodo.treinta, '30 días'),
      (_Periodo.mes, 'Este mes'),
      (_Periodo.anio, 'Este año'),
      (
        _Periodo.personalizado,
        rangoPersonalizado == null
            ? 'Personalizado'
            : '${_fmtDiaCorto(rangoPersonalizado!.start)}–${_fmtDiaCorto(rangoPersonalizado!.end)}',
      ),
    ];

    Widget opt((_Periodo, String) o) {
      final selected = periodo == o.$1;
      return Material(
        color: selected ? AbakoColors.accentGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(o.$1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (o.$1 == _Periodo.personalizado) ...[
                  Icon(Icons.calendar_month_outlined, size: 14, color: selected ? Colors.white : AbakoColors.textLabel),
                  const SizedBox(width: 5),
                ],
                Text(o.$2,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AbakoColors.textLabel)),
              ],
            ),
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
      child: Wrap(spacing: 2, runSpacing: 2, children: opciones.map(opt).toList()),
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
  const _KpiTile({
    required this.label,
    required this.value,
    required this.hoy,
    required this.ayer,
    this.width,
    this.invertirColor = false,
  });
  final String label;
  final String value;
  final double hoy;
  final double ayer;
  final double? width;
  // Para "Devoluciones": subir NO es una buena noticia, invierte los colores.
  final bool invertirColor;

  @override
  Widget build(BuildContext context) {
    final bool? subio = ayer == 0 && hoy == 0 ? null : (ayer == 0 ? true : hoy >= ayer);
    final String delta = ayer == 0
        ? (hoy == 0 ? '—' : 'nuevo')
        : '${hoy >= ayer ? '+' : ''}${(((hoy - ayer) / ayer) * 100).round()}%';
    final bool? esBueno = subio == null ? null : (invertirColor ? !subio : subio);

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
          // Apilado (no en una Row) para que el valor no compita por ancho
          // con el badge de variación — mismo fix que inicio_page.dart
          // (sesión 2026-09-02): con montos grandes se truncaba el número.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 22, color: AbakoColors.textDark)),
              const SizedBox(height: 3),
              Text(delta,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: esBueno == null
                          ? AbakoColors.textFaint
                          : (esBueno ? AbakoColors.statusOkText : AbakoColors.statusAgotadoText))),
            ],
          ),
        ],
      ),
    );

    return width != null ? SizedBox(width: width, child: card) : card;
  }
}

class _SerieChart extends StatelessWidget {
  const _SerieChart({required this.serie});
  final List<_Bucket> serie;

  @override
  Widget build(BuildContext context) {
    final maxValor = serie.fold(0.0, (m, b) => b.valor > m ? b.valor : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ventas en el período',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 18),
        SizedBox(
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
                        Text(b.valor == 0 ? '' : _fmtMoney(b.valor),
                            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AbakoColors.textFaint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Container(
                          height: maxValor == 0 ? 4 : (b.valor / maxValor) * 92 + 4,
                          decoration: BoxDecoration(color: AbakoColors.accentGreen, borderRadius: BorderRadius.circular(6)),
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
        ),
      ],
    );
  }
}

class _CategoriaList extends StatelessWidget {
  const _CategoriaList({required this.items});
  final List<_CategoriaTotal> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0.0, (t, i) => t + i.monto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ventas por categoría',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 4),
        Text('Estimado con el precio actual de cada producto',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textFaint)),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text('Todavía no hay ventas en este período.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(it.categoria,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                      ),
                      Text(_fmtMoney(it.monto),
                          style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AbakoColors.textFaint)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : it.monto / total,
                      minHeight: 6,
                      backgroundColor: AbakoColors.creamOuter,
                      color: AbakoColors.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _MasVendidosList extends StatelessWidget {
  const _MasVendidosList({required this.items});
  final List<_ProductoTop> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Productos más vendidos',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text('Todavía no hay ventas en este período.',
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
                        style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(it.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                  ),
                  Text('${_fmtQty(it.unidades)} un.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AbakoColors.textFaint)),
                ],
              ),
            ),
      ],
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

class _MetodoList extends StatelessWidget {
  const _MetodoList({required this.items});
  final List<_MetodoTotal> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0.0, (t, i) => t + i.monto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Métodos de pago',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text('Todavía no hay pagos en este período.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_iconoMetodo(it.metodo), size: 16, color: AbakoColors.textFaint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(it.metodo,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                      ),
                      Text(_fmtMoney(it.monto),
                          style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AbakoColors.textFaint)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : it.monto / total,
                      minHeight: 6,
                      backgroundColor: AbakoColors.creamOuter,
                      color: AbakoColors.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Diferencias de caja (esperado vs. real al cerrar) dentro del período —
/// pensado para detectar un problema recurrente (ej. faltantes seguidos) en
/// vez de mirarlo aislado día a día en la pantalla de Caja.
class _CajaSection extends StatelessWidget {
  const _CajaSection({required this.cajas, required this.conDiferencia, required this.diferenciaTotal});
  final List<_CajaCierre> cajas;
  final int conDiferencia;
  final double diferenciaTotal;

  @override
  Widget build(BuildContext context) {
    final ok = diferenciaTotal == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Caja',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 4),
        Text('Diferencias entre lo esperado y lo contado al cerrar',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textFaint)),
        const SizedBox(height: 14),
        if (cajas.isEmpty)
          Text('No se cerró ninguna caja en este período.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else ...[
          Row(
            children: [
              Expanded(child: _ReporteMiniStat(label: 'Cerradas', value: '${cajas.length}')),
              Expanded(child: _ReporteMiniStat(label: 'Con diferencia', value: '$conDiferencia')),
              Expanded(
                child: _ReporteMiniStat(
                  label: 'Acumulada',
                  value: ok ? _fmtMoney(0) : '${diferenciaTotal < 0 ? 'Falta' : 'Sobra'} ${_fmtMoney(diferenciaTotal.abs())}',
                  color: ok ? AbakoColors.textDark : (diferenciaTotal < 0 ? AbakoColors.statusAgotadoText : AbakoColors.statusOkText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final c in cajas.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_fmtDiaCorto(c.cerradaEn),
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                  ),
                  Text(
                    c.diferencia == 0 ? 'Exacto' : '${c.diferencia < 0 ? 'Falta' : 'Sobra'} ${_fmtMoney(c.diferencia.abs())}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.diferencia == 0 ? AbakoColors.statusOkText : AbakoColors.statusAgotadoText),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ReporteMiniStat extends StatelessWidget {
  const _ReporteMiniStat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textFaint)),
        const SizedBox(height: 3),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 15, color: color ?? AbakoColors.textDark)),
      ],
    );
  }
}

class _DevolucionesList extends StatelessWidget {
  const _DevolucionesList({required this.items});
  final List<_DevolucionItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Devoluciones recientes',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 16, color: AbakoColors.textDark)),
        const SizedBox(height: 4),
        Text('Se registran desde el detalle de una venta',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textFaint)),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text('No hubo devoluciones en este período.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
        else
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(it.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                  ),
                  Text('${_fmtQty(it.cantidad)} un.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AbakoColors.statusAgotadoText)),
                ],
              ),
            ),
      ],
    );
  }
}
