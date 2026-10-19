import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/session.dart';
import '../../main.dart' show themeMode;
import '../audit_log/audit_log_screen.dart';
import '../customers/customer_list_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../documents/company_form_screen.dart';
import '../documents/document_list_screen.dart';
import '../inventory/inventory_screen.dart';
import '../notifications/notification_list_screen.dart';
import '../reports/reports_screen.dart';
import '../suppliers/supplier_list_screen.dart';
import '../treasury/treasury_screen.dart';
import '../users/targets_screen.dart';
import '../users/user_list_screen.dart';
import '../visits/visit_list_screen.dart';

class _Tab {
  const _Tab(
    this.label,
    this.icon,
    this.screen, {
    this.managersOnly = false,
    this.ownerOnly = false,
    this.repLabel,
    this.hiddenForWarehouseRep = false,
    this.showsUnread = false,
  });
  final String label;
  final IconData icon;
  final Widget Function(Session session) screen;
  final bool managersOnly;
  final bool ownerOnly;
  final String? repLabel;
  final bool hiddenForWarehouseRep;

  /// Unread-notifications badge on the icon.
  final bool showsUnread;

  bool visibleTo(User user) =>
      (user.isManager || !managersOnly) &&
      (user.role == UserRole.owner || !ownerOnly) &&
      (user.role != UserRole.warehouseRep || !hiddenForWarehouseRep);
}

/// Same tabs as the web sidebar. Warehouse reps only get المخزن and الإشعارات.
final _tabs = [
  _Tab(
    'الرئيسية',
    Icons.home_outlined,
    (s) => DashboardScreen(session: s),
    hiddenForWarehouseRep: true,
  ),
  _Tab(
    'الزيارات',
    Icons.event_outlined,
    (_) => const VisitListScreen(),
    hiddenForWarehouseRep: true,
  ),
  _Tab(
    'العملاء',
    Icons.storefront_outlined,
    (_) => const CustomerListScreen(),
    hiddenForWarehouseRep: true,
  ),
  _Tab('المخزن', Icons.inventory_2_outlined, (_) => const InventoryScreen()),
  _Tab(
    'الموردين',
    Icons.local_shipping_outlined,
    (_) => const SupplierListScreen(),
    managersOnly: true,
  ),
  _Tab(
    'الفواتير',
    Icons.receipt_long_outlined,
    (_) => const DocumentListScreen(),
    managersOnly: true,
  ),
  _Tab(
    'الخزنة',
    Icons.account_balance_wallet_outlined,
    (_) => const TreasuryScreen(),
    repLabel: 'خزنتي',
    hiddenForWarehouseRep: true,
  ),
  _Tab(
    'الإشعارات',
    Icons.notifications_outlined,
    (_) => const NotificationListScreen(),
    showsUnread: true,
  ),
  _Tab(
    'التارجت',
    Icons.track_changes_outlined,
    (_) => const TargetsScreen(),
    managersOnly: true,
  ),
  _Tab(
    'التقارير',
    Icons.insert_chart_outlined,
    (_) => const ReportsScreen(),
    managersOnly: true,
  ),
  _Tab(
    'المستخدمون',
    Icons.group_outlined,
    (_) => const UserListScreen(),
    managersOnly: true,
  ),
  _Tab(
    'بيانات الشركة',
    Icons.business_outlined,
    (_) => const CompanyFormScreen(),
    managersOnly: true,
  ),
  _Tab('السجل', Icons.history, (_) => const AuditLogScreen(), ownerOnly: true),
];

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session});

  final Session session;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ponytail: polling, no push; the badge can lag up to a minute while the app is open.
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _refreshUnread());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshUnread());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnread();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A failed poll keeps the last count. Also sends what was saved offline.
  Future<void> _refreshUnread() async {
    context.app.session.api.syncQueue();
    try {
      unreadNotifications.value = await context.app.notifications.unreadCount();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;
    final tabs = _tabs.where((t) => t.visibleTo(user)).toList();
    final tab = tabs[_index];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset(
          'assets/icon/logo-tech.png',
          height: 40,
          semanticLabel: 'Techloop',
        ),
        leading: ValueListenableBuilder(
          valueListenable: themeMode,
          builder: (context, mode, _) {
            final dark =
                mode == ThemeMode.dark ||
                (mode == ThemeMode.system &&
                    MediaQuery.platformBrightnessOf(context) ==
                        Brightness.dark);
            return IconButton(
              icon: Icon(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              tooltip: dark ? 'الوضع الفاتح' : 'الوضع الداكن',
              onPressed: () =>
                  themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: widget.session.logout,
          ),
        ],
      ),
      // A key per tab so switching tabs starts each screen fresh.
      body: KeyedSubtree(
        key: ValueKey(_index),
        child: tab.screen(widget.session),
      ),
      bottomNavigationBar: _TabBar(
        user: user,
        tabs: tabs,
        selected: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// All tabs in one horizontally scrollable row, instead of a burger-menu drawer.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.user,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final User user;
  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: tabs.length,
            itemBuilder: (context, i) {
              final active = i == selected;
              final fg = active
                  ? colors.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant;
              return InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 76,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: active
                        ? colors.primary.withValues(alpha: 0.12)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      tabs[i].showsUnread
                          ? ValueListenableBuilder(
                              valueListenable: unreadNotifications,
                              builder: (context, count, icon) => Badge(
                                isLabelVisible: count > 0,
                                label: Text('$count'),
                                child: icon,
                              ),
                              child: Icon(tabs[i].icon, color: fg),
                            )
                          : Icon(tabs[i].icon, color: fg),
                      const SizedBox(height: 4),
                      Text(
                        user.isManager
                            ? tabs[i].label
                            : tabs[i].repLabel ?? tabs[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
