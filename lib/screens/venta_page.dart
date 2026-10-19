import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/money_input.dart';
import '../utils/product_avatar.dart';
import '../widgets/barcode_scan_screen.dart';
import '../widgets/venta_confirmada_popup.dart';
import 'caja_page.dart';

const _uuid = Uuid();

const _metodosPago = ['Efectivo', 'Tarjeta', 'Transferencia'];

const _productosQuery = '''
  SELECT id, nombre, sku, precio, costo, categoria, activo FROM productos ORDER BY nombre
''';

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

class _ProductoVenta {
  _ProductoVenta({
    required this.id,
    required this.nombre,
    required this.sku,
    required this.precio,
    required this.costo,
    required this.categoria,
  });

  final String id;
  final String nombre;
  final String? sku;
  final double precio;
  final double costo;
  final String categoria;

  static _ProductoVenta fromRow(dynamic row) => _ProductoVenta(
    id: row['id'] as String,
    nombre: row['nombre'] as String,
    sku: row['sku'] as String?,
    precio: double.tryParse('${row['precio']}') ?? 0,
    costo: double.tryParse('${row['costo']}') ?? 0,
    categoria: (row['categoria'] as String?)?.isNotEmpty == true
        ? row['categoria'] as String
        : 'Otros',
  );
}

class _CartLine {
  _CartLine({required this.producto});
  final _ProductoVenta producto;
  double cantidad = 1;
  double get importe => producto.precio * cantidad;
  double get ganancia => (producto.precio - producto.costo) * cantidad;
}

class _ClienteOption {
  const _ClienteOption(this.id, this.nombre);
  final String id;
  final String nombre;
}

class _PagoResumen {
  _PagoResumen({
    required this.metodo,
    required this.monto,
    this.efectivoRecibido,
    this.vuelto,
  });
  final String metodo;
  final double monto;
  final double? efectivoRecibido;
  final double? vuelto;
}

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

class VentaPage extends StatefulWidget {
  const VentaPage({super.key});

  @override
  State<VentaPage> createState() => _VentaPageState();
}

class _VentaPageState extends State<VentaPage> {
  final _searchController = TextEditingController();

  String _categoryFilter = 'Todos';
  String? _depositoId;
  final List<_CartLine> _cart = [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double get _total => _cart.fold(0, (t, l) => t + l.importe);
  int get _itemCount => _cart.fold(0, (t, l) => t + l.cantidad.round());

  void _addProducto(_ProductoVenta p) {
    setState(() {
      final i = _cart.indexWhere((l) => l.producto.id == p.id);
      if (i >= 0) {
        _cart[i].cantidad += 1;
      } else {
        _cart.add(_CartLine(producto: p));
      }
    });
  }

  void _ajustarCantidad(int index, double delta) {
    setState(() {
      final nueva = _cart[index].cantidad + delta;
      if (nueva <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].cantidad = nueva;
      }
    });
  }

  void _quitarLinea(int index) => setState(() => _cart.removeAt(index));

  void _buscarPorCodigoExacto(String codigo, List<_ProductoVenta> productos) {
    final code = codigo.trim();
    if (code.isEmpty) return;
    final match = productos.where((p) => p.sku == code);
    if (match.isEmpty) {
      mostrarSnack(
        context,
        'No se encontró ningún producto con código "$code"',
        kind: SnackKind.error,
      );
      return;
    }
    _addProducto(match.first);
    _searchController.clear();
  }

