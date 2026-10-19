import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/money_input.dart';
import '../utils/product_avatar.dart';
import '../widgets/barcode_scan_screen.dart';
import 'ajustes_page.dart' show ajustesUmbralStockDefault;
import 'ordenes_compra_page.dart';

const _uuid = Uuid();

// PowerSync no replica la vista `stock_actual` de Postgres (solo tablas
// base), así que sumamos acá directo sobre movimientos_stock. Se suma across
// todos los depósitos (el selector de sucursal está pospuesto, ver memoria
// del proyecto) — con un solo depósito activo hoy da lo mismo.
const _productosQuery = '''
  SELECT
    p.id AS id, p.nombre AS nombre, p.sku AS sku, p.precio AS precio,
    p.costo AS costo, p.categoria AS categoria, p.stock_minimo AS stock_minimo,
    p.activo AS activo,
    COALESCE((
      SELECT SUM(CAST(m.cantidad AS REAL)) FROM movimientos_stock m
      WHERE m.producto_id = p.id
    ), 0) AS stock_actual
  FROM productos p
  ORDER BY p.nombre
''';

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

class _Producto {
  _Producto({
    required this.id,
    required this.nombre,
    required this.sku,
    required this.precio,
    required this.costo,
    required this.categoria,
    required this.stockMinimo,
    required this.stockActual,
    required this.activo,
  });

  final String id;
  final String nombre;
  final String? sku;
  final double precio;
  final double costo;
  final String categoria;
  final double stockMinimo;
  final double stockActual;
  final bool activo;

  static _Producto fromRow(dynamic row) => _Producto(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        sku: row['sku'] as String?,
        precio: double.tryParse('${row['precio']}') ?? 0,
        costo: double.tryParse('${row['costo']}') ?? 0,
        categoria: (row['categoria'] as String?)?.isNotEmpty == true
            ? row['categoria'] as String
            : 'Otros',
        stockMinimo: double.tryParse('${row['stock_minimo']}') ?? 0,
        stockActual: (row['stock_actual'] as num).toDouble(),
        activo: row['activo'] == null ? true : _asBool(row['activo']),
      );

  // Agotado incluye stock negativo (posible por sobregiro, ver trigger de
  // detección) — a diferencia del mockup original que solo miraba ===0.
  String get status {
    if (stockActual <= 0) return 'agotado';
    if (stockActual <= stockMinimo) return 'bajo';
    return 'ok';
  }
}

