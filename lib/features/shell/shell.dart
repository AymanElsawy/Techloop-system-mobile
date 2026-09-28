import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../main.dart' show themeMode;
import '../customers/customer_list_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../documents/document_list_screen.dart';
import '../inventory/inventory_screen.dart';
import '../suppliers/supplier_list_screen.dart';
import '../treasury/treasury_screen.dart';
import '../users/user_list_screen.dart';
import '../visits/visit_list_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.screen, {this.managersOnly = false, this.repLabel});
  final String label;
  final IconData icon;
  final Widget Function(Session session) screen;
  final bool managersOnly;
  final String? repLabel;
}

/// Same tabs as the web sidebar.
final _tabs = [
  _Tab('الرئيسية', Icons.home_outlined, (s) => DashboardScreen(session: s)),
  _Tab('الزيارات', Icons.event_outlined, (_) => const VisitListScreen()),
  _Tab('العملاء', Icons.storefront_outlined, (_) => const CustomerListScreen()),
  _Tab('المخزن', Icons.inventory_2_outlined, (_) => const InventoryScreen()),
  _Tab('الموردين', Icons.local_shipping_outlined, (_) => const SupplierListScreen(), managersOnly: true),
  _Tab('الفواتير', Icons.receipt_long_outlined, (_) => const DocumentListScreen()),
  _Tab('الخزنة', Icons.account_balance_wallet_outlined, (_) => const TreasuryScreen(), repLabel: 'خزنتي'),
  _Tab('المستخدمون', Icons.group_outlined, (_) => const UserListScreen(), managersOnly: true),
];

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;
    final tabs = _tabs.where((t) => user.isManager || !t.managersOnly).toList();
    final tab = tabs[_index];

    return Scaffold(
      appBar: AppBar(title: Text(user.isManager ? tab.label : tab.repLabel ?? tab.label)),
      drawer: _Drawer(
        user: user,
        tabs: tabs,
        selected: _index,
        onSelect: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
        onLogout: widget.session.logout,
      ),
      // A key per tab so switching tabs starts each screen fresh.
      body: KeyedSubtree(key: ValueKey(_index), child: tab.screen(widget.session)),
    );
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.user,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onLogout,
  });

  final User user;
  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.7);
    // Light: white on the blue drawer; dark: the orange accent.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? Theme.of(context).colorScheme.primary : Colors.white;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              leading: CircleAvatar(
                backgroundColor: accent,
                foregroundColor: dark ? Colors.black : const Color(0xFF284B63),
                child: Text(user.name.characters.first),
              ),
              title: Text(
                user.name,
                style: const TextStyle(color: fg, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(user.roleLabel, style: TextStyle(color: dim)),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.15)),
            Expanded(
              child: ListView.builder(
                itemCount: tabs.length,
                itemBuilder: (context, i) {
                  final active = i == selected;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      selected: active,
                      selectedTileColor: Colors.white.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      leading: Icon(tabs[i].icon, color: active ? accent : dim),
                      title: Text(
                        user.isManager ? tabs[i].label : tabs[i].repLabel ?? tabs[i].label,
                        style: TextStyle(
                          color: active ? fg : dim,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      onTap: () => onSelect(i),
                    ),
                  );
                },
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.15)),
            ValueListenableBuilder(
              valueListenable: themeMode,
              builder: (context, mode, _) {
                final dark =
                    mode == ThemeMode.dark ||
                    (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
                return ListTile(
                  leading: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: dim),
                  title: Text(dark ? 'الوضع الفاتح' : 'الوضع الداكن', style: TextStyle(color: dim)),
                  onTap: () => themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: dim),
              title: Text('تسجيل الخروج', style: TextStyle(color: dim)),
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}
