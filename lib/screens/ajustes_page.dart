import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../db.dart';
import '../theme/abako_colors.dart';
import '../utils/app_snackbar.dart';
import '../utils/product_avatar.dart';

const _tabLabels = ['Perfil', 'Datos de la tienda', 'Usuarios', 'Notificaciones'];
const _tabIcons = [
  Icons.person_outline,
  Icons.storefront_outlined,
  Icons.group_outlined,
  Icons.notifications_outlined,
];

const _tiendaQuery = 'SELECT * FROM configuracion_tienda ORDER BY creado_en LIMIT 1';
const _perfilesQuery = 'SELECT id, email, nombre FROM perfiles ORDER BY creado_en';

String _fmtQty(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

class _ConfigTienda {
  _ConfigTienda({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.horarioApertura,
    required this.horarioCierre,
    required this.moneda,
    required this.notifBannerRevision,
    required this.notifStockMinimoDefault,
  });

  final String id;
  final String nombre;
  final String? direccion;
  final String? horarioApertura;
  final String? horarioCierre;
  final String moneda;
  final bool notifBannerRevision;
  final double notifStockMinimoDefault;

  static _ConfigTienda fromRow(dynamic row) => _ConfigTienda(
        id: row['id'] as String,
        nombre: row['nombre'] as String? ?? 'Tienda Centro',
        direccion: row['direccion'] as String?,
        horarioApertura: row['horario_apertura'] as String?,
        horarioCierre: row['horario_cierre'] as String?,
        moneda: (row['moneda'] as String?)?.isNotEmpty == true ? row['moneda'] as String : 'ARS',
        notifBannerRevision: _asBool(row['notif_banner_revision']),
        notifStockMinimoDefault: double.tryParse('${row['notif_stock_minimo_default']}') ?? 0,
      );
}

class _Perfil {
  _Perfil({required this.id, required this.email, required this.nombre});
  final String id;
  final String email;
  final String? nombre;

  static _Perfil fromRow(dynamic row) => _Perfil(
        id: row['id'] as String,
        email: row['email'] as String,
        nombre: row['nombre'] as String?,
      );
}

/// Devuelve el umbral de stock bajo por defecto (para prefillear "Stock
/// mínimo" al crear un producto nuevo en Inventario) — único punto de la app
/// fuera de esta pantalla que necesita leer `configuracion_tienda`.
Future<double> ajustesUmbralStockDefault() async {
  final rows = await db.getAll(
    'SELECT notif_stock_minimo_default FROM configuracion_tienda ORDER BY creado_en LIMIT 1',
  );
  if (rows.isEmpty) return 0;
  return double.tryParse('${rows.first['notif_stock_minimo_default']}') ?? 0;
}

class AjustesPage extends StatefulWidget {
  const AjustesPage({super.key});

  @override
  State<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends State<AjustesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return StreamBuilder<ResultSet>(
          stream: db.watch(_tiendaQuery),
          builder: (context, tiendaSnap) {
            if (!tiendaSnap.hasData || tiendaSnap.data!.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final tienda = _ConfigTienda.fromRow(tiendaSnap.data!.first);

            return StreamBuilder<ResultSet>(
              stream: db.watch(_perfilesQuery),
              builder: (context, perfilesSnap) {
                if (!perfilesSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final perfiles = perfilesSnap.data!.map(_Perfil.fromRow).toList();
                final user = sb.Supabase.instance.client.auth.currentUser;
                final miPerfil = perfiles.where((p) => p.id == user?.id).firstOrNull;

                final content = IndexedStack(
                  index: _tab,
                  children: [
                    _PerfilTab(
                      email: user?.email ?? '',
                      nombre: miPerfil?.nombre,
                      userId: user?.id,
                    ),
                    _TiendaTab(tienda: tienda),
                    _UsuariosTab(perfiles: perfiles, currentUserId: user?.id),
                    _NotificacionesTab(tienda: tienda),
                  ],
                );

                return isDesktop
                    ? _DesktopAjustes(tab: _tab, onTab: (i) => setState(() => _tab = i), content: content)
                    : _MobileAjustes(tab: _tab, onTab: (i) => setState(() => _tab = i), content: content);
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Layout: pestañas laterales (escritorio) / chips arriba (móvil)
// ---------------------------------------------------------------------------

class _DesktopAjustes extends StatelessWidget {
  const _DesktopAjustes({required this.tab, required this.onTab, required this.content});
  final int tab;
  final ValueChanged<int> onTab;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AbakoColors.cream,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 240,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ajustes',
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w600, fontSize: 22, color: AbakoColors.textDark)),
                const SizedBox(height: 22),
                for (var i = 0; i < _tabLabels.length; i++) _tile(i),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(int i) {
    final selected = i == tab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AbakoColors.statusOkBg : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onTab(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(_tabIcons[i], size: 19, color: selected ? AbakoColors.statusOkText : AbakoColors.textMuted),
                const SizedBox(width: 11),
                Text(_tabLabels[i],
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AbakoColors.statusOkText : AbakoColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAjustes extends StatelessWidget {
  const _MobileAjustes({required this.tab, required this.onTab, required this.content});
  final int tab;
  final ValueChanged<int> onTab;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AbakoColors.panelGreen,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 18),
          child: Text('Ajustes',
              style: GoogleFonts.bricolageGrotesque(
                  fontWeight: FontWeight.w600, fontSize: 21, color: AbakoColors.creamText)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _tabLabels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _TabChip(label: _tabLabels[i], selected: i == tab, onTap: () => onTab(i)),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            child: content,
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
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

// ---------------------------------------------------------------------------
// Compartidos entre pestañas
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEAE3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w600, fontSize: 18, color: AbakoColors.textDark)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(color: AbakoColors.placeholder),
      filled: true,
      fillColor: AbakoColors.cream,
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

Widget _saveButton(bool saving, VoidCallback onPressed) => Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(
        onPressed: saving ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AbakoColors.accentGreen,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: saving
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text('Guardar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );

// ---------------------------------------------------------------------------
// Perfil
// ---------------------------------------------------------------------------

class _PerfilTab extends StatefulWidget {
  const _PerfilTab({required this.email, required this.nombre, required this.userId});
  final String email;
  final String? nombre;
  final String? userId;

  @override
  State<_PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<_PerfilTab> {
  late final _nombreCtrl = TextEditingController(text: widget.nombre ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final userId = widget.userId;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await db.execute('UPDATE perfiles SET nombre = ? WHERE id = ?', [_nombreCtrl.text.trim(), userId]);
      if (mounted) {
        mostrarSnack(context, 'Perfil actualizado');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colorOf(widget.nombre?.isNotEmpty == true ? widget.nombre! : widget.email),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(monoOf(widget.nombre?.isNotEmpty == true ? widget.nombre! : widget.email),
                    style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text('El ícono se genera con las iniciales del nombre, igual que el resto de la app.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _label('Correo'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AbakoColors.creamOuter,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(widget.email,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AbakoColors.textLabel)),
          ),
          const SizedBox(height: 16),
          _label('Nombre'),
          TextField(controller: _nombreCtrl, decoration: _dec('Tu nombre')),
          const SizedBox(height: 20),
          _saveButton(_saving, _guardar),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Datos de la tienda
// ---------------------------------------------------------------------------

class _TiendaTab extends StatefulWidget {
  const _TiendaTab({required this.tienda});
  final _ConfigTienda tienda;

  @override
  State<_TiendaTab> createState() => _TiendaTabState();
}

class _TiendaTabState extends State<_TiendaTab> {
  late final _nombreCtrl = TextEditingController(text: widget.tienda.nombre);
  late final _direccionCtrl = TextEditingController(text: widget.tienda.direccion ?? '');
  late final _aperturaCtrl = TextEditingController(text: widget.tienda.horarioApertura ?? '');
  late final _cierreCtrl = TextEditingController(text: widget.tienda.horarioCierre ?? '');
  late final _monedaCtrl = TextEditingController(text: widget.tienda.moneda);
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _aperturaCtrl.dispose();
    _cierreCtrl.dispose();
    _monedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);
    try {
      await db.execute(
        '''UPDATE configuracion_tienda
           SET nombre=?, direccion=?, horario_apertura=?, horario_cierre=?, moneda=?
           WHERE id=?''',
        [
          _nombreCtrl.text.trim().isEmpty ? 'Tienda Centro' : _nombreCtrl.text.trim(),
          _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
          _aperturaCtrl.text.trim().isEmpty ? null : _aperturaCtrl.text.trim(),
          _cierreCtrl.text.trim().isEmpty ? null : _cierreCtrl.text.trim(),
          _monedaCtrl.text.trim().isEmpty ? 'ARS' : _monedaCtrl.text.trim(),
          widget.tienda.id,
        ],
      );
      if (mounted) {
        mostrarSnack(context, 'Datos de la tienda actualizados');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Datos de la tienda',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Nombre'),
          TextField(controller: _nombreCtrl, decoration: _dec('Tienda Centro')),
          const SizedBox(height: 16),
          _label('Dirección'),
          TextField(controller: _direccionCtrl, decoration: _dec('Opcional')),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Horario apertura'),
                    TextField(controller: _aperturaCtrl, decoration: _dec('09:00')),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Horario cierre'),
                    TextField(controller: _cierreCtrl, decoration: _dec('20:00')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Moneda'),
          SizedBox(width: 140, child: TextField(controller: _monedaCtrl, decoration: _dec('ARS'))),
          const SizedBox(height: 20),
          _saveButton(_saving, _guardar),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Usuarios
// ---------------------------------------------------------------------------

class _UsuariosTab extends StatelessWidget {
  const _UsuariosTab({required this.perfiles, required this.currentUserId});
  final List<_Perfil> perfiles;
  final String? currentUserId;

  Future<void> _invitar(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitar usuario'),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'correo@ejemplo.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()), child: const Text('Invitar')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !context.mounted) return;

    try {
      final res = await sb.Supabase.instance.client.functions.invoke('invite-user', body: {'email': email});
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (context.mounted) {
        mostrarSnack(context, 'Invitación enviada a $email');
      }
    } catch (e) {
      if (context.mounted) {
        mostrarSnack(context, 'No se pudo invitar: $e', kind: SnackKind.error);
      }
    }
  }

  Future<void> _eliminar(BuildContext context, _Perfil perfil) async {
    final nombre = (perfil.nombre?.isNotEmpty ?? false) ? perfil.nombre! : perfil.email;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar usuario?'),
        content: Text('$nombre va a perder el acceso a la app de inmediato. Esto no se puede deshacer.'),
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
    if (confirmar != true || !context.mounted) return;

    try {
      final res = await sb.Supabase.instance.client.functions.invoke('delete-user', body: {'userId': perfil.id});
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (context.mounted) {
        mostrarSnack(context, '$nombre eliminado');
      }
    } catch (e) {
      if (context.mounted) {
        mostrarSnack(context, 'No se pudo eliminar: $e', kind: SnackKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Usuarios',
      trailing: FilledButton.icon(
        onPressed: () => _invitar(context),
        style: FilledButton.styleFrom(
          backgroundColor: AbakoColors.accentGreen,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
        label: Text('Invitar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (perfiles.isEmpty)
            Text('Todavía no hay usuarios.', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AbakoColors.textFaint))
          else
            for (final p in perfiles)
              _UsuarioRow(
                perfil: p,
                // No dejamos borrar la propia cuenta (te quedarías afuera sin
                // querer) ni al último usuario que queda (nadie podría
                // volver a entrar a la app).
                puedeEliminar: p.id != currentUserId && perfiles.length > 1,
                onEliminar: () => _eliminar(context, p),
              ),
        ],
      ),
    );
  }
}

class _UsuarioRow extends StatelessWidget {
  const _UsuarioRow({required this.perfil, required this.puedeEliminar, required this.onEliminar});
  final _Perfil perfil;
  final bool puedeEliminar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final nombre = (perfil.nombre?.isNotEmpty ?? false) ? perfil.nombre! : perfil.email.split('@').first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colorOf(nombre), borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.center,
            child: Text(monoOf(nombre),
                style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nombre,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                Text(perfil.email, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AbakoColors.textFaint)),
              ],
            ),
          ),
          if (puedeEliminar)
            IconButton(
              onPressed: onEliminar,
              icon: const Icon(Icons.delete_outline, size: 19),
              color: AbakoColors.statusAgotadoText,
              tooltip: 'Eliminar usuario',
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notificaciones
// ---------------------------------------------------------------------------

class _NotificacionesTab extends StatefulWidget {
  const _NotificacionesTab({required this.tienda});
  final _ConfigTienda tienda;

  @override
  State<_NotificacionesTab> createState() => _NotificacionesTabState();
}

class _NotificacionesTabState extends State<_NotificacionesTab> {
  late bool _banner = widget.tienda.notifBannerRevision;
  late final _umbralCtrl = TextEditingController(text: _fmtQty(widget.tienda.notifStockMinimoDefault));
  bool _saving = false;

  @override
  void dispose() {
    _umbralCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleBanner(bool value) async {
    setState(() => _banner = value);
    await db.execute('UPDATE configuracion_tienda SET notif_banner_revision = ? WHERE id = ?', [value, widget.tienda.id]);
  }

  Future<void> _guardarUmbral() async {
    setState(() => _saving = true);
    try {
      final umbral = double.tryParse(_umbralCtrl.text.replaceAll(',', '.')) ?? 0;
      await db.execute(
        'UPDATE configuracion_tienda SET notif_stock_minimo_default = ? WHERE id = ?',
        [umbral, widget.tienda.id],
      );
      if (mounted) {
        mostrarSnack(context, 'Preferencias actualizadas');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Notificaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Alerta de venta pendiente de revisión',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AbakoColors.textDark)),
                    const SizedBox(height: 3),
                    Text('Muestra el banner en Inicio cuando hay ventas con sobregiro de stock.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
                  ],
                ),
              ),
              Switch(value: _banner, activeThumbColor: AbakoColors.accentGreen, onChanged: _toggleBanner),
            ],
          ),
          const SizedBox(height: 22),
          _label('Umbral de stock bajo por defecto'),
          Text('Se usa como valor inicial de "Stock mínimo" al crear un producto nuevo en Inventario.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: AbakoColors.textFaint)),
          const SizedBox(height: 8),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _umbralCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec('0'),
            ),
          ),
          const SizedBox(height: 20),
          _saveButton(_saving, _guardarUmbral),
        ],
      ),
    );
  }
}