  Future<void> _confirmarVenta(
    List<_PagoResumen> pagos,
    String? clienteId,
  ) async {
    if (_cart.isEmpty || _depositoId == null || pagos.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final ventaId = _uuid.v4();
      final ahora = DateTime.now().toIso8601String();
      final total = _total;
      final lineas = List<_CartLine>.from(_cart);

      await db.writeTransaction((tx) async {
        await tx.execute(
          '''INSERT INTO ventas (id, deposito_id, total, estado, cliente_id, creado_en)
             VALUES (?, ?, ?, 'completada', ?, ?)''',
          [ventaId, _depositoId, total, clienteId, ahora],
        );
        for (final linea in lineas) {
          await tx.execute(
            '''INSERT INTO movimientos_stock
               (id, producto_id, deposito_id, cantidad, motivo, venta_id, creado_en)
               VALUES (?, ?, ?, ?, 'venta', ?, ?)''',
            [
              _uuid.v4(),
              linea.producto.id,
              _depositoId,
              -linea.cantidad,
              ventaId,
              ahora,
            ],
          );
        }
        for (final pago in pagos) {
          await tx.execute(
            '''INSERT INTO pagos_venta
               (id, venta_id, metodo, monto, efectivo_recibido, vuelto, creado_en)
               VALUES (?, ?, ?, ?, ?, ?, ?)''',
            [
              _uuid.v4(),
              ventaId,
              pago.metodo,
              pago.monto,
              pago.efectivoRecibido,
              pago.vuelto,
              ahora,
            ],
          );
        }
      });

      if (mounted) {
        setState(() => _cart.clear());
        // Se difiere al próximo frame para que el popup se abra recién
        // después de que la hoja de cobro móvil termine de cerrarse
        // (Navigator.maybePop() en _TicketPanelState._handleConfirmar) —
        // si se abriera en el mismo frame, ese maybePop() cerraría el
        // popup en vez de la hoja, por quedar arriba en la pila.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) mostrarVentaConfirmada(context, total: total);
        });
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _abrirCobro() {
    if (_cart.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _TicketPanel(
          cart: _cart,
          guardando: _guardando,
          rounded: true,
          onAjustar: _ajustarCantidad,
          onQuitar: _quitarLinea,
          onConfirmar: _confirmarVenta,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResultSet>(
      stream: db.watch(cajasQuery),
      builder: (context, cajasSnap) {
        if (!cajasSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final abierta = cajaAbiertaDe(
          cajasSnap.data!.map(Caja.fromRow).toList(),
        );
        final ahora = DateTime.now();
        final esDeHoy =
            abierta != null &&
            abierta.creadoEn.year == ahora.year &&
            abierta.creadoEn.month == ahora.month &&
            abierta.creadoEn.day == ahora.day;

        if (abierta == null || !esDeHoy) {
          return _SinCajaAbierta(
            cajaViejaSinCerrar: abierta != null && !esDeHoy,
          );
        }

        return _buildVenta(context);
      },
    );
  }

  Widget _buildVenta(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(_productosQuery),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final productos = snapshot.data!
                .where((row) => _asBool(row['activo']))
                .map(_ProductoVenta.fromRow)
                .toList();
            final categories = <String>{
              for (final p in productos) p.categoria,
            }.toList()..sort();

            final q = _searchController.text.trim().toLowerCase();
            final filtered = productos.where((p) {
              final matchesCat =
                  _categoryFilter == 'Todos' || p.categoria == _categoryFilter;
              final matchesQuery =
                  q.isEmpty ||
                  p.nombre.toLowerCase().contains(q) ||
                  (p.sku?.toLowerCase().contains(q) ?? false);
              return matchesCat && matchesQuery;
            }).toList();

            final grid = _ProductGrid(
              isDesktop: isDesktop,
              productos: filtered,
              totalCount: productos.length,
              categories: categories,
              categoryFilter: _categoryFilter,
              searchController: _searchController,
              onCategoryFilter: (c) => setState(() => _categoryFilter = c),
              onSearchSubmit: (code) => _buscarPorCodigoExacto(code, productos),
              onTapProducto: _addProducto,
            );

            if (isDesktop) {
              return ColoredBox(
                color: AbakoColors.cream,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: grid),
                    SizedBox(
                      width: 380,
                      child: _TicketPanel(
                        cart: _cart,
                        guardando: _guardando,
                        rounded: false,
                        onAjustar: _ajustarCantidad,
                        onQuitar: _quitarLinea,
                        onConfirmar: _confirmarVenta,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ColoredBox(
              color: AbakoColors.creamOuter,
              child: Stack(
                children: [
                  grid,
                  if (_cart.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                      child: _CartBar(
                        itemCount: _itemCount,
                        total: _total,
                        onTap: _abrirCobro,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Bloquea la venta cuando no hay una caja abierta hoy (ver feature "Caja",
/// sesión 2026-08-29). Las demás pantallas (Inicio, Inventario, etc.) no se
/// bloquean, solo muestran un recordatorio — acá sí se bloquea porque vender
/// sin caja abierta no tiene sentido para el control de efectivo.
class _SinCajaAbierta extends StatelessWidget {
  const _SinCajaAbierta({required this.cajaViejaSinCerrar});
  final bool cajaViejaSinCerrar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AbakoColors.creamOuter,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.point_of_sale_outlined,
                size: 40,
                color: AbakoColors.textFaint,
              ),
              const SizedBox(height: 16),
              Text(
                cajaViejaSinCerrar
                    ? 'Quedó una caja sin cerrar'
                    : 'No hay una caja abierta',
                textAlign: TextAlign.center,
                style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: AbakoColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cajaViejaSinCerrar
                    ? 'Cerrá la caja de un día anterior antes de seguir vendiendo.'
                    : 'Abrí la caja para empezar a vender.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: AbakoColors.textFaint,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: AbakoColors.creamOuter,
                      appBar: AppBar(
                        backgroundColor: AbakoColors.panelGreen,
                        foregroundColor: AbakoColors.creamText,
                        elevation: 0,
                        title: Text(
                          'Caja',
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            color: AbakoColors.creamText,
                          ),
                        ),
                      ),
                      body: const CajaPage(),
                    ),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AbakoColors.accentGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  cajaViejaSinCerrar ? 'Ir a cerrar caja' : 'Ir a abrir caja',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 14,
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

// ---------------------------------------------------------------------------
// Grilla de productos
// ---------------------------------------------------------------------------

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.isDesktop,
    required this.productos,
    required this.totalCount,
    required this.categories,
    required this.categoryFilter,
    required this.searchController,
    required this.onCategoryFilter,
    required this.onSearchSubmit,
    required this.onTapProducto,
  });

  final bool isDesktop;
  final List<_ProductoVenta> productos;
  final int totalCount;
  final List<String> categories;
  final String categoryFilter;
  final TextEditingController searchController;
  final ValueChanged<String> onCategoryFilter;
  final ValueChanged<String> onSearchSubmit;
  final ValueChanged<_ProductoVenta> onTapProducto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Punto de venta',
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w600,
                      fontSize: 27,
                      color: AbakoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$totalCount productos',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AbakoColors.textFaint,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              color: AbakoColors.panelGreen,
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 14,
                20,
                18,
              ),
              child: Text(
                'Punto de venta',
                style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w600,
                  fontSize: 21,
                  color: AbakoColors.creamText,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 32 : 16,
              isDesktop ? 20 : 14,
              isDesktop ? 32 : 16,
              0,
            ),
            child: _SearchField(
              controller: searchController,
              onSubmitted: onSearchSubmit,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 32 : 16,
              14,
              isDesktop ? 32 : 16,
              10,
            ),
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
          Expanded(
            child: productos.isEmpty
                ? Center(
                    child: Text(
                      'No se encontraron productos con esos filtros.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AbakoColors.textFaint,
                        fontSize: 14,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 32 : 16,
                      4,
                      isDesktop ? 32 : 16,
                      100,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 168,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                    itemCount: productos.length,
                    itemBuilder: (context, i) => _ProductTile(
                      producto: productos[i],
                      onTap: () => onTapProducto(productos[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.producto, required this.onTap});
  final _ProductoVenta producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFECEAE3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: colorOf(producto.nombre),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  monoOf(producto.nombre),
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                producto.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AbakoColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                _fmtMoney(producto.precio),
                style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AbakoColors.accentGreenHover,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
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
            border: Border.all(
              color: selected
                  ? AbakoColors.accentGreen
                  : AbakoColors.inputBorder,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AbakoColors.textLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  bool get _camaraDisponible => !kIsWeb && Platform.isAndroid;

  Future<void> _escanear(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code != null) onSubmitted(code);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: AbakoColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar producto o escanear código…',
        hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
        prefixIcon: const Icon(
          Icons.search,
          size: 19,
          color: AbakoColors.textFaint,
        ),
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
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AbakoColors.inputBorder,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AbakoColors.inputBorder,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AbakoColors.accentGreen,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de carrito (móvil)
// ---------------------------------------------------------------------------

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.itemCount,
    required this.total,
    required this.onTap,
  });
  final int itemCount;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AbakoColors.panelGreen,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AbakoColors.accentGreen,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$itemCount',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ver venta actual',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AbakoColors.creamText,
                  ),
                ),
              ),
              Text(
                _fmtMoney(total),
                style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AbakoColors.creamText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket + cobro
// ---------------------------------------------------------------------------

class _TicketPanel extends StatefulWidget {
  const _TicketPanel({
    required this.cart,
    required this.guardando,
    required this.rounded,
    required this.onAjustar,
    required this.onQuitar,
    required this.onConfirmar,
  });

  final List<_CartLine> cart;
  final bool guardando;
  final bool rounded;
  final void Function(int index, double delta) onAjustar;
  final ValueChanged<int> onQuitar;
  final Future<void> Function(List<_PagoResumen> pagos, String? clienteId)
  onConfirmar;

  @override
  State<_TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<_TicketPanel> {
  final List<_PagoLineState> _pagos = [];
  String? _clienteId;
  String? _clienteNombre;

  @override
  void dispose() {
    for (final p in _pagos) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirCliente() async {
    final elegido = await _pickCliente(context);
    if (elegido != null) {
      setState(() {
        _clienteId = elegido.id;
        _clienteNombre = elegido.nombre;
      });
    }
  }

  void _quitarCliente() => setState(() {
    _clienteId = null;
    _clienteNombre = null;
  });

  // Se recalcula del carrito en cada build en vez de recibir un total fijo
  // del padre: en la hoja de cobro móvil (showModalBottomSheet), el padre
  // vive en una ruta separada del Navigator y no reconstruye este widget
  // cuando cambia el carrito — un total pasado por parámetro quedaba
  // "congelado" en el valor de cuando se abrió la hoja, sin reflejar
  // cantidades ajustadas después (bug real encontrado por Franco).
  double get _currentTotal => widget.cart.fold(0.0, (t, l) => t + l.importe);

  double get _asignado => _pagos.fold(0, (t, p) => t + p.monto);
  double get _restante => _currentTotal - _asignado;

  bool get _puedeConfirmar {
    if (widget.cart.isEmpty || _pagos.isEmpty) return false;
    if (_restante.abs() > 0.005) return false;
    for (final p in _pagos) {
      if (p.metodo == 'Efectivo') {
        final recibido = p.recibido;
        if (recibido == null || recibido < p.monto - 0.005) return false;
      }
    }
    return true;
  }

  void _toggleMetodo(String metodo) {
    setState(() {
      final i = _pagos.indexWhere((p) => p.metodo == metodo);
      if (i >= 0) {
        _pagos[i].dispose();
        _pagos.removeAt(i);
      } else {
        final faltante = _restante > 0 ? _restante : _currentTotal;
        final linea = _PagoLineState(metodo, fmtMoneyInput(faltante));
        linea.montoCtrl.addListener(() => setState(() {}));
        if (metodo == 'Efectivo') {
          linea.recibidoCtrl.addListener(() => setState(() {}));
        }
        _pagos.add(linea);
      }
    });
  }

  Future<void> _handleConfirmar() async {
    final resumen = [
      for (final p in _pagos)
        _PagoResumen(
          metodo: p.metodo,
          monto: p.monto,
          efectivoRecibido: p.recibido,
          vuelto: p.vuelto,
        ),
    ];
    await widget.onConfirmar(resumen, _clienteId);
    if (mounted) {
      for (final p in _pagos) {
        p.dispose();
      }
      setState(() {
        _pagos.clear();
        _clienteId = null;
        _clienteNombre = null;
      });
    }
    // Solo en la hoja de cobro móvil hay una ruta modal que cerrar; en
    // escritorio el panel vive embebido y no debe tocar la navegación.
    if (widget.rounded && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final ganancia = widget.cart.fold<double>(
      0,
      (t, l) => t + l.ganancia,
    );

    // El sheet vive dentro de un FractionallySizedBox de alto fijo (no dentro
    // de un Scaffold que se resizee solo), así que si no achicamos nosotros
    // mismos el alto disponible cuando aparece el teclado, el contenedor
    // sigue ocupando el mismo lugar en pantalla y el teclado lo tapa por
    // encima — el auto-scroll de los campos no sirve de nada si el viewport
    // nunca se achica. Este Padding es lo que efectivamente "achica" el
    // sheet para que el resto (SingleChildScrollView + ensureVisible) tenga
    // un viewport que realmente termina justo arriba del teclado.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AbakoColors.cream,
          border: widget.rounded
              ? null
              : const Border(left: BorderSide(color: Color(0xFFECEAE3))),
          borderRadius: widget.rounded
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : BorderRadius.zero,
        ),
        child: SafeArea(
          top: widget.rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Venta actual',
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          color: AbakoColors.textDark,
                        ),
                      ),
                    ),
                    if (widget.rounded)
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _elegirCliente,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: AbakoColors.inputBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 17,
                          color: AbakoColors.textFaint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _clienteNombre ?? 'Sin cliente (opcional)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _clienteNombre != null
                                  ? AbakoColors.textDark
                                  : AbakoColors.textFaint,
                            ),
                          ),
                        ),
                        if (_clienteNombre != null)
                          IconButton(
                            onPressed: _quitarCliente,
                            icon: const Icon(Icons.close, size: 15),
                            color: AbakoColors.textFaint,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          )
                        else
                          const Icon(
                            Icons.chevron_right,
                            size: 17,
                            color: AbakoColors.textFaint,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1EFE8)),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      widget.cart.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Tu venta está vacía.\nTocá un producto para agregarlo.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13.5,
                                    color: AbakoColors.textFaint,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              itemCount: widget.cart.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) => _TicketLine(
                                linea: widget.cart[i],
                                onAjustar: (d) =>
                                    setState(() => widget.onAjustar(i, d)),
                                onQuitar: () =>
                                    setState(() => widget.onQuitar(i)),
                              ),
                            ),
                      const Divider(height: 1, color: Color(0xFFF1EFE8)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _totalRow(
                              'Ganancia',
                              _fmtMoney(ganancia),
                              muted: true,
                            ),
                            const SizedBox(height: 6),
                            _totalRow(
                              'Total',
                              _fmtMoney(_currentTotal),
                              big: true,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Método de pago',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AbakoColors.textLabel,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final m in _metodosPago)
                                  _CategoryChip(
                                    label: m,
                                    selected: _pagos.any((p) => p.metodo == m),
                                    onTap: () => _toggleMetodo(m),
                                  ),
                              ],
                            ),
                            if (_pagos.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              for (final p in _pagos)
                                _PagoLineRow(
                                  pago: p,
                                  onQuitar: () => _toggleMetodo(p.metodo),
                                ),
                              _totalRow(
                                'Restante',
                                _fmtMoney(_restante),
                                muted: _restante.abs() <= 0.005,
                                warn: _restante.abs() > 0.005,
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: !_puedeConfirmar || widget.guardando
                                  ? null
                                  : _handleConfirmar,
                              style: FilledButton.styleFrom(
                                backgroundColor: AbakoColors.accentGreen,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: widget.guardando
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Cobrar ${_fmtMoney(_currentTotal)}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalRow(
    String label,
    String value, {
    bool muted = false,
    bool big = false,
    bool warn = false,
  }) {
    final valueColor = warn ? Colors.red.shade700 : AbakoColors.textFaint;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: big ? 15 : 13,
                fontWeight: big || warn ? FontWeight.w700 : FontWeight.w500,
                color: warn
                    ? valueColor
                    : (muted ? AbakoColors.textFaint : AbakoColors.textDark),
              ),
            ),
          ),
          Text(
            value,
            style: big
                ? GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w700,
                    fontSize: 21,
                    color: AbakoColors.textDark,
                  )
                : GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Línea de pago editable (monto y, para Efectivo, recibido/vuelto)
// ---------------------------------------------------------------------------

class _PagoLineState {
  _PagoLineState(this.metodo, String montoInicial)
    : montoCtrl = TextEditingController(text: montoInicial) {
    montoFocus.addListener(() => _scrollIntoViewOnFocus(montoFocus));
    recibidoFocus.addListener(() => _scrollIntoViewOnFocus(recibidoFocus));
  }

  final String metodo;
  final TextEditingController montoCtrl;
  final TextEditingController recibidoCtrl = TextEditingController();
  final FocusNode montoFocus = FocusNode();
  final FocusNode recibidoFocus = FocusNode();

  // El scroll-to-caret automático de Flutter solo garantiza que el cursor
  // quede visible, no todo el campo — con el teclado numérico tapando la
  // mitad de la pantalla eso deja el campo casi escondido. Forzamos que el
  // campo entero quede pegado justo arriba del teclado al enfocarlo.
  static void _scrollIntoViewOnFocus(FocusNode node) {
    if (!node.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      final ctx = node.context;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  double get monto => parseMoney(montoCtrl.text);
  double? get recibido =>
      metodo == 'Efectivo' && recibidoCtrl.text.trim().isNotEmpty
      ? parseMoney(recibidoCtrl.text)
      : null;
  double? get vuelto {
    final r = recibido;
    return r == null ? null : r - monto;
  }

  void dispose() {
    montoCtrl.dispose();
    recibidoCtrl.dispose();
    montoFocus.dispose();
    recibidoFocus.dispose();
  }
}

InputDecoration _compactDec({String hint = ''}) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.plusJakartaSans(
    fontSize: 13,
    color: AbakoColors.placeholder,
  ),
  isDense: true,
  filled: true,
  fillColor: AbakoColors.cream,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: AbakoColors.accentGreen, width: 1.5),
  ),
);

class _PagoLineRow extends StatelessWidget {
  const _PagoLineRow({required this.pago, required this.onQuitar});
  final _PagoLineState pago;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final vuelto = pago.vuelto;
    final vueltoInvalido = vuelto != null && vuelto < -0.005;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pago.metodo,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AbakoColors.textDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: onQuitar,
                icon: const Icon(Icons.close, size: 15),
                color: AbakoColors.textFaint,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  'Monto',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AbakoColors.textFaint,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: pago.montoCtrl,
                  focusNode: pago.montoFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [MoneyInputFormatter()],
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
                  decoration: _compactDec(
                    hint: '0',
                  ).copyWith(prefixText: '\$ '),
                ),
              ),
            ],
          ),
          if (pago.metodo == 'Efectivo') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    'Recibido',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AbakoColors.textFaint,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: pago.recibidoCtrl,
                    focusNode: pago.recibidoFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [MoneyInputFormatter()],
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5),
                    decoration: _compactDec(
                      hint: '0',
                    ).copyWith(prefixText: '\$ '),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                vuelto == null ? 'Vuelto: —' : 'Vuelto: ${_fmtMoney(vuelto)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: vueltoInvalido
                      ? Colors.red.shade700
                      : AbakoColors.accentGreenHover,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketLine extends StatelessWidget {
  const _TicketLine({
    required this.linea,
    required this.onAjustar,
    required this.onQuitar,
  });
  final _CartLine linea;
  final ValueChanged<double> onAjustar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final p = linea.producto;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorOf(p.nombre),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              monoOf(p.nombre),
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w700,
                fontSize: 13,
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
                  p.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbakoColors.textDark,
                  ),
                ),
                Text(
                  _fmtMoney(p.precio),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: AbakoColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          _stepBtn(Icons.remove, () => onAjustar(-1)),
          SizedBox(
            width: 26,
            child: Text(
              _fmtQty(linea.cantidad),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
          _stepBtn(Icons.add, () => onAjustar(1)),
          const SizedBox(width: 4),
          SizedBox(
            width: 56,
            child: Text(
              _fmtMoney(linea.importe),
              textAlign: TextAlign.right,
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AbakoColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: onQuitar,
            icon: const Icon(Icons.close, size: 15),
            color: AbakoColors.textFaint,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 26,
      height: 26,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: AbakoColors.cream,
          side: const BorderSide(color: AbakoColors.inputBorder, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 13, color: AbakoColors.textLabel),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selección de cliente (opcional) para la venta actual
// ---------------------------------------------------------------------------

Future<_ClienteOption?> _pickCliente(BuildContext context) {
  return showModalBottomSheet<_ClienteOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ClientePickerSheet(),
  );
}

class _ClientePickerSheet extends StatefulWidget {
  const _ClientePickerSheet();

  @override
  State<_ClientePickerSheet> createState() => _ClientePickerSheetState();
}

class _ClientePickerSheetState extends State<_ClientePickerSheet> {
  final _searchCtrl = TextEditingController();
  bool _creando = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearYSeleccionar(String nombre) async {
    setState(() => _creando = true);
    try {
      final id = _uuid.v4();
      await db.execute(
        'INSERT INTO clientes (id, nombre, creado_en) VALUES (?, ?, ?)',
        [id, nombre, DateTime.now().toIso8601String()],
      );
      if (mounted) Navigator.of(context).pop(_ClienteOption(id, nombre));
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Container(
        decoration: const BoxDecoration(
          color: AbakoColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Elegir cliente',
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre…',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: AbakoColors.placeholder,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 19,
                      color: AbakoColors.textFaint,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(
                        color: AbakoColors.inputBorder,
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(
                        color: AbakoColors.inputBorder,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(
                        color: AbakoColors.accentGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<ResultSet>(
                  stream: db.watch(
                    'SELECT id, nombre, telefono FROM clientes ORDER BY nombre',
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final texto = _searchCtrl.text.trim();
                    final q = texto.toLowerCase();
                    final clientes = snap.data!
                        .where(
                          (r) =>
                              q.isEmpty ||
                              (r['nombre'] as String).toLowerCase().contains(q),
                        )
                        .toList();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      children: [
                        for (final c in clientes)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorOf(c['nombre'] as String),
                              child: Text(
                                monoOf(c['nombre'] as String),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              c['nombre'] as String,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle:
                                (c['telefono'] as String?)?.isNotEmpty == true
                                ? Text(c['telefono'] as String)
                                : null,
                            onTap: () => Navigator.of(context).pop(
                              _ClienteOption(
                                c['id'] as String,
                                c['nombre'] as String,
                              ),
                            ),
                          ),
                        if (texto.isNotEmpty)
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.add)),
                            title: Text(
                              'Crear "$texto" como nuevo cliente',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            enabled: !_creando,
                            onTap: () => _crearYSeleccionar(texto),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