String _fmtQty(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

String _fmtPct(double n) => '${n >= 0 ? '+' : ''}${n.round()}%';

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

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();

  String _categoryFilter = 'Todos';
  String _statusFilter = 'todos';
  _Producto? _editingProduct;
  bool _isNew = false;

  String? _depositoId;
  double _umbralDefault = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadDepositoId();
    _loadUmbralDefault();
  }

  Future<void> _loadDepositoId() async {
    final rows =
        await db.getAll('SELECT id FROM depositos ORDER BY creado_en LIMIT 1');
    if (mounted && rows.isNotEmpty) {
      setState(() => _depositoId = rows.first['id'] as String);
    }
  }

  Future<void> _loadUmbralDefault() async {
    final umbral = await ajustesUmbralStockDefault();
    if (mounted) setState(() => _umbralDefault = umbral);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _guardar({
    required String nombre,
    required String categoria,
    required String? sku,
    required String precioText,
    required String costoText,
    required String stockMinText,
    required double stock,
  }) async {
    final depositoId = _depositoId;
    final precio = parseMoney(precioText);
    final costo = parseMoney(costoText);
    final stockMin = double.tryParse(stockMinText.replaceAll(',', '.')) ?? 0;
    final ahora = DateTime.now().toIso8601String();

    if (_isNew) {
      if (depositoId == null && stock != 0) {
        throw Exception('No hay ningún depósito configurado todavía.');
      }
      final id = _uuid.v4();
      await db.writeTransaction((tx) async {
        await tx.execute(
          '''INSERT INTO productos
             (id, nombre, sku, precio, costo, categoria, stock_minimo, creado_en)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          [id, nombre, sku, precio, costo, categoria, stockMin, ahora],
        );
        if (stock != 0) {
          await tx.execute(
            '''INSERT INTO movimientos_stock
               (id, producto_id, deposito_id, cantidad, motivo, venta_id, creado_en)
               VALUES (?, ?, ?, ?, 'ajuste', NULL, ?)''',
            [_uuid.v4(), id, depositoId, stock, ahora],
          );
        }
      });
    } else {
      final p = _editingProduct!;
      final delta = stock - p.stockActual;
      if (delta != 0 && depositoId == null) {
        throw Exception('No hay ningún depósito configurado todavía.');
      }
      await db.writeTransaction((tx) async {
        await tx.execute(
          '''UPDATE productos
             SET nombre=?, sku=?, precio=?, costo=?, categoria=?, stock_minimo=?
             WHERE id=?''',
          [nombre, sku, precio, costo, categoria, stockMin, p.id],
        );
        if (delta != 0) {
          await tx.execute(
            '''INSERT INTO movimientos_stock
               (id, producto_id, deposito_id, cantidad, motivo, venta_id, creado_en)
               VALUES (?, ?, ?, ?, 'ajuste', NULL, ?)''',
            [_uuid.v4(), p.id, depositoId, delta, ahora],
          );
        }
      });
    }
  }

  void _openForm(bool isDesktop, {_Producto? producto}) {
    setState(() {
      _editingProduct = producto;
      _isNew = producto == null;
    });
    if (isDesktop) {
      _scaffoldKey.currentState!.openEndDrawer();
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // Usar el context propio del builder (no el de _openForm, que queda
        // fijo) es lo que hace que este Padding se recalcule cuando aparece
        // el teclado — con el context de afuera, MediaQuery.of nunca vuelve
        // a evaluarse y el valor de apertura (sin teclado) queda pegado para
        // siempre, tapando los campos de más abajo del formulario.
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: _buildFormPanel(rounded: true),
          ),
        ),
      );
    }
  }

  Widget _buildFormPanel({required bool rounded}) {
    return _ProductForm(
      key: ValueKey(_editingProduct?.id ?? 'nuevo'),
      title: _isNew ? 'Nuevo producto' : 'Editar producto',
      rounded: rounded,
      existingCategories: _categoriesFromCache,
      initialName: _editingProduct?.nombre ?? '',
      initialCategoria: _editingProduct?.categoria ?? '',
      initialSku: _editingProduct?.sku ?? '',
      initialPrecio: _editingProduct == null || _editingProduct!.precio == 0
          ? ''
          : fmtMoneyInput(_editingProduct!.precio),
      initialCosto: _editingProduct == null || _editingProduct!.costo == 0
          ? ''
          : fmtMoneyInput(_editingProduct!.costo),
      initialStockMinimo: _editingProduct == null
          ? (_umbralDefault == 0 ? '' : _fmtQty(_umbralDefault))
          : _fmtQty(_editingProduct!.stockMinimo),
      initialStock: _editingProduct?.stockActual ?? 0,
      onSave: _guardar,
      onEliminar: _editingProduct == null ? null : () => _eliminarProducto(_editingProduct!),
    );
  }

  Future<void> _eliminarProducto(_Producto p) async {
    await db.execute('UPDATE productos SET activo = false WHERE id = ?', [p.id]);
  }

  List<String> _categoriesFromCache = const [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(_productosQuery),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final productos = snapshot.data!.map(_Producto.fromRow).where((p) => p.activo).toList();
            final categories = <String>{for (final p in productos) p.categoria}
                .toList()
              ..sort();
            _categoriesFromCache = categories;

            final valorVenta = productos.fold<double>(
                0, (t, p) => t + p.precio * p.stockActual);
            final valorCosto = productos.fold<double>(
                0, (t, p) => t + p.costo * p.stockActual);
            final ganancia = valorVenta - valorCosto;
            final gananciaPct = valorCosto == 0 ? null : (ganancia / valorCosto) * 100;
            final bajoCount =
                productos.where((p) => p.status == 'bajo').length;
            final agotadoCount =
                productos.where((p) => p.status == 'agotado').length;

            final q = _searchController.text.trim().toLowerCase();
            final filtered = productos.where((p) {
              final matchesCat =
                  _categoryFilter == 'Todos' || p.categoria == _categoryFilter;
              final matchesStatus =
                  _statusFilter == 'todos' || p.status == _statusFilter;
              final matchesQuery = q.isEmpty ||
                  p.nombre.toLowerCase().contains(q) ||
                  (p.sku?.toLowerCase().contains(q) ?? false);
              return matchesCat && matchesStatus && matchesQuery;
            }).toList();

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: isDesktop ? AbakoColors.cream : AbakoColors.creamOuter,
              endDrawer: isDesktop
                  ? SizedBox(width: 420, child: Drawer(child: _buildFormPanel(rounded: false)))
                  : null,
              body: isDesktop
                  ? _DesktopInventario(
                      productos: filtered,
                      categories: categories,
                      categoryFilter: _categoryFilter,
                      statusFilter: _statusFilter,
                      searchController: _searchController,
                      valorVenta: valorVenta,
                      valorCosto: valorCosto,
                      ganancia: ganancia,
                      gananciaPct: gananciaPct,
                      totalCount: productos.length,
                      bajoCount: bajoCount,
                      agotadoCount: agotadoCount,
                      onCategoryFilter: (c) => setState(() => _categoryFilter = c),
                      onStatusFilter: (s) => setState(() => _statusFilter = s),
                      onNew: () => _openForm(true),
                      onEdit: (p) => _openForm(true, producto: p),
                    )
                  : _MobileInventario(
                      productos: filtered,
                      categories: categories,
                      categoryFilter: _categoryFilter,
                      searchController: _searchController,
                      valorVenta: valorVenta,
                      valorCosto: valorCosto,
                      ganancia: ganancia,
                      gananciaPct: gananciaPct,
                      onCategoryFilter: (c) => setState(() => _categoryFilter = c),
                      onNew: () => _openForm(false),
                      onEdit: (p) => _openForm(false, producto: p),
                    ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Escritorio
// ---------------------------------------------------------------------------

class _DesktopInventario extends StatelessWidget {
  const _DesktopInventario({
    required this.productos,
    required this.categories,
    required this.categoryFilter,
    required this.statusFilter,
    required this.searchController,
    required this.valorVenta,
    required this.valorCosto,
    required this.ganancia,
    required this.gananciaPct,
    required this.totalCount,
    required this.bajoCount,
    required this.agotadoCount,
    required this.onCategoryFilter,
    required this.onStatusFilter,
    required this.onNew,
    required this.onEdit,
  });

  final List<_Producto> productos;
  final List<String> categories;
  final String categoryFilter;
  final String statusFilter;
  final TextEditingController searchController;
  final double valorVenta;
  final double valorCosto;
  final double ganancia;
  final double? gananciaPct;
  final int totalCount;
  final int bajoCount;
  final int agotadoCount;
  final ValueChanged<String> onCategoryFilter;
  final ValueChanged<String> onStatusFilter;
  final VoidCallback onNew;
  final ValueChanged<_Producto> onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inventario',
                          style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w600,
                              fontSize: 27,
                              color: AbakoColors.textDark)),
                      const SizedBox(height: 3),
                      Text('$totalCount productos',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, color: AbakoColors.textFaint)),
                    ],
                  ),
                ),
                const OrdenesCompraButton(),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onNew,
                  style: FilledButton.styleFrom(
                    backgroundColor: AbakoColors.accentGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Agregar producto',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _ValorInventarioCard(
                    valorVenta: valorVenta,
                    valorCosto: valorCosto,
                    ganancia: ganancia,
                    gananciaPct: gananciaPct,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiCard(
                    label: 'Productos',
                    value: '$totalCount',
                    selected: statusFilter == 'todos',
                    valueColor: AbakoColors.textDark,
                    onTap: () => onStatusFilter('todos'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiCard(
                    label: 'Bajo stock',
                    value: '$bajoCount',
                    dotColor: AbakoColors.statusBajoDot,
                    selected: statusFilter == 'bajo',
                    valueColor: AbakoColors.statusBajoText,
                    onTap: () => onStatusFilter('bajo'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KpiCard(
                    label: 'Agotados',
                    value: '$agotadoCount',
                    dotColor: AbakoColors.statusAgotadoDot,
                    selected: statusFilter == 'agotado',
                    valueColor: AbakoColors.statusAgotadoText,
                    onTap: () => onStatusFilter('agotado'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 22, 32, 14),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final c in ['Todos', ...categories])
                          Padding(
                            padding: const EdgeInsets.only(right: 9),
                            child: _CategoryChip(
                              label: c,
                              selected: c == categoryFilter,
                              onTap: () => onCategoryFilter(c),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(width: 300, child: _SearchField(controller: searchController)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFECEAE3)),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      decoration: const BoxDecoration(
                        color: AbakoColors.cream,
                        border: Border(bottom: BorderSide(color: Color(0xFFF1EFE8))),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: _colHeader('Producto')),
                          Expanded(child: _colHeader('Categoría')),
                          Expanded(child: _colHeader('Precio')),
                          Expanded(flex: 2, child: _colHeader('Stock')),
                          const SizedBox(width: 34),
                        ],
                      ),
                    ),
                    Expanded(
                      child: productos.isEmpty
                          ? Center(
                              child: Text('No se encontraron productos con esos filtros.',
                                  style: GoogleFonts.plusJakartaSans(
                                      color: AbakoColors.textFaint, fontSize: 14)))
                          : ListView.separated(
                              itemCount: productos.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, color: Color(0xFFF4F2EB)),
                              itemBuilder: (context, i) =>
                                  _ProductRowDesktop(producto: productos[i], onEdit: onEdit),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String label) => Text(
        label.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AbakoColors.textFaint),
      );
}

class _ValorInventarioCard extends StatelessWidget {
  const _ValorInventarioCard({
    required this.valorVenta,
    required this.valorCosto,
    required this.ganancia,
    required this.gananciaPct,
  });
  final double valorVenta;
  final double valorCosto;
  final double ganancia;
  final double? gananciaPct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: AbakoColors.panelGreen, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Valor del inventario',
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.creamText.withValues(alpha: 0.75))),
          const SizedBox(height: 10),
          Row(children: [_ValorStat('Venta', _fmtMoney(valorVenta)), _ValorStat('Costo', _fmtMoney(valorCosto))]),
          const SizedBox(height: 10),
          Row(children: [
            _ValorStat('Ganancia', _fmtMoney(ganancia)),
            _ValorStat('Margen', gananciaPct == null ? '—' : _fmtPct(gananciaPct!)),
          ]),
        ],
      ),
    );
  }
}

class _ValorStat extends StatelessWidget {
  const _ValorStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.creamText.withValues(alpha: 0.7))),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 18, color: AbakoColors.creamText)),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.valueColor,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final String value;
  final bool selected;
  final Color valueColor;
  final Color? dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AbakoColors.accentGreen : const Color(0xFFECEAE3), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(value,
                      style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700, fontSize: 27, color: valueColor)),
                  if (dotColor != null) ...[
                    const SizedBox(width: 9),
                    Container(
                        width: 9, height: 9, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AbakoColors.accentGreen : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AbakoColors.accentGreen : AbakoColors.inputBorder, width: 1.5),
          ),
          child: Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AbakoColors.textLabel)),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  bool get _camaraDisponible => !kIsWeb && Platform.isAndroid;

  Future<void> _escanear(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code != null) controller.text = code;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AbakoColors.textDark),
      decoration: InputDecoration(
        hintText: 'Buscar producto o código…',
        hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
        prefixIcon: const Icon(Icons.search, size: 19, color: AbakoColors.textFaint),
        suffixIcon: _camaraDisponible
            ? IconButton(
                icon: const Icon(Icons.camera_alt_outlined, size: 19),
                onPressed: () => _escanear(context),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.accentGreen, width: 1.5)),
      ),
    );
  }
}

class _ProductRowDesktop extends StatelessWidget {
  const _ProductRowDesktop({required this.producto, required this.onEdit});
  final _Producto producto;
  final ValueChanged<_Producto> onEdit;

  @override
  Widget build(BuildContext context) {
    final st = _statusStyle(producto.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _Avatar(nombre: producto.nombre, size: 42),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(producto.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                      Text(producto.sku?.isNotEmpty == true ? producto.sku! : 'Sin código',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.placeholder)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(producto.categoria,
                style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: AbakoColors.textLabel)),
          ),
          Expanded(
            child: Text(_fmtMoney(producto.precio),
                style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700, fontSize: 15, color: AbakoColors.textDark)),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(_fmtQty(producto.stockActual),
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: AbakoColors.textDark)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(7)),
                  child: Text(st.label,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: st.text)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 34,
            child: IconButton(
              onPressed: () => onEdit(producto),
              icon: const Icon(Icons.edit_outlined, size: 17),
              color: AbakoColors.textMuted,
              style: IconButton.styleFrom(
                side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Móvil
// ---------------------------------------------------------------------------

class _MobileInventario extends StatelessWidget {
  const _MobileInventario({
    required this.productos,
    required this.categories,
    required this.categoryFilter,
    required this.searchController,
    required this.valorVenta,
    required this.valorCosto,
    required this.ganancia,
    required this.gananciaPct,
    required this.onCategoryFilter,
    required this.onNew,
    required this.onEdit,
  });

  final List<_Producto> productos;
  final List<String> categories;
  final String categoryFilter;
  final TextEditingController searchController;
  final double valorVenta;
  final double valorCosto;
  final double ganancia;
  final double? gananciaPct;
  final ValueChanged<String> onCategoryFilter;
  final VoidCallback onNew;
  final ValueChanged<_Producto> onEdit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AbakoColors.panelGreen,
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text('Inventario',
                            style: GoogleFonts.bricolageGrotesque(
                                fontWeight: FontWeight.w600, fontSize: 21, color: AbakoColors.creamText)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const OrdenesCompraPage()),
                        ),
                        icon: Icon(Icons.local_shipping_outlined, color: AbakoColors.creamText, size: 21),
                        tooltip: 'Órdenes de compra',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(children: [_ValorStat('Venta', _fmtMoney(valorVenta)), _ValorStat('Costo', _fmtMoney(valorCosto))]),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _ValorStat('Ganancia', _fmtMoney(ganancia)),
                      _ValorStat('Margen', gananciaPct == null ? '—' : _fmtPct(gananciaPct!)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SearchField(controller: searchController),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in ['Todos', ...categories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _CategoryChip(
                            label: c, selected: c == categoryFilter, onTap: () => onCategoryFilter(c)),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: productos.isEmpty
                  ? Center(
                      child: Text('No se encontraron productos.',
                          style: GoogleFonts.plusJakartaSans(color: AbakoColors.textFaint, fontSize: 13.5)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: productos.length,
                      itemBuilder: (context, i) =>
                          _ProductCardMobile(producto: productos[i], onTap: () => onEdit(productos[i])),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton(
            backgroundColor: AbakoColors.accentGreen,
            onPressed: onNew,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _ProductCardMobile extends StatelessWidget {
  const _ProductCardMobile({required this.producto, required this.onTap});
  final _Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = _statusStyle(producto.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFECEAE3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _Avatar(nombre: producto.nombre, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(producto.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                    Text('${producto.categoria} · ${_fmtMoney(producto.precio)}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmtQty(producto.stockActual),
                      style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700, fontSize: 17, color: AbakoColors.textDark)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(6)),
                    child: Text(st.label,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: st.text)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compartidos
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nombre, required this.size});
  final String nombre;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colorOf(nombre), borderRadius: BorderRadius.circular(size * 0.26)),
      alignment: Alignment.center,
      child: Text(monoOf(nombre),
          style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w700, fontSize: size * 0.33, color: Colors.white)),
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.bg, this.text);
  final String label;
  final Color bg;
  final Color text;
}

_StatusStyle _statusStyle(String status) {
  switch (status) {
    case 'bajo':
      return const _StatusStyle('Bajo', AbakoColors.statusBajoBg, AbakoColors.statusBajoText);
    case 'agotado':
      return const _StatusStyle('Agotado', AbakoColors.statusAgotadoBg, AbakoColors.statusAgotadoText);
    default:
      return const _StatusStyle('En stock', AbakoColors.statusOkBg, AbakoColors.statusOkText);
  }
}

// ---------------------------------------------------------------------------
// Formulario alta / edición
// ---------------------------------------------------------------------------

class _ProductForm extends StatefulWidget {
  const _ProductForm({
    super.key,
    required this.title,
    required this.rounded,
    required this.existingCategories,
    required this.initialName,
    required this.initialCategoria,
    required this.initialSku,
    required this.initialPrecio,
    required this.initialCosto,
    required this.initialStockMinimo,
    required this.initialStock,
    required this.onSave,
    this.onEliminar,
  });

  final String title;
  final bool rounded;
  final List<String> existingCategories;
  final String initialName;
  final String initialCategoria;
  final String initialSku;
  final String initialPrecio;
  final String initialCosto;
  final String initialStockMinimo;
  final double initialStock;
  final Future<void> Function({
    required String nombre,
    required String categoria,
    required String? sku,
    required String precioText,
    required String costoText,
    required String stockMinText,
    required double stock,
  }) onSave;
  final Future<void> Function()? onEliminar;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final _nombreCtrl = TextEditingController(text: widget.initialName)
    ..addListener(() => setState(() {}));
  late final _categoriaCtrl = TextEditingController(text: widget.initialCategoria)
    ..addListener(() => setState(() {}));
  late final _skuCtrl = TextEditingController(text: widget.initialSku);
  late final _precioCtrl = TextEditingController(text: widget.initialPrecio);
  late final _costoCtrl = TextEditingController(text: widget.initialCosto);
  late final _stockMinCtrl = TextEditingController(text: widget.initialStockMinimo);
  late double _stock = widget.initialStock;
  late final _stockCtrl = TextEditingController(text: _fmtQty(_stock));

  bool _saving = false;
  String? _error;

  bool get _camaraDisponible => !kIsWeb && Platform.isAndroid;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _categoriaCtrl.dispose();
    _skuCtrl.dispose();
    _precioCtrl.dispose();
    _costoCtrl.dispose();
    _stockMinCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  void _adjustStock(double delta) {
    setState(() {
      _stock = (_stock + delta) < 0 ? 0 : _stock + delta;
      _stockCtrl.text = _fmtQty(_stock);
    });
  }

  void _onStockTextChanged(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed != null) _stock = parsed < 0 ? 0 : parsed;
  }

  Future<void> _escanearSku() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code != null) setState(() => _skuCtrl.text = code);
  }

  Future<void> _submit() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresá un nombre.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sku = _skuCtrl.text.trim();
      await widget.onSave(
        nombre: nombre,
        categoria: _categoriaCtrl.text.trim().isEmpty ? 'Otros' : _categoriaCtrl.text.trim(),
        sku: sku.isEmpty ? null : sku,
        precioText: _precioCtrl.text,
        costoText: _costoCtrl.text,
        stockMinText: _stockMinCtrl.text,
        stock: _stock,
      );
      if (mounted) {
        mostrarSnack(context, widget.title == 'Nuevo producto' ? 'Producto agregado' : 'Producto actualizado');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmarEliminar() async {
    final nombre = _nombreCtrl.text.trim();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text(
            '${nombre.isEmpty ? 'Este producto' : nombre} ya no va a aparecer en Inventario ni se va a poder vender. Su historial de ventas se conserva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AbakoColors.statusAgotadoText),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.onEliminar!();
      if (mounted) {
        mostrarSnack(context, 'Producto eliminado');
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AbakoColors.accentGreen, width: 1.5)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AbakoColors.textLabel)),
      );

  @override
  Widget build(BuildContext context) {
    final name = _nombreCtrl.text.trim();
    return Container(
      decoration: BoxDecoration(
        color: AbakoColors.cream,
        borderRadius: widget.rounded ? const BorderRadius.vertical(top: Radius.circular(24)) : BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 19, color: AbakoColors.textDark)),
                ),
                if (widget.onEliminar != null)
                  IconButton(
                    onPressed: _saving ? null : _confirmarEliminar,
                    icon: const Icon(Icons.delete_outline, size: 19),
                    color: AbakoColors.statusAgotadoText,
                    style: IconButton.styleFrom(backgroundColor: AbakoColors.statusAgotadoBg),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 19),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1EFE8)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1EFE8)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Avatar(nombre: name.isEmpty ? '?' : name, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('El ícono se genera con las iniciales del producto.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _label('Nombre del producto'),
                  TextField(controller: _nombreCtrl, decoration: _dec('Ej. Refresco Coca-Cola 600 ml')),
                  const SizedBox(height: 16),
                  _label('Código de barras (SKU)'),
                  TextField(
                    controller: _skuCtrl,
                    decoration: _dec('Opcional').copyWith(
                      suffixIcon: _camaraDisponible
                          ? IconButton(icon: const Icon(Icons.camera_alt_outlined, size: 18), onPressed: _escanearSku)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('Categoría'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in widget.existingCategories)
                        _CategoryChip(
                          label: c,
                          selected: _categoriaCtrl.text.trim() == c,
                          onTap: () => setState(() => _categoriaCtrl.text = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: _categoriaCtrl, decoration: _dec('O escribí una categoría nueva')),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Precio'),
                            TextField(
                              controller: _precioCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: const [MoneyInputFormatter()],
                              decoration: _dec('0').copyWith(prefixText: '\$ '),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Costo'),
                            TextField(
                              controller: _costoCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: const [MoneyInputFormatter()],
                              decoration: _dec('Opcional').copyWith(prefixText: '\$ '),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label('Stock mínimo'),
                  TextField(
                    controller: _stockMinCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('0'),
                  ),
                  const SizedBox(height: 16),
                  _label('Existencias actuales'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AbakoColors.inputBorder, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _stepBtn(Icons.remove, () => _adjustStock(-1)),
                        Expanded(
                          child: TextField(
                            controller: _stockCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 24, color: AbakoColors.textDark),
                            decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
                            onChanged: _onStockTextChanged,
                          ),
                        ),
                        _stepBtn(Icons.add, () => _adjustStock(1)),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.red.shade700)),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1EFE8)),
          Padding(
            // El +22 base de siempre, más el inset del sistema (gesture bar
            // o barra de navegación de 3 botones) para que estos botones
            // nunca queden tapados por eso en el celular.
            padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Cancelar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AbakoColors.textLabel)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AbakoColors.accentGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(widget.title == 'Nuevo producto' ? 'Agregar producto' : 'Guardar cambios',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 38,
      height: 38,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: AbakoColors.cream,
          side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Icon(icon, size: 18, color: AbakoColors.textLabel),
      ),
    );
  }
}
