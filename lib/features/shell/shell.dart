import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/session.dart';
import '../../main.dart' show themeMode;
import '../../widgets/async_view.dart' show ReloadSignal;
import '../../widgets/form.dart' show confirm;
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
    this.isNotifications = false,
    this.mainFor = const {},
  });
  final String label;
  final IconData icon;
  final Widget Function(Session session) screen;
  final bool managersOnly;
  final bool ownerOnly;
  final String? repLabel;
  final bool hiddenForWarehouseRep;

  /// Opened from the bell in the app bar, not from the bottom bar.
  final bool isNotifications;

  /// Roles that get this tab in the bottom bar; the rest go under "المزيد".
  final Set<UserRole> mainFor;

  bool visibleTo(User user) =>
      (user.isManager || !managersOnly) &&
      (user.role == UserRole.owner || !ownerOnly) &&
      (user.role != UserRole.warehouseRep || !hiddenForWarehouseRep);

  String labelFor(User user) => user.isManager ? label : repLabel ?? label;
}

const _managers = {UserRole.owner, UserRole.admin};

/// Same tabs as the web sidebar. Warehouse reps only get المخزن and الإشعارات.
final _tabs = [
  _Tab(
    'الرئيسية',
    Icons.home_outlined,
    (s) => DashboardScreen(session: s),
    hiddenForWarehouseRep: true,
    mainFor: {..._managers, UserRole.salesRep},
  ),
  _Tab(
    'الزيارات',
    Icons.event_outlined,
    (_) => const VisitListScreen(),
    hiddenForWarehouseRep: true,
    mainFor: {UserRole.salesRep},
  ),
  _Tab(
    'العملاء',
    Icons.storefront_outlined,
    (_) => const CustomerListScreen(),
    hiddenForWarehouseRep: true,
    mainFor: {..._managers, UserRole.salesRep},
  ),
  _Tab(
    'المخزن',
    Icons.inventory_2_outlined,
    (_) => const InventoryScreen(),
    mainFor: {..._managers, UserRole.warehouseRep},
  ),
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
    mainFor: _managers,
  ),
  _Tab(
    'الخزنة',
    Icons.account_balance_wallet_outlined,
    (_) => const TreasuryScreen(),
    repLabel: 'خزنتي',
    hiddenForWarehouseRep: true,
    mainFor: {UserRole.salesRep},
  ),
  _Tab(
    'الإشعارات',
    Icons.notifications_outlined,
    (_) => const NotificationListScreen(),
    isNotifications: true,
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

  /// One per tab opened so far: those tabs stay alive and reload in place when shown again.
  final _signals = <int, ValueNotifier<int>>{};

  void _select(int i) {
    final opened = _signals[i];
    if (i != _index) {
      HapticFeedback.selectionClick();
      setState(() => _index = i);
    }
    opened?.value++;
  }

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
    for (final s in _signals.values) {
      s.dispose();
    }
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

  Future<void> _openMore(User user, List<_Tab> tabs) async {
    final picked = await showModalBottomSheet<_Tab>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        user: user,
        tabs: [
          for (final t in tabs)
            if (!t.mainFor.contains(user.role) && !t.isNotifications) t,
        ],
        onLogout: widget.session.logout,
      ),
    );
    if (picked != null) _select(tabs.indexOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;
    final tabs = _tabs.where((t) => t.visibleTo(user)).toList();
    final tab = tabs[_index];
    final main = [
      for (final t in tabs)
        if (t.mainFor.contains(user.role)) t,
    ];
    final mainIndex = main.indexOf(tab);
    final notifications = tabs.indexWhere((t) => t.isNotifications);
    final home = identical(tab, _tabs.first);

    return Scaffold(
      appBar: AppBar(
        // The home tab shows the company logo in the middle; other tabs their name.
        centerTitle: home,
        title: home
            ? Image.asset(
                'assets/icon/logo-tech.png',
                height: 36,
                semanticLabel: 'Techloop',
              )
            : Text(tab.labelFor(user)),
        actions: [
          if (notifications >= 0)
            IconButton(
              tooltip: 'الإشعارات',
              onPressed: () => _select(notifications),
              icon: ValueListenableBuilder(
                valueListenable: unreadNotifications,
                builder: (context, count, icon) => Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: icon,
                ),
                child: Icon(
                  _index == notifications
                      ? Icons.notifications
                      : Icons.notifications_outlined,
                ),
              ),
            ),
        ],
      ),
      // Tabs are built on first open and kept, so switching back is instant (filters and scroll stay).
      body: IndexedStack(
        index: _index,
        sizing: StackFit.expand,
        children: [
          for (var i = 0; i < tabs.length; i++)
            if (i == _index || _signals.containsKey(i))
              HeroMode(
                // Hidden tabs' FABs would clash with the visible one's hero.
                enabled: i == _index,
                child: TickerMode(
                  enabled: i == _index,
                  child: ReloadSignal(
                    signal: _signals.putIfAbsent(i, () => ValueNotifier(0)),
                    child: tabs[i].screen(widget.session),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        // Tabs outside the bar (incl. the bell) highlight "المزيد".
        selectedIndex: mainIndex >= 0 ? mainIndex : main.length,
        onDestinationSelected: (i) => i == main.length
            ? _openMore(user, tabs)
            : _select(tabs.indexOf(main[i])),
        destinations: [
          for (final t in main)
            NavigationDestination(icon: Icon(t.icon), label: t.labelFor(user)),
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'المزيد',
          ),
        ],
      ),
    );
  }
}

/// "المزيد": the remaining tabs as a grid, plus dark mode and logout.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.user,
    required this.tabs,
    required this.onLogout,
  });

  final User user;
  final List<_Tab> tabs;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (tabs.isNotEmpty)
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.15,
                children: [
                  for (final t in tabs)
                    Material(
                      color: colors.secondaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, t),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(t.icon, color: colors.primary, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              t.labelFor(user),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: themeMode,
              builder: (context, mode, _) {
                final dark =
                    mode == ThemeMode.dark ||
                    (mode == ThemeMode.system &&
                        MediaQuery.platformBrightnessOf(context) ==
                            Brightness.dark);
                return SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('الوضع الداكن'),
                  value: dark,
                  onChanged: (v) =>
                      themeMode.value = v ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('تسجيل الخروج'),
              onTap: () async {
                if (await confirm(
                  context,
                  'تسجيل الخروج',
                  'متأكد إنك عايز تخرج من الحساب؟',
                )) {
                  if (context.mounted) Navigator.pop(context);
                  onLogout();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
