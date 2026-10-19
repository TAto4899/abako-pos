import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/product_avatar.dart';

const _uuid = Uuid();

String _fmtQty(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

String _fmtFechaHora(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm $hh:$min';
}

const _ordenesQuery = '''
  SELECT id, proveedor, estado, notas, creado_por, recibida_en, recibida_por, creado_en
  FROM ordenes_compra
''';
const _itemsQuery =
    'SELECT id, orden_id, producto_id, cantidad, costo_unitario FROM orden_compra_items';
const _productosStockQuery = '''
  SELECT p.id AS id, p.nombre AS nombre, p.sku AS sku, p.stock_minimo AS stock_minimo, p.activo AS activo,
    p.costo AS costo,
    COALESCE((
      SELECT SUM(CAST(m.cantidad AS REAL)) FROM movimientos_stock m WHERE m.producto_id = p.id
    ), 0) AS stock_actual
  FROM productos p
  ORDER BY p.nombre
''';

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

class _Orden {
  _Orden({
    required this.id,
    required this.proveedor,
    required this.estado,
    required this.notas,
    required this.creadoPor,
    required this.recibidaEn,
    required this.recibidaPor,
    required this.creadoEn,
  });
  final String id;
  final String? proveedor;
  final String estado;
  final String? notas;
  final String? creadoPor;
  final DateTime? recibidaEn;
  final String? recibidaPor;
  final DateTime creadoEn;

  static _Orden fromRow(dynamic row) => _Orden(
    id: row['id'] as String,
    proveedor: row['proveedor'] as String?,
    estado: row['estado'] as String,
    notas: row['notas'] as String?,
    creadoPor: row['creado_por'] as String?,
    recibidaEn: row['recibida_en'] == null
        ? null
        : DateTime.parse(row['recibida_en'] as String),
    recibidaPor: row['recibida_por'] as String?,
    creadoEn: DateTime.parse(row['creado_en'] as String),
  );
}

class _Item {
  _Item({
    required this.id,
    required this.ordenId,
    required this.productoId,
    required this.cantidad,
    required this.costoUnitario,
  });
  final String id;
  final String ordenId;
  final String productoId;
  final double cantidad;
  final double? costoUnitario;

  static _Item fromRow(dynamic row) => _Item(
    id: row['id'] as String,
    ordenId: row['orden_id'] as String,
    productoId: row['producto_id'] as String,
    cantidad: double.tryParse('${row['cantidad']}') ?? 0,
    costoUnitario: row['costo_unitario'] == null
        ? null
        : double.tryParse('${row['costo_unitario']}'),
  );
}

class _ProductoStock {
  _ProductoStock({
    required this.id,
    required this.nombre,
    required this.sku,
    required this.activo,
    required this.stockMinimo,
    required this.stockActual,
    required this.costo,
  });
  final String id;
  final String nombre;
  final String? sku;
  final double stockMinimo;
  final double stockActual;
  final bool activo;
  final double costo;

  static _ProductoStock fromRow(dynamic row) => _ProductoStock(
    id: row['id'] as String,
    nombre: row['nombre'] as String,
    sku: row['sku'] as String?,
    stockMinimo: double.tryParse('${row['stock_minimo']}') ?? 0,
    stockActual: double.tryParse('${row['stock_actual']}') ?? 0,
    activo: row['activo'] == null ? true : _asBool(row['activo']),
    costo: double.tryParse('${row['costo']}') ?? 0,
  );
}

class _LineaNueva {
  _LineaNueva({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
  });
  final String productoId;
  final String nombre;
  double cantidad;
  final double costoUnitario;
}

/// Botón de entrada a Órdenes de compra, para usar en el header de Inventario
/// (no tiene ítem propio en el nav, se llega desde acá).
class OrdenesCompraButton extends StatelessWidget {
  const OrdenesCompraButton({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const OrdenesCompraPage())),
      style: OutlinedButton.styleFrom(
        foregroundColor: AbakoColors.textLabel,
        side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.local_shipping_outlined, size: 17),
      label: Text(
        'Órdenes de compra',
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class OrdenesCompraPage extends StatelessWidget {
  const OrdenesCompraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.creamOuter,
      appBar: AppBar(
        backgroundColor: AbakoColors.panelGreen,
        foregroundColor: AbakoColors.creamText,
        elevation: 0,
        title: Text(
          'Órdenes de compra',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AbakoColors.creamText,
          ),
        ),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(_productosStockQuery),
        builder: (context, prodSnap) {
          if (!prodSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final productos = prodSnap.data!
              .map(_ProductoStock.fromRow)
              .where((p) => p.activo)
              .toList();

          return StreamBuilder<ResultSet>(
            stream: db.watch(_ordenesQuery),
            builder: (context, ordenesSnap) {
              if (!ordenesSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ordenes = ordenesSnap.data!.map(_Orden.fromRow).toList()
                ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

              return StreamBuilder<ResultSet>(
                stream: db.watch(_itemsQuery),
                builder: (context, itemsSnap) {
                  final items =
                      itemsSnap.data?.map(_Item.fromRow).toList() ??
                      const <_Item>[];
                  final cantidadPorOrden = <String, int>{};
                  for (final it in items) {
                    cantidadPorOrden[it.ordenId] =
                        (cantidadPorOrden[it.ordenId] ?? 0) + 1;
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _abrirNuevaOrden(
                                  context,
                                  productos,
                                  sugerida: false,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AbakoColors.textLabel,
                                  side: const BorderSide(
                                    color: AbakoColors.inputBorder,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(
                                  'Nueva orden',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _abrirNuevaOrden(
                                  context,
                                  productos,
                                  sugerida: true,
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AbakoColors.accentGreen,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  'Generar sugerida',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ordenes.isEmpty
                            ? Center(
                                child: Text(
                                  'Todavía no hay órdenes de compra.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: AbakoColors.textFaint,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  16,
                                ),
                                itemCount: ordenes.length,
                                itemBuilder: (context, i) => _OrdenTile(
                                  orden: ordenes[i],
                                  cantidadItems:
                                      cantidadPorOrden[ordenes[i].id] ?? 0,
                                ),
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _abrirNuevaOrden(
    BuildContext context,
    List<_ProductoStock> productos, {
    required bool sugerida,
  }) {
    final iniciales = <_LineaNueva>[];
    if (sugerida) {
      for (final p in productos) {
        final falta = p.stockActual <= 0 || p.stockActual <= p.stockMinimo;
        if (!falta) continue;
        final cantidad = (p.stockMinimo - p.stockActual)
            .clamp(1, double.infinity)
            .toDouble();
        iniciales.add(
          _LineaNueva(
            productoId: p.id,
            nombre: p.nombre,
            cantidad: cantidad,
            costoUnitario: p.costo,
          ),
        );
      }
      if (iniciales.isEmpty) {
        mostrarSnack(
          context,
          'No hay productos por debajo del stock mínimo ahora mismo.',
          kind: SnackKind.info,
        );
        return;
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // context propio del builder — mismo fix que inventario/clientes
      // (2026-09-04): con el context de afuera este Padding no se recalcula
      // cuando aparece el teclado.
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: _NuevaOrdenSheet(
            productos: productos,
            lineasIniciales: iniciales,
          ),
        ),
      ),
    );
  }
}

class _OrdenTile extends StatelessWidget {
  const _OrdenTile({required this.orden, required this.cantidadItems});
  final _Orden orden;
  final int cantidadItems;

  @override
  Widget build(BuildContext context) {
    final estilo = _estiloEstado(orden.estado);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrdenDetallePage(ordenId: orden.id),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFECEAE3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      orden.proveedor?.isNotEmpty == true
                          ? orden.proveedor!
                          : 'Sin proveedor',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AbakoColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtFechaHora(orden.creadoEn)} · $cantidadItems producto${cantidadItems == 1 ? '' : 's'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AbakoColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: estilo.$1,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  estilo.$3,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: estilo.$2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(Color, Color, String) _estiloEstado(String estado) {
  switch (estado) {
    case 'recibida':
      return (AbakoColors.statusOkBg, AbakoColors.statusOkText, 'Recibida');
    case 'cancelada':
      return (AbakoColors.creamOuter, AbakoColors.textMuted, 'Cancelada');
    default:
      return (
        AbakoColors.statusBajoBg,
        AbakoColors.statusBajoText,
        'Pendiente',
      );
  }
}

// ---------------------------------------------------------------------------
// Nueva orden
// ---------------------------------------------------------------------------

class _NuevaOrdenSheet extends StatefulWidget {
  const _NuevaOrdenSheet({
    required this.productos,
    required this.lineasIniciales,
  });
  final List<_ProductoStock> productos;
  final List<_LineaNueva> lineasIniciales;

  @override
  State<_NuevaOrdenSheet> createState() => _NuevaOrdenSheetState();
}

class _NuevaOrdenSheetState extends State<_NuevaOrdenSheet> {
  final _proveedorCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();
  late final List<_LineaNueva> _lineas = List.of(widget.lineasIniciales);
  bool _guardando = false;

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    _notasCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _agregar(_ProductoStock p) {
    setState(() {
      final i = _lineas.indexWhere((l) => l.productoId == p.id);
      if (i >= 0) {
        _lineas[i].cantidad += 1;
      } else {
        _lineas.add(
          _LineaNueva(
            productoId: p.id,
            nombre: p.nombre,
            cantidad: 1,
            costoUnitario: p.costo,
          ),
        );
      }
    });
  }

  void _ajustar(int index, double delta) {
    setState(() {
      final nueva = _lineas[index].cantidad + delta;
      if (nueva <= 0) {
        _lineas.removeAt(index);
      } else {
        _lineas[index].cantidad = nueva;
      }
    });
  }

  Future<void> _guardar() async {
    if (_lineas.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final ordenId = _uuid.v4();
      final ahora = DateTime.now().toIso8601String();
      final proveedor = _proveedorCtrl.text.trim();
      final notas = _notasCtrl.text.trim();
      final email = sb.Supabase.instance.client.auth.currentUser?.email;
      await db.writeTransaction((tx) async {
        await tx.execute(
          '''INSERT INTO ordenes_compra (id, proveedor, estado, notas, creado_por, creado_en)
             VALUES (?, ?, 'pendiente', ?, ?, ?)''',
          [
            ordenId,
            proveedor.isEmpty ? null : proveedor,
            notas.isEmpty ? null : notas,
            email,
            ahora,
          ],
        );
        for (final l in _lineas) {
          await tx.execute(
            'INSERT INTO orden_compra_items (id, orden_id, producto_id, cantidad, costo_unitario, creado_en) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _uuid.v4(),
              ordenId,
              l.productoId,
              l.cantidad,
              l.costoUnitario,
              ahora,
            ],
          );
        }
      });
      if (mounted) {
        Navigator.of(context).pop();
        mostrarSnack(context, 'Orden creada');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _buscarCtrl.text.trim().toLowerCase();
    final resultados = q.isEmpty
        ? const <_ProductoStock>[]
        : widget.productos
              .where(
                (p) =>
                    p.nombre.toLowerCase().contains(q) ||
                    (p.sku?.toLowerCase().contains(q) ?? false),
              )
              .take(6)
              .toList();

    return Container(
      decoration: const BoxDecoration(
        color: AbakoColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.lineasIniciales.isNotEmpty &&
                            _lineas.length == widget.lineasIniciales.length
                        ? 'Orden sugerida'
                        : 'Nueva orden',
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w600,
                      fontSize: 19,
                      color: AbakoColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 19),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1EFE8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1EFE8)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              children: [
                Text(
                  'Proveedor',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textLabel,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _proveedorCtrl,
                  decoration: _dec('Opcional'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Agregar productos',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textLabel,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _buscarCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(
                    'Buscar por nombre o código...',
                  ).copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                ),
                if (resultados.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AbakoColors.inputBorder),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in resultados)
                          ListTile(
                            dense: true,
                            leading: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: colorOf(p.nombre),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                monoOf(p.nombre),
                                style: GoogleFonts.bricolageGrotesque(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Text(
                              p.nombre,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Stock actual: ${_fmtQty(p.stockActual)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: AbakoColors.textFaint,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.add_circle_outline,
                              size: 20,
                              color: AbakoColors.accentGreen,
                            ),
                            onTap: () {
                              _agregar(p);
                              _buscarCtrl.clear();
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Text(
                  'Productos en esta orden (${_lineas.length})',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textLabel,
                  ),
                ),
                const SizedBox(height: 10),
                if (_lineas.isEmpty)
                  Text(
                    'Todavía no agregaste ningún producto.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AbakoColors.textFaint,
                    ),
                  )
                else
                  for (var i = 0; i < _lineas.length; i++)
                    _LineaTile(
                      linea: _lineas[i],
                      onAjustar: (d) => _ajustar(i, d),
                    ),
                const SizedBox(height: 16),
                Text(
                  'Notas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textLabel,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _notasCtrl,
                  maxLines: 2,
                  decoration: _dec('Opcional'),
                ),
              ],
            ),
          ),
          if (_lineas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Importe a pagar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AbakoColors.textLabel,
                    ),
                  ),
                  Text(
                    _fmtMoney(
                      _lineas.fold<double>(
                        0,
                        (t, l) => t + l.costoUnitario * l.cantidad,
                      ),
                    ),
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AbakoColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: FilledButton(
                onPressed: _guardando || _lineas.isEmpty ? null : _guardar,
                style: FilledButton.styleFrom(
                  backgroundColor: AbakoColors.accentGreen,
                  padding: const EdgeInsets.symmetric(vertical: 15),
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
                        'Guardar orden (${_lineas.length})',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
  ),
);

class _LineaTile extends StatelessWidget {
  const _LineaTile({required this.linea, required this.onAjustar});
  final _LineaNueva linea;
  final ValueChanged<double> onAjustar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorOf(linea.nombre),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              monoOf(linea.nombre),
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  linea.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textDark,
                  ),
                ),
                if (linea.costoUnitario > 0)
                  Text(
                    '${_fmtMoney(linea.costoUnitario)} c/u · ${_fmtMoney(linea.costoUnitario * linea.cantidad)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: AbakoColors.textFaint,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onAjustar(-1),
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: AbakoColors.textFaint,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          SizedBox(
            width: 30,
            child: Text(
              _fmtQty(linea.cantidad),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onAjustar(1),
            icon: const Icon(Icons.add_circle_outline, size: 20),
            color: AbakoColors.accentGreen,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle
// ---------------------------------------------------------------------------

class OrdenDetallePage extends StatefulWidget {
  const OrdenDetallePage({super.key, required this.ordenId});
  final String ordenId;

  @override
  State<OrdenDetallePage> createState() => _OrdenDetallePageState();
}

class _OrdenDetallePageState extends State<OrdenDetallePage> {
  bool _guardando = false;

  Future<void> _marcarRecibida(_Orden orden, List<_Item> items) async {
    setState(() => _guardando = true);
    try {
      final depositoRows = await db.getAll(
        'SELECT id FROM depositos ORDER BY creado_en LIMIT 1',
      );
      if (depositoRows.isEmpty) {
        throw Exception('No hay ningún depósito configurado todavía.');
      }
      final depositoId = depositoRows.first['id'] as String;
      final ahora = DateTime.now().toIso8601String();
      final email = sb.Supabase.instance.client.auth.currentUser?.email;

      await db.writeTransaction((tx) async {
        for (final it in items) {
          await tx.execute(
            '''INSERT INTO movimientos_stock (id, producto_id, deposito_id, cantidad, motivo, orden_id, creado_en)
               VALUES (?, ?, ?, ?, 'compra', ?, ?)''',
            [
              _uuid.v4(),
              it.productoId,
              depositoId,
              it.cantidad,
              orden.id,
              ahora,
            ],
          );
        }
        await tx.execute(
          "UPDATE ordenes_compra SET estado='recibida', recibida_en=?, recibida_por=? WHERE id=?",
          [ahora, email, orden.id],
        );
      });
      if (mounted) mostrarSnack(context, 'Orden recibida — stock actualizado');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _copiarListado(
    BuildContext context,
    _Orden orden,
    List<_Item> items,
    Map<String, String> nombrePorId,
    double importeTotal,
  ) async {
    final buf = StringBuffer('Orden de compra');
    if (orden.proveedor?.isNotEmpty == true) buf.write(' — ${orden.proveedor}');
    buf.writeln();
    buf.writeln(_fmtFechaHora(orden.creadoEn));
    buf.writeln();
    for (final it in items) {
      buf.writeln(
        '- ${nombrePorId[it.productoId] ?? 'Producto'}: ${_fmtQty(it.cantidad)}',
      );
    }
    if (importeTotal > 0) {
      buf.writeln();
      buf.writeln('Importe a pagar: ${_fmtMoney(importeTotal)}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      mostrarSnack(
        context,
        'Lista copiada — pegala en WhatsApp o donde la necesites',
      );
    }
  }

  Future<void> _cancelar(_Orden orden) async {
    setState(() => _guardando = true);
    try {
      await db.execute(
        "UPDATE ordenes_compra SET estado='cancelada' WHERE id=?",
        [orden.id],
      );
      if (mounted) {
        mostrarSnack(context, 'Orden cancelada', kind: SnackKind.info);
      }
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
        title: Text(
          'Detalle de orden',
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AbakoColors.creamText,
          ),
        ),
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch(_ordenesQuery),
        builder: (context, ordenesSnap) {
          if (!ordenesSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orden = ordenesSnap.data!
              .map(_Orden.fromRow)
              .where((o) => o.id == widget.ordenId)
              .firstOrNull;
          if (orden == null) {
            return Center(
              child: Text(
                'Esta orden ya no existe.',
                style: GoogleFonts.plusJakartaSans(
                  color: AbakoColors.textFaint,
                ),
              ),
            );
          }
          return StreamBuilder<ResultSet>(
            stream: db.watch(_itemsQuery),
            builder: (context, itemsSnap) {
              if (!itemsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = itemsSnap.data!
                  .map(_Item.fromRow)
                  .where((i) => i.ordenId == widget.ordenId)
                  .toList();
              return StreamBuilder<ResultSet>(
                stream: db.watch(_productosStockQuery),
                builder: (context, prodSnap) {
                  final nombrePorId = {
                    for (final row in prodSnap.data?.toList() ?? const [])
                      row['id'] as String: row['nombre'] as String,
                  };
                  final costoActualPorId = {
                    for (final row in prodSnap.data?.toList() ?? const [])
                      row['id'] as String:
                          double.tryParse('${row['costo']}') ?? 0,
                  };
                  // Usa el costo capturado al crear la orden; si es una orden
                  // vieja (de antes de esta mejora) que no lo tiene guardado,
                  // recae en el costo actual del producto como estimación.
                  double costoDe(_Item it) =>
                      it.costoUnitario ?? costoActualPorId[it.productoId] ?? 0;
                  final importeTotal = items.fold<double>(
                    0,
                    (t, it) => t + costoDe(it) * it.cantidad,
                  );

                  final estilo = _estiloEstado(orden.estado);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      orden.proveedor?.isNotEmpty == true
                                          ? orden.proveedor!
                                          : 'Sin proveedor',
                                      style: GoogleFonts.bricolageGrotesque(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 17,
                                        color: AbakoColors.textDark,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: estilo.$1,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      estilo.$3,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: estilo.$2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Creada ${_fmtFechaHora(orden.creadoEn)}${orden.creadoPor != null ? ' por ${orden.creadoPor}' : ''}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  color: AbakoColors.textFaint,
                                ),
                              ),
                              if (orden.recibidaEn != null)
                                Text(
                                  'Recibida ${_fmtFechaHora(orden.recibidaEn!)}${orden.recibidaPor != null ? ' por ${orden.recibidaPor}' : ''}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    color: AbakoColors.textFaint,
                                  ),
                                ),
                              if (orden.notas?.isNotEmpty == true) ...[
                                const SizedBox(height: 10),
                                Text(
                                  orden.notas!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: AbakoColors.textLabel,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Productos',
                                      style: GoogleFonts.bricolageGrotesque(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: AbakoColors.textDark,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _copiarListado(
                                      context,
                                      orden,
                                      items,
                                      nombrePorId,
                                      importeTotal,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          AbakoColors.accentGreenHover,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    label: Text(
                                      'Copiar lista',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              for (final it in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              nombrePorId[it.productoId] ??
                                                  'Producto',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 13.5,
                                                    color: AbakoColors.textDark,
                                                  ),
                                            ),
                                            if (costoDe(it) > 0)
                                              Text(
                                                '${_fmtMoney(costoDe(it))} c/u',
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                      fontSize: 11.5,
                                                      color:
                                                          AbakoColors.textFaint,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _fmtQty(it.cantidad),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AbakoColors.textDark,
                                            ),
                                          ),
                                          if (costoDe(it) > 0)
                                            Text(
                                              _fmtMoney(
                                                costoDe(it) * it.cantidad,
                                              ),
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 11.5,
                                                    color:
                                                        AbakoColors.textFaint,
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              if (importeTotal > 0) ...[
                                const Divider(
                                  height: 20,
                                  color: Color(0xFFECEAE3),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Importe a pagar',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AbakoColors.textLabel,
                                      ),
                                    ),
                                    Text(
                                      _fmtMoney(importeTotal),
                                      style: GoogleFonts.bricolageGrotesque(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: AbakoColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (orden.estado == 'pendiente') ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _guardando
                                ? null
                                : () => _marcarRecibida(orden, items),
                            style: FilledButton.styleFrom(
                              backgroundColor: AbakoColors.accentGreen,
                              padding: const EdgeInsets.symmetric(vertical: 15),
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
                                    'Marcar recibida',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _guardando
                                ? null
                                : () => _cancelar(orden),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AbakoColors.statusAgotadoText,
                              side: BorderSide(
                                color: AbakoColors.statusAgotadoText.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancelar orden',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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
