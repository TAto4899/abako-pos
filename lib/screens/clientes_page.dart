import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:uuid/uuid.dart';

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/product_avatar.dart';
import 'venta_detalle_page.dart';

const _uuid = Uuid();

// Un cliente se considera "frecuente" a partir de 3 compras — umbral fijo y
// arbitrario (no hay pedido de negocio que defina otro número), documentado
// acá por si hace falta ajustarlo más adelante.
const _umbralFrecuente = 3;

const _clientesQuery = 'SELECT id, nombre, telefono, email, notas, creado_en FROM clientes ORDER BY nombre';
const _ventasQuery = 'SELECT id, cliente_id, total, creado_en FROM ventas';

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

String _fmtFecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtFechaHora(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Cliente {
  _Cliente({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.email,
    required this.notas,
    required this.creadoEn,
  });

  final String id;
  final String nombre;
  final String? telefono;
  final String? email;
  final String? notas;
  final DateTime creadoEn;

  static _Cliente fromRow(dynamic row) => _Cliente(
        id: row['id'] as String,
        nombre: row['nombre'] as String,
        telefono: row['telefono'] as String?,
        email: row['email'] as String?,
        notas: row['notas'] as String?,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

class _VentaCliente {
  _VentaCliente({required this.clienteId, required this.total, required this.creadoEn});
  final String? clienteId;
  final double total;
  final DateTime creadoEn;

  static _VentaCliente fromRow(dynamic row) => _VentaCliente(
        clienteId: row['cliente_id'] as String?,
        total: double.tryParse('${row['total']}') ?? 0,
        creadoEn: DateTime.parse(row['creado_en'] as String),
      );
}

class _ClienteStats {
  const _ClienteStats({required this.compras, required this.gastoTotal, required this.ultimaVisita});
  final int compras;
  final double gastoTotal;
  final DateTime? ultimaVisita;

  double get gastoPromedio => compras == 0 ? 0 : gastoTotal / compras;
}

Map<String, _ClienteStats> _computeStats(List<_VentaCliente> ventas) {
  final porCliente = <String, List<_VentaCliente>>{};
  for (final v in ventas) {
    final cid = v.clienteId;
    if (cid == null) continue;
    (porCliente[cid] ??= []).add(v);
  }
  return {
    for (final entry in porCliente.entries)
      entry.key: _ClienteStats(
        compras: entry.value.length,
        gastoTotal: entry.value.fold(0.0, (t, v) => t + v.total),
        ultimaVisita: entry.value.map((v) => v.creadoEn).reduce((a, b) => a.isAfter(b) ? a : b),
      ),
  };
}

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  String _segmento = 'todos';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _abrirNuevo(bool isDesktop) {
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: SizedBox(width: 480, child: _ClienteForm(rounded: false)),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // context propio del builder, no el de _abrirNuevo — mismo fix que
        // en inventario_page.dart (2026-09-04): con el context de afuera
        // este Padding nunca se recalcula cuando aparece el teclado.
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: const FractionallySizedBox(heightFactor: 0.85, child: _ClienteForm(rounded: true)),
        ),
      );
    }
  }

  void _abrirDetalle(_Cliente cliente) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClienteDetallePage(clienteId: cliente.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(_clientesQuery),
          builder: (context, clientesSnap) {
            if (!clientesSnap.hasData) return const Center(child: CircularProgressIndicator());
            return StreamBuilder<ResultSet>(
              stream: db.watch(_ventasQuery),
              builder: (context, ventasSnap) {
                if (!ventasSnap.hasData) return const Center(child: CircularProgressIndicator());

                final clientes = clientesSnap.data!.map(_Cliente.fromRow).toList();
                final ventas = ventasSnap.data!.map(_VentaCliente.fromRow).toList();
                final stats = _computeStats(ventas);
                final ahora = DateTime.now();

                bool esNuevo(_Cliente c) =>
                    c.creadoEn.year == ahora.year && c.creadoEn.month == ahora.month;
                bool esFrecuente(_Cliente c) => (stats[c.id]?.compras ?? 0) >= _umbralFrecuente;

                final frecuentesCount = clientes.where(esFrecuente).length;
                final nuevosCount = clientes.where(esNuevo).length;

                final q = _searchController.text.trim().toLowerCase();
                final filtrados = clientes.where((c) {
                  final matchesSegmento = switch (_segmento) {
                    'frecuentes' => esFrecuente(c),
                    'nuevos' => esNuevo(c),
                    _ => true,
                  };
                  final matchesQuery = q.isEmpty ||
                      c.nombre.toLowerCase().contains(q) ||
                      (c.telefono?.toLowerCase().contains(q) ?? false);
                  return matchesSegmento && matchesQuery;
                }).toList()
                  ..sort((a, b) {
                    final va = stats[a.id]?.ultimaVisita;
                    final vb = stats[b.id]?.ultimaVisita;
                    if (va == null && vb == null) return a.nombre.compareTo(b.nombre);
                    if (va == null) return 1;
                    if (vb == null) return -1;
                    return vb.compareTo(va);
                  });

                return _Layout(
                  isDesktop: isDesktop,
                  clientes: filtrados,
                  totalCount: clientes.length,
                  frecuentesCount: frecuentesCount,
                  nuevosCount: nuevosCount,
                  segmento: _segmento,
                  stats: stats,
                  searchController: _searchController,
                  onSegmento: (s) => setState(() => _segmento = s),
                  onNuevo: () => _abrirNuevo(isDesktop),
                  onTapCliente: _abrirDetalle,
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
// Layout único (tarjetas), responsive
// ---------------------------------------------------------------------------

class _Layout extends StatelessWidget {
  const _Layout({
    required this.isDesktop,
    required this.clientes,
    required this.totalCount,
    required this.frecuentesCount,
    required this.nuevosCount,
    required this.segmento,
    required this.stats,
    required this.searchController,
    required this.onSegmento,
    required this.onNuevo,
    required this.onTapCliente,
  });

  final bool isDesktop;
  final List<_Cliente> clientes;
  final int totalCount;
  final int frecuentesCount;
  final int nuevosCount;
  final String segmento;
  final Map<String, _ClienteStats> stats;
  final TextEditingController searchController;
  final ValueChanged<String> onSegmento;
  final VoidCallback onNuevo;
  final ValueChanged<_Cliente> onTapCliente;

  @override
  Widget build(BuildContext context) {
    final pad = isDesktop ? 32.0 : 16.0;
    return Stack(
      children: [
        ColoredBox(
          color: isDesktop ? AbakoColors.cream : AbakoColors.creamOuter,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, isDesktop ? 28 : 18, pad, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clientes',
                                style: GoogleFonts.bricolageGrotesque(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isDesktop ? 27 : 21,
                                    color: isDesktop ? AbakoColors.textDark : AbakoColors.textDark)),
                            const SizedBox(height: 3),
                            Text('$totalCount clientes',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint)),
                          ],
                        ),
                      ),
                      if (isDesktop)
                        FilledButton.icon(
                          onPressed: onNuevo,
                          style: FilledButton.styleFrom(
                            backgroundColor: AbakoColors.accentGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('Nuevo cliente', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 18, pad, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentoCard(
                          label: 'Frecuentes',
                          value: '$frecuentesCount',
                          dotColor: AbakoColors.statusOkText,
                          selected: segmento == 'frecuentes',
                          onTap: () => onSegmento(segmento == 'frecuentes' ? 'todos' : 'frecuentes'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SegmentoCard(
                          label: 'Nuevos este mes',
                          value: '$nuevosCount',
                          dotColor: AbakoColors.statusBajoDot,
                          selected: segmento == 'nuevos',
                          onTap: () => onSegmento(segmento == 'nuevos' ? 'todos' : 'nuevos'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SegmentoCard(
                          label: 'Total',
                          value: '$totalCount',
                          selected: segmento == 'todos',
                          onTap: () => onSegmento('todos'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 16, pad, 4),
                  child: TextField(
                    controller: searchController,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AbakoColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o teléfono…',
                      hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
                      prefixIcon: const Icon(Icons.search, size: 19, color: AbakoColors.textFaint),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: const BorderSide(color: AbakoColors.inputBorder, width: 1.5)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: const BorderSide(color: AbakoColors.accentGreen, width: 1.5)),
                    ),
                  ),
                ),
                Expanded(
                  child: clientes.isEmpty
                      ? Center(
                          child: Text('No se encontraron clientes.',
                              style: GoogleFonts.plusJakartaSans(color: AbakoColors.textFaint, fontSize: 14)))
                      : isDesktop
                          // Wrap en vez de GridView: cada tarjeta se dimensiona
                          // sola según su contenido (badges opcionales incluidos)
                          // en vez de forzar una altura fija que puede no
                          // alcanzar y producir overflow.
                          ? SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 28),
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: [
                                  for (final c in clientes)
                                    SizedBox(
                                      width: 300,
                                      child: _ClienteCard(
                                        cliente: c,
                                        stats: stats[c.id],
                                        esNuevo: c.creadoEn.year == DateTime.now().year &&
                                            c.creadoEn.month == DateTime.now().month,
                                        esFrecuente: (stats[c.id]?.compras ?? 0) >= _umbralFrecuente,
                                        onTap: () => onTapCliente(c),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                              itemCount: clientes.length,
                              itemBuilder: (context, i) {
                                final c = clientes[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ClienteCard(
                                    cliente: c,
                                    stats: stats[c.id],
                                    esNuevo: c.creadoEn.year == DateTime.now().year &&
                                        c.creadoEn.month == DateTime.now().month,
                                    esFrecuente: (stats[c.id]?.compras ?? 0) >= _umbralFrecuente,
                                    onTap: () => onTapCliente(c),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
        if (!isDesktop)
          Positioned(
            right: 18,
            bottom: 18,
            child: FloatingActionButton(
              backgroundColor: AbakoColors.accentGreen,
              onPressed: onNuevo,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}

class _SegmentoCard extends StatelessWidget {
  const _SegmentoCard({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final String value;
  final bool selected;
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AbakoColors.accentGreen : const Color(0xFFECEAE3), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(value,
                      style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700, fontSize: 22, color: AbakoColors.textDark)),
                  if (dotColor != null) ...[
                    const SizedBox(width: 8),
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
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

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    required this.cliente,
    required this.stats,
    required this.esNuevo,
    required this.esFrecuente,
    required this.onTap,
  });

  final _Cliente cliente;
  final _ClienteStats? stats;
  final bool esNuevo;
  final bool esFrecuente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFECEAE3)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: colorOf(cliente.nombre), borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: Text(monoOf(cliente.nombre),
                        style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cliente.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AbakoColors.textDark)),
                        Text(cliente.telefono?.isNotEmpty == true ? cliente.telefono! : 'Sin teléfono',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (esFrecuente || esNuevo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (esFrecuente) _badge('Frecuente', AbakoColors.statusOkBg, AbakoColors.statusOkText),
                      if (esNuevo) _badge('Nuevo', AbakoColors.statusBajoBg, AbakoColors.statusBajoText),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compras',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AbakoColors.textFaint)),
                        Text('${s?.compras ?? 0}',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: AbakoColors.textDark)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Última visita',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AbakoColors.textFaint)),
                        Text(s?.ultimaVisita != null ? _fmtFecha(s!.ultimaVisita!) : '—',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: AbakoColors.textDark)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Gasto total',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AbakoColors.textFaint)),
                      Text(_fmtMoney(s?.gastoTotal ?? 0),
                          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 14, color: AbakoColors.textDark)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

// ---------------------------------------------------------------------------
// Alta / edición
// ---------------------------------------------------------------------------

class _ClienteForm extends StatefulWidget {
  const _ClienteForm({required this.rounded, this.cliente});
  final bool rounded;
  final _Cliente? cliente;

  @override
  State<_ClienteForm> createState() => _ClienteFormState();
}

class _ClienteFormState extends State<_ClienteForm> {
  late final _nombreCtrl = TextEditingController(text: widget.cliente?.nombre ?? '');
  late final _telefonoCtrl = TextEditingController(text: widget.cliente?.telefono ?? '');
  late final _emailCtrl = TextEditingController(text: widget.cliente?.email ?? '');
  late final _notasCtrl = TextEditingController(text: widget.cliente?.notas ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
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
      final telefono = _telefonoCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final notas = _notasCtrl.text.trim();
      if (widget.cliente == null) {
        await db.execute(
          'INSERT INTO clientes (id, nombre, telefono, email, notas, creado_en) VALUES (?, ?, ?, ?, ?, ?)',
          [
            _uuid.v4(),
            nombre,
            telefono.isEmpty ? null : telefono,
            email.isEmpty ? null : email,
            notas.isEmpty ? null : notas,
            DateTime.now().toIso8601String(),
          ],
        );
      } else {
        await db.execute(
          'UPDATE clientes SET nombre=?, telefono=?, email=?, notas=? WHERE id=?',
          [
            nombre,
            telefono.isEmpty ? null : telefono,
            email.isEmpty ? null : email,
            notas.isEmpty ? null : notas,
            widget.cliente!.id,
          ],
        );
      }
      if (mounted) {
        mostrarSnack(context, widget.cliente == null ? 'Cliente agregado' : 'Cliente actualizado');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AbakoColors.cream,
        borderRadius: widget.rounded ? const BorderRadius.vertical(top: Radius.circular(24)) : BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente',
                      style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 19, color: AbakoColors.textDark)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 19),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1EFE8)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1EFE8)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Nombre'),
                  TextField(controller: _nombreCtrl, decoration: _dec('Ej. María Gómez')),
                  const SizedBox(height: 16),
                  _label('Teléfono'),
                  TextField(controller: _telefonoCtrl, keyboardType: TextInputType.phone, decoration: _dec('Opcional')),
                  const SizedBox(height: 16),
                  _label('Correo'),
                  TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _dec('Opcional')),
                  const SizedBox(height: 16),
                  _label('Notas'),
                  TextField(controller: _notasCtrl, maxLines: 3, decoration: _dec('Opcional')),
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
                        : Text(widget.cliente == null ? 'Agregar cliente' : 'Guardar cambios',
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
}

// ---------------------------------------------------------------------------
// Detalle de cliente
// ---------------------------------------------------------------------------

class ClienteDetallePage extends StatelessWidget {
  const ClienteDetallePage({super.key, required this.clienteId});
  final String clienteId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbakoColors.creamOuter,
      appBar: AppBar(
        backgroundColor: AbakoColors.panelGreen,
        foregroundColor: AbakoColors.creamText,
        elevation: 0,
        title: Text('Detalle de cliente',
            style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.creamText)),
        actions: [
          StreamBuilder<ResultSet>(
            stream: db.watch('SELECT * FROM clientes WHERE id = ?', parameters: [clienteId]),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
              final cliente = _Cliente.fromRow(snap.data!.first);
              return IconButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(child: SizedBox(width: 480, child: _ClienteForm(rounded: false, cliente: cliente))),
                ),
                icon: const Icon(Icons.edit_outlined),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<ResultSet>(
        stream: db.watch('SELECT * FROM clientes WHERE id = ?', parameters: [clienteId]),
        builder: (context, clienteSnap) {
          if (!clienteSnap.hasData) return const Center(child: CircularProgressIndicator());
          if (clienteSnap.data!.isEmpty) {
            return Center(
                child: Text('Este cliente ya no existe.', style: GoogleFonts.plusJakartaSans(color: AbakoColors.textFaint)));
          }
          final cliente = _Cliente.fromRow(clienteSnap.data!.first);

          return StreamBuilder<ResultSet>(
            stream: db.watch('SELECT id, total, creado_en FROM ventas WHERE cliente_id = ? ORDER BY creado_en DESC',
                parameters: [clienteId]),
            builder: (context, ventasSnap) {
              if (!ventasSnap.hasData) return const Center(child: CircularProgressIndicator());
              final ventas = ventasSnap.data!
                  .map((r) => _VentaCliente.fromRow({'cliente_id': clienteId, 'total': r['total'], 'creado_en': r['creado_en']}))
                  .toList();
              final compras = ventas.length;
              final gastoTotal = ventas.fold(0.0, (t, v) => t + v.total);
              final gastoPromedio = compras == 0 ? 0.0 : gastoTotal / compras;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Card(
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(color: colorOf(cliente.nombre), borderRadius: BorderRadius.circular(14)),
                            alignment: Alignment.center,
                            child: Text(monoOf(cliente.nombre),
                                style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(cliente.nombre,
                                    style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 17, color: AbakoColors.textDark)),
                                if (cliente.telefono?.isNotEmpty == true)
                                  Text(cliente.telefono!, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint)),
                                if (cliente.email?.isNotEmpty == true)
                                  Text(cliente.email!, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (cliente.notas?.isNotEmpty == true) ...[
                      const SizedBox(height: 14),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Notas', style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AbakoColors.textFaint)),
                            const SizedBox(height: 6),
                            Text(cliente.notas!, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AbakoColors.textLabel)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _StatCard(label: 'Compras', value: '$compras')),
                        const SizedBox(width: 12),
                        Expanded(child: _StatCard(label: 'Gasto total', value: _fmtMoney(gastoTotal))),
                        const SizedBox(width: 12),
                        Expanded(child: _StatCard(label: 'Gasto promedio', value: _fmtMoney(gastoPromedio))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Historial de compras',
                              style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 15, color: AbakoColors.textDark)),
                          const SizedBox(height: 12),
                          if (ventasSnap.data!.isEmpty)
                            Text('Todavía no hay compras registradas.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
                          else
                            for (final row in ventasSnap.data!)
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => VentaDetallePage(ventaId: row['id'] as String)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(_fmtFechaHora(DateTime.parse(row['creado_en'] as String)),
                                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textLabel)),
                                      ),
                                      Text(_fmtMoney(double.tryParse('${row['total']}') ?? 0),
                                          style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 14, color: AbakoColors.textDark)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, size: 16, color: AbakoColors.textFaint),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: AbakoColors.textFaint)),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 17, color: AbakoColors.textDark)),
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
