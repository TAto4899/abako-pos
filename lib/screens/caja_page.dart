import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/denominaciones.dart';
import '../utils/money_input.dart';

const _uuid = Uuid();

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

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const cajasQuery = '''
  SELECT id, deposito_id, monto_apertura, abierta_por, cerrada_en,
         monto_cierre_esperado, monto_cierre_real, diferencia, cerrada_por,
         estado, notas, creado_en
  FROM cajas
''';
const _pagosQuery =
    'SELECT venta_id, metodo, monto, creado_en FROM pagos_venta';
const _movimientosCajaQuery =
    'SELECT id, caja_id, tipo, monto, motivo, creado_por, creado_en FROM movimientos_caja';
const _movimientosStockQuery =
    'SELECT producto_id, cantidad, motivo, venta_id, creado_en FROM movimientos_stock';
const _productosQuery = 'SELECT id, precio, costo FROM productos';
const _ventasQuery = 'SELECT id, estado FROM ventas';

/// Una caja registradora (apertura/cierre diario). No es append-only como
/// movimientos_stock/pagos_venta: esta fila se actualiza al cerrar.
class Caja {
  Caja({
    required this.id,
    required this.depositoId,
    required this.montoApertura,
    required this.abiertaPor,
    required this.cerradaEn,
    required this.montoCierreEsperado,
    required this.montoCierreReal,
    required this.diferencia,
    required this.cerradaPor,
    required this.estado,
    required this.creadoEn,
  });

  final String id;
  final String depositoId;
  final double montoApertura;
  final String? abiertaPor;
  final DateTime? cerradaEn;
  final double? montoCierreEsperado;
  final double? montoCierreReal;
  final double? diferencia;
  final String? cerradaPor;
  final String estado;
  final DateTime creadoEn;

  bool get abierta => estado == 'abierta';

  static Caja fromRow(dynamic row) => Caja(
    id: row['id'] as String,
    depositoId: row['deposito_id'] as String,
    montoApertura: double.tryParse('${row['monto_apertura']}') ?? 0,
    abiertaPor: row['abierta_por'] as String?,
    cerradaEn: row['cerrada_en'] == null
        ? null
        : DateTime.parse(row['cerrada_en'] as String),
    montoCierreEsperado: row['monto_cierre_esperado'] == null
        ? null
        : double.tryParse('${row['monto_cierre_esperado']}'),
    montoCierreReal: row['monto_cierre_real'] == null
        ? null
        : double.tryParse('${row['monto_cierre_real']}'),
    diferencia: row['diferencia'] == null
        ? null
        : double.tryParse('${row['diferencia']}'),
    cerradaPor: row['cerrada_por'] as String?,
    estado: row['estado'] as String,
    creadoEn: DateTime.parse(row['creado_en'] as String),
  );
}

/// Un retiro o ingreso manual de efectivo de una caja puntual (append-only,
/// igual que movimientos_stock/pagos_venta: si se cargó mal se compensa con
/// otro movimiento, no se corrige el original). Siempre es en efectivo — no
/// tiene sentido "retirar" una venta con tarjeta/transferencia de la caja
/// física.
class MovimientoCaja {
  MovimientoCaja({
    required this.id,
    required this.cajaId,
    required this.tipo,
    required this.monto,
    required this.motivo,
    required this.creadoPor,
    required this.creadoEn,
  });

  final String id;
  final String cajaId;
  final String tipo; // 'ingreso' | 'retiro'
  final double monto;
  final String? motivo;
  final String? creadoPor;
  final DateTime creadoEn;

  bool get esIngreso => tipo == 'ingreso';

  static MovimientoCaja fromRow(dynamic row) => MovimientoCaja(
    id: row['id'] as String,
    cajaId: row['caja_id'] as String,
    tipo: row['tipo'] as String,
    monto: double.tryParse('${row['monto']}') ?? 0,
    motivo: row['motivo'] as String?,
    creadoPor: row['creado_por'] as String?,
    creadoEn: DateTime.parse(row['creado_en'] as String),
  );
}

/// Una venta de stock (motivo='venta'), suficiente para valorizar la ganancia
/// por caja. Igual criterio que el resto de la app: se valoriza con el
/// precio/costo ACTUAL del producto, no hay costo histórico por línea.
class _MovimientoVenta {
  _MovimientoVenta({
    required this.productoId,
    required this.cantidad,
    required this.ventaId,
    required this.creadoEn,
  });
  final String productoId;
  final double cantidad;
  final String? ventaId;
  final DateTime creadoEn;
}

