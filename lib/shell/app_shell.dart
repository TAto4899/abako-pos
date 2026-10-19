import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqlite3/common.dart' hide Row;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../db.dart';
import '../screens/ajustes_page.dart';
import '../screens/caja_page.dart';
import '../screens/clientes_page.dart';
import '../screens/inicio_page.dart';
import '../screens/inventario_page.dart';
import '../screens/reportes_page.dart';
import '../screens/venta_page.dart';
import '../theme/abako_colors.dart';
import '../widgets/abako_logo.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.iconFilled, this.builder);
  final String label;
  final IconData icon;
  final IconData iconFilled;
  final WidgetBuilder builder;
}

final _navItems = <_NavItem>[
  _NavItem('Inicio', Icons.home_outlined, Icons.home,
      (_) => const InicioPage()),
  _NavItem('Punto de venta', Icons.shopping_bag_outlined, Icons.shopping_bag,
      (_) => const VentaPage()),
  _NavItem('Caja', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet,
      (_) => const CajaPage()),
  _NavItem('Inventario', Icons.inventory_2_outlined, Icons.inventory_2,
      (_) => const InventarioPage()),
  _NavItem('Reportes', Icons.bar_chart_outlined, Icons.bar_chart,
      (_) => const ReportesPage()),
  _NavItem('Clientes', Icons.people_alt_outlined, Icons.people_alt,
      (_) => const ClientesPage()),
  _NavItem('Ajustes', Icons.settings_outlined, Icons.settings,
      (_) => const AjustesPage()),
];

/// Shell de navegación persistente del diseño Abako: sidebar en escritorio,
/// barra inferior en móvil.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: AbakoColors.creamOuter,
          body: isDesktop
              ? Row(
                  children: [
                    _Sidebar(index: _index, onSelect: (i) => setState(() => _index = i)),
                    Expanded(child: _navItems[_index].builder(context)),
                  ],
                )
              : _navItems[_index].builder(context),
          bottomNavigationBar: isDesktop
              ? null
              : _BottomNav(index: _index, onSelect: (i) => setState(() => _index = i)),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = sb.Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final initials =
        email.isNotEmpty ? email.substring(0, 1).toUpperCase() : '?';

    return Container(
      width: 236,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 0, 0),
            child: AbakoLogo(dark: false, size: 34),
          ),
          const SizedBox(height: 30),
          for (var i = 0; i < _navItems.length; i++) _navTile(i),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => _showAccountMenu(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AbakoColors.creamOuter.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AbakoColors.panelGreen,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AbakoColors.textDark,
                          ),
                        ),
                        StreamBuilder<ResultSet>(
                          stream: db.watch(
                              'SELECT nombre FROM configuracion_tienda ORDER BY creado_en LIMIT 1'),
                          builder: (context, snap) {
                            final nombre = (snap.hasData && snap.data!.isNotEmpty)
                                ? snap.data!.first['nombre'] as String? ?? 'Tienda Centro'
                                : 'Tienda Centro';
                            return Text(
                              nombre,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AbakoColors.textFaint,
                              ),
                            );
                          },
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
    );
  }

  void _showAccountMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + 20,
        offset.dy + box.size.height - 70,
        offset.dx + box.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem(
          onTap: () => sb.Supabase.instance.client.auth.signOut(),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }

  Widget _navTile(int i) {
    final item = _navItems[i];
    final selected = i == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AbakoColors.statusOkBg : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onSelect(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? item.iconFilled : item.icon,
                  size: 21,
                  color: selected ? AbakoColors.statusOkText : AbakoColors.textMuted,
                ),
                const SizedBox(width: 13),
                Text(
                  item.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AbakoColors.statusOkText : AbakoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// En mobile solo entran 4 ítems directos + "Más" (7 no entraban cómodos en
// pantallas angostas — ver sesión 2026-09-02, "Inventario" se cortaba en 2
// líneas). El sidebar de escritorio no se tocó: ahí sí entran los 7 sueltos.
const _navDirectos = [0, 1, 2, 3]; // Inicio, Punto de venta, Caja, Inventario
const _navAgrupados = [4, 5, 6]; // Reportes, Clientes, Ajustes → sheet "Más"

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final masSeleccionado = _navAgrupados.contains(index);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AbakoColors.inputBorder)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        child: Row(
          children: [
            for (final i in _navDirectos)
              Expanded(
                child: _BottomNavTile(
                  icon: i == index ? _navItems[i].iconFilled : _navItems[i].icon,
                  label: _navItems[i].label == 'Punto de venta' ? 'Vender' : _navItems[i].label,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
            Expanded(
              child: _BottomNavTile(
                icon: Icons.more_horiz,
                label: 'Más',
                selected: masSeleccionado,
                onTap: () => _abrirMas(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirMas(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AbakoColors.inputBorder, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 8),
              for (final i in _navAgrupados)
                ListTile(
                  leading: Icon(i == index ? _navItems[i].iconFilled : _navItems[i].icon, color: AbakoColors.textDark),
                  title: Text(_navItems[i].label,
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15, color: AbakoColors.textDark)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSelect(i);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AbakoColors.statusAgotadoText),
                title: Text('Cerrar sesión',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 15, color: AbakoColors.statusAgotadoText)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  sb.Supabase.instance.client.auth.signOut();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AbakoColors.accentGreen : AbakoColors.textFaint;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}