List<_MovimientoVenta> _parsearVentas(ResultSet? rows) => (rows ?? const [])
    .where((r) => r['motivo'] == 'venta')
    .map(
      (r) => _MovimientoVenta(
        productoId: r['producto_id'] as String,
        cantidad: double.tryParse('${r['cantidad']}') ?? 0,
        ventaId: r['venta_id'] as String?,
        creadoEn: DateTime.parse(r['creado_en'] as String),
      ),
    )
    .toList();

Set<String> _anuladaIdsDe(ResultSet? rows) => (rows ?? const [])
    .where((r) => r['estado'] == 'anulada')
    .map((r) => r['id'] as String)
    .toSet();

Map<String, double> _margenPorProducto(ResultSet? rows) => {
  for (final r in (rows ?? const []))
    r['id'] as String:
        (double.tryParse('${r['precio']}') ?? 0) -
        (double.tryParse('${r['costo']}') ?? 0),
};

/// La caja actualmente abierta (0 o 1 en todo momento — abrir una nueva caja
/// se bloquea mientras haya una abierta, sea de hoy o de un día anterior sin
/// cerrar). Usado tanto acá como en Inicio (banner) y Punto de Venta (bloqueo).
Caja? cajaAbiertaDe(List<Caja> cajas) =>
    cajas.where((c) => c.abierta).firstOrNull;

/// Parsea "HH:mm" (formato libre usado en Ajustes → Datos de la tienda) y
/// dice si la hora actual ya pasó ese horario. Devuelve false si el campo
/// está vacío o no matchea el formato — no rompe si Franco dejó texto libre.
bool horaActualPaso(String? horaHHmm, DateTime ahora) {
  if (horaHHmm == null) return false;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(horaHHmm.trim());
  if (m == null) return false;
  final h = int.tryParse(m.group(1)!);
  final min = int.tryParse(m.group(2)!);
  if (h == null || min == null) return false;
  final limite = DateTime(ahora.year, ahora.month, ahora.day, h, min);
  return !ahora.isBefore(limite);
}

class CajaPage extends StatefulWidget {
  const CajaPage({super.key});

  @override
  State<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends State<CajaPage> {
  String? _depositoId;

  @override
  void initState() {
    super.initState();
    _loadDepositoId();
  }

  Future<void> _loadDepositoId() async {
    final rows = await db.getAll(
      'SELECT id FROM depositos ORDER BY creado_en LIMIT 1',
    );
    if (mounted && rows.isNotEmpty) {
      setState(() => _depositoId = rows.first['id'] as String);
    }
  }

  String? get _usuarioActual =>
      sb.Supabase.instance.client.auth.currentUser?.email;

  Future<void> _abrirCaja(double montoApertura) async {
    final depositoId = _depositoId;
    if (depositoId == null) return;
    await db.execute(
      '''INSERT INTO cajas (id, deposito_id, monto_apertura, abierta_por, estado, creado_en)
         VALUES (?, ?, ?, ?, 'abierta', ?)''',
      [
        _uuid.v4(),
        depositoId,
        montoApertura,
        _usuarioActual,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  Future<void> _cerrarCaja(
    Caja caja,
    double montoEsperado,
    double montoReal,
  ) async {
    final diferencia = montoReal - montoEsperado;
    await db.execute(
      '''UPDATE cajas
         SET cerrada_en=?, monto_cierre_esperado=?, monto_cierre_real=?, diferencia=?, cerrada_por=?, estado='cerrada'
         WHERE id=?''',
      [
        DateTime.now().toIso8601String(),
        montoEsperado,
        montoReal,
        diferencia,
        _usuarioActual,
        caja.id,
      ],
    );
  }

  Future<void> _registrarMovimientoCaja(
    String cajaId,
    String tipo,
    double monto,
    String? motivo,
  ) async {
    await db.execute(
      '''INSERT INTO movimientos_caja (id, caja_id, tipo, monto, motivo, creado_por, creado_en)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        _uuid.v4(),
        cajaId,
        tipo,
        monto,
        motivo,
        _usuarioActual,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(cajasQuery),
          builder: (context, cajasSnap) {
            if (!cajasSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final cajas = cajasSnap.data!.map(Caja.fromRow).toList()
              ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
            final abiertas = cajas.where((c) => c.abierta).toList();
            final historial = cajas.where((c) => !c.abierta).toList();

            // Sugerencia de monto de apertura: el cierre real de la última
            // caja cerrada (historial ya viene ordenado más reciente primero)
            // — evita reescribir a mano un número que ya se contó ayer.
            final sugeridoApertura = historial.isNotEmpty
                ? historial.first.montoCierreReal
                : null;

            return StreamBuilder<ResultSet>(
              stream: db.watch(_ventasQuery),
              builder: (context, ventasEstadoSnap) {
                // Una venta anulada no cuenta en Caja — ver flujo de
                // anulación en venta_detalle_page.dart.
                final anuladaIds = _anuladaIdsDe(ventasEstadoSnap.data);

                return StreamBuilder<ResultSet>(
                  stream: db.watch(_pagosQuery),
                  builder: (context, pagosSnap) {
                    final pagos = pagosSnap.data?.toList() ?? const [];

                    double totalMetodo(
                      String metodo,
                      DateTime desde,
                      DateTime? hasta,
                    ) => pagos
                        .where((p) {
                          if (p['metodo'] != metodo) return false;
                          if (anuladaIds.contains(p['venta_id'])) return false;
                          final fecha = DateTime.parse(
                            p['creado_en'] as String,
                          );
                          if (fecha.isBefore(desde)) return false;
                          if (hasta != null && !fecha.isBefore(hasta)) {
                            return false;
                          }
                          return true;
                        })
                        .fold(
                          0.0,
                          (t, p) => t + (double.tryParse('${p['monto']}') ?? 0),
                        );

                    return StreamBuilder<ResultSet>(
                      stream: db.watch(_movimientosCajaQuery),
                      builder: (context, movsSnap) {
                        final movimientos =
                            (movsSnap.data
                                      ?.map(MovimientoCaja.fromRow)
                                      .toList() ??
                                  const [])
                              ..sort(
                                (a, b) => b.creadoEn.compareTo(a.creadoEn),
                              );
                        final movsPorCaja = <String, List<MovimientoCaja>>{};
                        for (final m in movimientos) {
                          (movsPorCaja[m.cajaId] ??= []).add(m);
                        }

                        return StreamBuilder<ResultSet>(
                          stream: db.watch(_movimientosStockQuery),
                          builder: (context, ventasSnap) {
                            final ventas = _parsearVentas(ventasSnap.data);
                            return StreamBuilder<ResultSet>(
                              stream: db.watch(_productosQuery),
                              builder: (context, prodSnap) {
                                final margenPorId = _margenPorProducto(
                                  prodSnap.data,
                                );

                                double gananciaEntre(
                                  DateTime desde,
                                  DateTime? hasta,
                                ) => ventas
                                    .where((v) {
                                      if (v.ventaId != null &&
                                          anuladaIds.contains(v.ventaId)) {
                                        return false;
                                      }
                                      if (v.creadoEn.isBefore(desde)) {
                                        return false;
                                      }
                                      if (hasta != null &&
                                          !v.creadoEn.isBefore(hasta)) {
                                        return false;
                                      }
                                      return true;
                                    })
                                    .fold(
                                      0.0,
                                      (t, v) =>
                                          t -
                                          v.cantidad *
                                              (margenPorId[v.productoId] ?? 0),
                                    );

                                return _CajaBody(
                                  isDesktop: isDesktop,
                                  abiertas: abiertas,
                                  historial: historial,
                                  sugeridoApertura: sugeridoApertura,
                                  onAbrir: _abrirCaja,
                                  totalMetodo: totalMetodo,
                                  gananciaEntre: gananciaEntre,
                                  movsPorCaja: movsPorCaja,
                                  onCerrar: _cerrarCaja,
                                  onRegistrarMovimiento:
                                      _registrarMovimientoCaja,
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

class _CajaBody extends StatelessWidget {
  const _CajaBody({
    required this.isDesktop,
    required this.abiertas,
    required this.historial,
    required this.sugeridoApertura,
    required this.onAbrir,
    required this.totalMetodo,
    required this.gananciaEntre,
    required this.movsPorCaja,
    required this.onCerrar,
    required this.onRegistrarMovimiento,
  });
  final bool isDesktop;
  final List<Caja> abiertas;
  final List<Caja> historial;
  final double? sugeridoApertura;
  final Future<void> Function(double montoApertura) onAbrir;
  final double Function(String metodo, DateTime desde, DateTime? hasta)
  totalMetodo;
  final double Function(DateTime desde, DateTime? hasta) gananciaEntre;
  final Map<String, List<MovimientoCaja>> movsPorCaja;
  final Future<void> Function(Caja caja, double esperado, double real) onCerrar;
  final Future<void> Function(
    String cajaId,
    String tipo,
    double monto,
    String? motivo,
  )
  onRegistrarMovimiento;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16,
          isDesktop ? 28 : 16,
          isDesktop ? 32 : 16,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caja',
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w600,
                fontSize: isDesktop ? 24 : 21,
                color: AbakoColors.textDark,
              ),
            ),
            const SizedBox(height: 18),
            if (abiertas.isEmpty)
              _AbrirCajaCard(onAbrir: onAbrir, sugerido: sugeridoApertura)
            else ...[
              if (abiertas.length > 1) ...[
                _CajasDuplicadasAviso(cantidad: abiertas.length),
                const SizedBox(height: 14),
              ],
              for (final c in abiertas) ...[
                _CajaAbiertaCard(
                  key: ValueKey(c.id),
                  caja: c,
                  totalEfectivo: totalMetodo('Efectivo', c.creadoEn, null),
                  totalTarjeta: totalMetodo('Tarjeta', c.creadoEn, null),
                  totalTransferencia: totalMetodo(
                    'Transferencia',
                    c.creadoEn,
                    null,
                  ),
                  ganancia: gananciaEntre(c.creadoEn, null),
                  movimientos: movsPorCaja[c.id] ?? const [],
                  onCerrar: (esperado, real) => onCerrar(c, esperado, real),
                  onRegistrarMovimiento: (tipo, monto, motivo) =>
                      onRegistrarMovimiento(c.id, tipo, monto, motivo),
                ),
                const SizedBox(height: 14),
              ],
            ],
            const SizedBox(height: 10),
            Text(
              'Historial de cajas',
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AbakoColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            if (historial.isEmpty)
              Text(
                'Todavía no hay cajas cerradas.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AbakoColors.textFaint,
                ),
              )
            else ...[
              _ResumenDiferenciasCard(historial: historial),
              const SizedBox(height: 14),
              for (final c in historial)
                _CajaHistorialTile(
                  caja: c,
                  movimientos: movsPorCaja[c.id] ?? const [],
                  ganancia: gananciaEntre(c.creadoEn, c.cerradaEn),
                ),
            ],
          ],
        ),
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

/// Se muestra cuando hay más de una caja abierta a la vez — puede pasar si
/// dos dispositivos abrieron caja casi al mismo instante, antes de que
/// alcanzaran a sincronizarse entre sí (mismo tipo de carrera que el
/// sobregiro de stock: no se previene, se resuelve a mano cuando aparece).
class _CajasDuplicadasAviso extends StatelessWidget {
  const _CajasDuplicadasAviso({required this.cantidad});
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AbakoColors.statusAgotadoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: AbakoColors.statusAgotadoText,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Se abrieron $cantidad cajas casi al mismo tiempo desde distintos dispositivos. Cerralas todas antes de seguir.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AbakoColors.statusAgotadoText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbrirCajaCard extends StatefulWidget {
  const _AbrirCajaCard({required this.onAbrir, this.sugerido});
  final Future<void> Function(double montoApertura) onAbrir;
  // Cierre real de la última caja cerrada, para prellenar (editable) y evitar
  // que Franco tenga que volver a tipear un número que ya contó ayer.
  final double? sugerido;

  @override
  State<_AbrirCajaCard> createState() => _AbrirCajaCardState();
}

class _AbrirCajaCardState extends State<_AbrirCajaCard> {
  late final _montoCtrl = TextEditingController(
    text: widget.sugerido != null ? fmtMoneyInput(widget.sugerido!) : '',
  );
  bool _guardando = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final monto = parseMoney(_montoCtrl.text);
    setState(() => _guardando = true);
    try {
      await widget.onAbrir(monto);
      if (mounted) mostrarSnack(context, 'Caja abierta');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_open_outlined,
                color: AbakoColors.accentGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Abrir caja',
                style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: AbakoColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'No hay una caja abierta. Ingresá el monto inicial en efectivo para empezar a vender.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AbakoColors.textFaint,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MoneyInputFormatter()],
            decoration: InputDecoration(
              hintText: 'Monto de apertura',
              prefixText: '\$ ',
              filled: true,
              fillColor: AbakoColors.cream,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(
                  color: AbakoColors.inputBorder,
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (widget.sugerido != null) ...[
            const SizedBox(height: 6),
            Text(
              'Sugerido a partir del cierre real de la última caja — podés cambiarlo.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                color: AbakoColors.textFaint,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmar,
              style: FilledButton.styleFrom(
                backgroundColor: AbakoColors.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Abrir caja',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CajaAbiertaCard extends StatefulWidget {
  const _CajaAbiertaCard({
    super.key,
    required this.caja,
    required this.totalEfectivo,
    required this.totalTarjeta,
    required this.totalTransferencia,
    required this.ganancia,
    required this.movimientos,
    required this.onCerrar,
    required this.onRegistrarMovimiento,
  });
  final Caja caja;
  final double totalEfectivo;
  final double totalTarjeta;
  final double totalTransferencia;
  final double ganancia;
  final List<MovimientoCaja> movimientos;
  final Future<void> Function(double esperado, double real) onCerrar;
  final Future<void> Function(String tipo, double monto, String? motivo)
  onRegistrarMovimiento;

  @override
  State<_CajaAbiertaCard> createState() => _CajaAbiertaCardState();
}

class _CajaAbiertaCardState extends State<_CajaAbiertaCard> {
  bool _cerrando = false;
  double _totalContado = 0;
  bool _conteoIniciado = false;

  double get _totalIngresos => widget.movimientos
      .where((m) => m.esIngreso)
      .fold(0.0, (t, m) => t + m.monto);
  double get _totalRetiros => widget.movimientos
      .where((m) => !m.esIngreso)
      .fold(0.0, (t, m) => t + m.monto);

  // El efectivo esperado en el cajón suma la apertura y lo vendido en
  // efectivo, y ahora también los ingresos/retiros manuales (plata que entró
  // o salió de la caja física sin ser una venta, ej. pagarle a un proveedor
  // en efectivo) — sin esto, cualquier movimiento de ese tipo generaba una
  // diferencia fantasma al cerrar.
  double get _esperado =>
      widget.caja.montoApertura +
      widget.totalEfectivo +
      _totalIngresos -
      _totalRetiros;

  // "Digital" agrupa todo lo que no es efectivo físico — tarjeta y
  // transferencia no pasan por el cajón, así que no afectan el conteo de
  // billetes ni el "esperado en caja".
  double get _totalDigital => widget.totalTarjeta + widget.totalTransferencia;

  // Física (esperado en caja) + digital: lo que realmente entró en total,
  // más allá de dónde quedó guardado cada peso.
  double get _totalGeneral => _esperado + _totalDigital;

  Future<void> _abrirDialogoMovimiento() async {
    final resultado =
        await showDialog<({String tipo, double monto, String? motivo})>(
          context: context,
          builder: (_) => const _MovimientoCajaDialog(),
        );
    if (resultado == null) return;
    await widget.onRegistrarMovimiento(
      resultado.tipo,
      resultado.monto,
      resultado.motivo,
    );
    if (mounted) {
      mostrarSnack(
        context,
        resultado.tipo == 'ingreso'
            ? 'Ingreso registrado'
            : 'Retiro registrado',
      );
    }
  }

  // Cerrar la caja no se puede deshacer, así que antes se muestra el resumen
  // esperado/contado/diferencia — sin esto un clic sin querer (por ejemplo
  // con el conteo todavía en $0) registraba un faltante enorme.
  Future<void> _confirmarCierre() async {
    final esperado = _esperado;
    final contado = _totalContado;
    final diferencia = contado - esperado;
    final sinConteo = contado == 0;
    final coincide = diferencia.abs() < 0.005;
    final colorDiferencia = coincide
        ? AbakoColors.statusOkText
        : (sinConteo
              ? AbakoColors.statusAgotadoText
              : AbakoColors.statusBajoText);

    Widget fila(String label, String valor, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AbakoColors.textLabel,
              ),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color ?? AbakoColors.textDark,
            ),
          ),
        ],
      ),
    );

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '¿Cerrar la caja?',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            color: AbakoColors.textDark,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fila('Esperado en caja', _fmtMoney(esperado)),
              fila('Contado', _fmtMoney(contado)),
              fila(
                'Diferencia',
                coincide
                    ? 'Coincide con lo esperado'
                    : '${diferencia < 0 ? 'Falta' : 'Sobra'} ${_fmtMoney(diferencia.abs())}',
                color: colorDiferencia,
              ),
              if (sinConteo) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AbakoColors.statusAgotadoBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'No contaste ningún billete. Si cerrás así, se registra un faltante de ${_fmtMoney(esperado)}.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AbakoColors.statusAgotadoText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver a contar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: sinConteo
                  ? AbakoColors.statusAgotadoText
                  : AbakoColors.accentGreen,
            ),
            child: Text(sinConteo ? 'Cerrar igual' : 'Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cerrando = true);
    try {
      await widget.onCerrar(_esperado, _totalContado);
      if (mounted) mostrarSnack(context, 'Caja cerrada');
    } finally {
      if (mounted) setState(() => _cerrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final esDeHoy = _mismoDia(widget.caja.creadoEn, ahora);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: esDeHoy
                    ? AbakoColors.statusOkText
                    : AbakoColors.statusAgotadoText,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  esDeHoy
                      ? 'Caja abierta'
                      : 'Caja sin cerrar de ${_fmtFechaHora(widget.caja.creadoEn)}',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                    color: AbakoColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Abierta ${_fmtFechaHora(widget.caja.creadoEn)}${widget.caja.abiertaPor != null ? ' por ${widget.caja.abiertaPor}' : ''}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: AbakoColors.textFaint,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Apertura',
                  value: _fmtMoney(widget.caja.montoApertura),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Efectivo vendido',
                  value: _fmtMoney(widget.totalEfectivo),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Esperado en caja',
                  value: _fmtMoney(_esperado),
                  destacado: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Tarjeta',
                  value: _fmtMoney(widget.totalTarjeta),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Transferencia',
                  value: _fmtMoney(widget.totalTransferencia),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Total digital',
                  value: _fmtMoney(_totalDigital),
                  destacado: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Ganancia',
                  value: _fmtMoney(widget.ganancia),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Total (física + digital)',
                  value: _fmtMoney(_totalGeneral),
                  destacado: true,
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFECEAE3)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Movimientos de caja',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AbakoColors.textDark,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _abrirDialogoMovimiento,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AbakoColors.textLabel,
                  side: const BorderSide(
                    color: AbakoColors.inputBorder,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Ingreso/Retiro',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Efectivo que entra o sale de la caja sin ser una venta (ej. pagarle a un proveedor).',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AbakoColors.textFaint,
            ),
          ),
          const SizedBox(height: 10),
          if (widget.movimientos.isEmpty)
            Text(
              'Todavía no hay movimientos manuales en esta caja.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: AbakoColors.textFaint,
              ),
            )
          else
            for (final m in widget.movimientos)
              _MovimientoCajaTile(movimiento: m),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFECEAE3)),
          const SizedBox(height: 18),
          Text(
            'Cerrar caja',
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AbakoColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Contá el efectivo real en la caja e ingresalo acá.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: AbakoColors.textFaint,
            ),
          ),
          const SizedBox(height: 12),
          _ConteoEfectivo(
            onCambio: (total) => setState(() {
              _totalContado = total;
              _conteoIniciado = true;
            }),
          ),
          if (_conteoIniciado) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final diferencia = _totalContado - _esperado;
                final negativo = diferencia < 0;
                return Text(
                  diferencia == 0
                      ? 'Coincide con lo esperado'
                      : '${negativo ? 'Falta' : 'Sobra'} ${_fmtMoney(diferencia.abs())}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: diferencia == 0
                        ? AbakoColors.statusOkText
                        : AbakoColors.statusAgotadoText,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _cerrando ? null : _confirmarCierre,
              style: FilledButton.styleFrom(
                backgroundColor: AbakoColors.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _cerrando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Cerrar caja',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Conteo de efectivo por denominación en vez de un solo "monto contado" a
/// mano — pedido de Franco (2026-09-04): tipear el total a ojo es donde más
/// se pierde/pifia. Acá se cuenta cantidad de billetes por denominación y el
/// total sale calculado solo. No se persiste el desglose, solo el total final
/// (mismo campo `monto_cierre_real` de siempre).
class _ConteoEfectivo extends StatefulWidget {
  const _ConteoEfectivo({required this.onCambio});
  final ValueChanged<double> onCambio;

  @override
  State<_ConteoEfectivo> createState() => _ConteoEfectivoState();
}

class _ConteoEfectivoState extends State<_ConteoEfectivo> {
  final Map<double, TextEditingController> _ctrls = {
    for (final d in denominacionesArs) d: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => denominacionesArs.fold(
    0.0,
    (t, d) => t + (int.tryParse(_ctrls[d]!.text) ?? 0) * d,
  );

  void _cambiarCantidad(double denominacion, int cantidad) {
    final ctrl = _ctrls[denominacion]!;
    ctrl.value = TextEditingValue(text: cantidad <= 0 ? '' : '$cantidad');
    widget.onCambio(_total);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in denominacionesArs)
          _FilaDenominacion(
            denominacion: d,
            controller: _ctrls[d]!,
            onCambiarCantidad: (cant) => _cambiarCantidad(d, cant),
            onTipeado: () => widget.onCambio(_total),
          ),
        const Divider(height: 20, color: Color(0xFFECEAE3)),
        Row(
          children: [
            Text(
              'Total contado',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AbakoColors.textDark,
              ),
            ),
            const Spacer(),
            Text(
              _fmtMoney(_total),
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AbakoColors.textDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilaDenominacion extends StatelessWidget {
  const _FilaDenominacion({
    required this.denominacion,
    required this.controller,
    required this.onCambiarCantidad,
    required this.onTipeado,
  });
  final double denominacion;
  final TextEditingController controller;
  final ValueChanged<int> onCambiarCantidad;
  final VoidCallback onTipeado;

  int get _cantidad => int.tryParse(controller.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              _fmtMoney(denominacion),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AbakoColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onCambiarCantidad(_cantidad - 1),
            icon: const Icon(Icons.remove_circle_outline, size: 19),
            color: AbakoColors.textFaint,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          SizedBox(
            width: 46,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onTipeado(),
              decoration: InputDecoration(
                hintText: '0',
                isDense: true,
                filled: true,
                fillColor: AbakoColors.cream,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AbakoColors.inputBorder,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => onCambiarCantidad(_cantidad + 1),
            icon: const Icon(Icons.add_circle_outline, size: 19),
            color: AbakoColors.textFaint,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _fmtMoney(denominacion * _cantidad),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: AbakoColors.textFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.destacado = false,
  });
  final String label;
  final String value;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            color: AbakoColors.textFaint,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w700,
            fontSize: destacado ? 17 : 15,
            color: destacado ? AbakoColors.accentGreen : AbakoColors.textDark,
          ),
        ),
      ],
    );
  }
}

/// Una fila de "Movimientos de caja" (ingreso/retiro manual). El monto va en
/// verde/rojo con el signo correspondiente, igual convención que "Falta"/
/// "Sobra" del resto de la pantalla.
class _MovimientoCajaTile extends StatelessWidget {
  const _MovimientoCajaTile({required this.movimiento});
  final MovimientoCaja movimiento;

  @override
  Widget build(BuildContext context) {
    final color = movimiento.esIngreso
        ? AbakoColors.statusOkText
        : AbakoColors.statusAgotadoText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            movimiento.esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              movimiento.motivo?.isNotEmpty == true
                  ? movimiento.motivo!
                  : (movimiento.esIngreso ? 'Ingreso' : 'Retiro'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AbakoColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtFechaHora(movimiento.creadoEn),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AbakoColors.textFaint,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${movimiento.esIngreso ? '+' : '-'}${_fmtMoney(movimiento.monto)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo chico para registrar un ingreso o retiro manual de efectivo.
class _MovimientoCajaDialog extends StatefulWidget {
  const _MovimientoCajaDialog();

  @override
  State<_MovimientoCajaDialog> createState() => _MovimientoCajaDialogState();
}

class _MovimientoCajaDialogState extends State<_MovimientoCajaDialog> {
  String _tipo = 'retiro';
  final _montoCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();

  @override
  void dispose() {
    _montoCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monto = parseMoney(_montoCtrl.text);
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Movimiento de caja',
        style: GoogleFonts.bricolageGrotesque(
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AbakoColors.textDark,
        ),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _TipoChip(
                    label: 'Retiro',
                    icon: Icons.arrow_upward,
                    selected: _tipo == 'retiro',
                    onTap: () => setState(() => _tipo = 'retiro'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TipoChip(
                    label: 'Ingreso',
                    icon: Icons.arrow_downward,
                    selected: _tipo == 'ingreso',
                    onTap: () => setState(() => _tipo = 'ingreso'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _montoCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [MoneyInputFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Monto',
                prefixText: '\$ ',
                filled: true,
                fillColor: AbakoColors.cream,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(
                    color: AbakoColors.inputBorder,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motivoCtrl,
              decoration: InputDecoration(
                hintText: 'Motivo (opcional) — ej. Pago a proveedor',
                filled: true,
                fillColor: AbakoColors.cream,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(
                    color: AbakoColors.inputBorder,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              color: AbakoColors.textLabel,
            ),
          ),
        ),
        FilledButton(
          onPressed: monto <= 0
              ? null
              : () => Navigator.of(context).pop((
                  tipo: _tipo,
                  monto: monto,
                  motivo: _motivoCtrl.text.trim().isEmpty
                      ? null
                      : _motivoCtrl.text.trim(),
                )),
          style: FilledButton.styleFrom(
            backgroundColor: AbakoColors.accentGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'Registrar',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _TipoChip extends StatelessWidget {
  const _TipoChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AbakoColors.accentGreen : AbakoColors.cream,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AbakoColors.accentGreen
                  : AbakoColors.inputBorder,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AbakoColors.textLabel,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AbakoColors.textLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen de diferencias acumuladas del historial de cajas cerradas — ayuda
/// a detectar un problema recurrente (ej. alguien se queda con vuelto) en vez
/// de verlo aislado día a día.
class _ResumenDiferenciasCard extends StatelessWidget {
  const _ResumenDiferenciasCard({required this.historial});
  final List<Caja> historial;

  @override
  Widget build(BuildContext context) {
    final total = historial.fold(0.0, (t, c) => t + (c.diferencia ?? 0));
    final conDiferencia = historial
        .where((c) => (c.diferencia ?? 0) != 0)
        .length;
    final ok = total == 0;
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Cajas cerradas',
              value: '${historial.length}',
            ),
          ),
          Expanded(
            child: _MiniStat(label: 'Con diferencia', value: '$conDiferencia'),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diferencia acumulada',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: AbakoColors.textFaint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ok
                      ? _fmtMoney(0)
                      : '${total < 0 ? 'Falta' : 'Sobra'} ${_fmtMoney(total.abs())}',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ok
                        ? AbakoColors.textDark
                        : (total < 0
                              ? AbakoColors.statusAgotadoText
                              : AbakoColors.statusOkText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CajaHistorialTile extends StatelessWidget {
  const _CajaHistorialTile({
    required this.caja,
    required this.movimientos,
    required this.ganancia,
  });
  final Caja caja;
  final List<MovimientoCaja> movimientos;
  final double ganancia;

  @override
  Widget build(BuildContext context) {
    final diferencia = caja.diferencia ?? 0;
    final negativo = diferencia < 0;
    final ok = diferencia == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_fmtFechaHora(caja.creadoEn)} → ${caja.cerradaEn != null ? _fmtFechaHora(caja.cerradaEn!) : '—'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Apertura ${_fmtMoney(caja.montoApertura)} · Esperado ${_fmtMoney(caja.montoCierreEsperado ?? 0)} · Real ${_fmtMoney(caja.montoCierreReal ?? 0)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: AbakoColors.textFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ganancia ${_fmtMoney(ganancia)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.accentGreen,
                  ),
                ),
                if (movimientos.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${movimientos.length} movimiento${movimientos.length == 1 ? '' : 's'} manual${movimientos.length == 1 ? '' : 'es'} de caja',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: AbakoColors.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: ok ? AbakoColors.statusOkBg : AbakoColors.statusAgotadoBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              ok
                  ? 'Exacto'
                  : '${negativo ? 'Falta' : 'Sobra'} ${_fmtMoney(diferencia.abs())}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ok
                    ? AbakoColors.statusOkText
                    : AbakoColors.statusAgotadoText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
