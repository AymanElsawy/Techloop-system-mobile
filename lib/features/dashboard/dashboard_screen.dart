import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart' show ReloadOnShow;
import '../../widgets/ui.dart' show SkeletonList, push;
import '../customers/customer_list_screen.dart';
import '../documents/document_list_screen.dart' show pickParty;
import '../inventory/product_list.dart';
import '../sales/collection_form_screen.dart';
import '../sales/invoice_form_screen.dart';
import '../treasury/treasury_screen.dart';
import '../users/targets_screen.dart';
import '../visits/visit_form_screen.dart';
import 'dashboard.dart';

/// Home tab: 4 numbers, what needs attention (only non-zero), then النهارده / الشهر / المناديب tabs.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with ReloadOnShow<DashboardScreen> {
  late Future<Dashboard> _future = _load();

  Future<Dashboard> _load() async => Dashboard.fromJson(
    await widget.session.api.get('/dashboard') as Map<String, dynamic>,
  );

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {} // shown by the FutureBuilder
  }

  @override
  Future<void> reloadInPlace() => _refresh();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Dashboard>(
      future: _future,
      builder: (context, snap) {
        final Widget child;
        if (snap.hasData) {
          child = RefreshIndicator(
            onRefresh: _refresh,
            child: _Content(
              d: snap.data!,
              user: widget.session.user!,
              onChanged: _refresh,
            ),
          );
        } else if (snap.hasError) {
          child = _Error(message: snap.error.toString(), onRetry: _refresh);
        } else {
          child = const SkeletonList();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: child,
        );
      },
    );
  }
}

enum _Tab {
  today('النهارده'),
  month('الشهر'),
  reps('المناديب');

  const _Tab(this.label);
  final String label;
}

class _Content extends StatefulWidget {
  const _Content({
    required this.d,
    required this.user,
    required this.onChanged,
  });

  final Dashboard d;
  final User user;

  /// After a quick action's form closes.
  final Future<void> Function() onChanged;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  var _tab = _Tab.today;

  /// Tab screens have no app bar of their own.
  void _open(String title, Widget body) => push(
    context,
    Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final manager = widget.user.isManager;
    final c = context.colors;
    final tabs = [
      _Tab.today,
      _Tab.month,
      if (d.reps?.isNotEmpty ?? false) _Tab.reps,
    ];
    final tab = tabs.contains(_tab) ? _tab : _Tab.today;
    final repsWithCash = d.reps?.where((r) => r.cashHeld > 0).length ?? 0;
    final lowStock = d.stock?.lowStock ?? const [];

    final alerts = [
      if (d.treasury case final t? when t.withReps > 0)
        _Alert(
          title: '${money(t.withReps)} مع المناديب',
          subtitle: '$repsWithCash مندوب لسه ماسلّمش للخزنة',
          onTap: () => _open('الخزنة', const TreasuryScreen()),
        ),
      if (d.cheques.isNotEmpty)
        _Alert(
          title: '${d.cheques.length} شيك مستحق خلال 14 يوم',
          subtitle: 'أقربهم ${_dueIn(d.cheques.first.dueDate)}',
          onTap: () => setState(() => _tab = _Tab.today),
        ),
      if (manager && d.pendingApproval > 0)
        _Alert(
          title: '${d.pendingApproval} عميل بانتظار الموافقة',
          onTap: () => _open('العملاء', const CustomerListScreen()),
        ),
      if (lowStock.isNotEmpty)
        _Alert(
          title: '${lowStock.length} صنف تحت الحد الأدنى',
          subtitle:
              lowStock.take(3).map((p) => p.name).join('، ') +
              (lowStock.length > 3 ? ' …' : ''),
          onTap: () => _open('الأصناف', const ProductList()),
        ),
    ];

    final sections = <Widget>[
      _Greeting(name: widget.user.name),
      if (widget.user.role == UserRole.salesRep)
        _QuickActions(onDone: widget.onChanged),
      _Grid(
        children: [
          _Stat(
            label: 'مبيعات الشهر',
            value: money(d.salesMonth.total),
            hint:
                '${d.salesMonth.count} فاتورة · اليوم ${money(d.salesToday.total)}',
          ),
          _Stat(
            label: 'المحصّل هذا الشهر',
            value: money(d.collectedMonth),
            hint: 'اليوم ${money(d.collectedToday)}',
          ),
          _Stat(
            label: manager ? 'مديونية العملاء' : 'مديونية عملائي',
            onTap: () => _open('العملاء', const CustomerListScreen()),
            value: money(d.debt),
            valueColor: c.danger,
            hint:
                '${d.debtors} عميل مدين${d.pendingPayments > 0 ? ' · تحت التسليم ${money(d.pendingPayments)}' : ''}',
          ),
          if (d.treasury case final t?)
            _Stat(
              label: 'رصيد الخزنة',
              onTap: () => _open('الخزنة', const TreasuryScreen()),
              value: money(t.total),
              highlight: true,
              hint: [
                for (final m in t.byMethod)
                  '${bucketLabel(m.method)} ${money(m.total)}',
              ].join(' · '),
            ),
          if (d.cashBox case final box?)
            _Stat(
              label: 'خزنتي (لم تُسلَّم)',
              onTap: () => _open('خزنتي', const TreasuryScreen()),
              value: money(box.total),
              highlight: true,
              hint: '${box.count} مستند',
            ),
        ],
      ),
      _Section(
        title: 'محتاج متابعة',
        empty: 'كله تمام ✓ مفيش حاجة محتاجة متابعة.',
        children: alerts,
      ),
      SegmentedButton<_Tab>(
        showSelectedIcon: false,
        segments: [
          for (final t in tabs) ButtonSegment(value: t, label: Text(t.label)),
        ],
        selected: {tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
      ...switch (tab) {
        _Tab.today => [
          if (d.visits.isNotEmpty || !manager)
            _VisitsCard(d: d, showRep: manager),
          if (d.cheques.isNotEmpty)
            _Section(
              title: 'شيكات مستحقة خلال 14 يوم',
              empty: '',
              children: [
                for (final ch in d.cheques)
                  _Row(
                    title: ch.customer,
                    subtitle:
                        'شيك ${ch.chequeNumber ?? '—'} · ${dayMonth(ch.dueDate)}${ch.withRep ? ' · مع المندوب' : ''}',
                    trailing: money(ch.amount),
                    trailingHint: _dueIn(ch.dueDate),
                  ),
              ],
            ),
          if (d.visits.isEmpty && d.cheques.isEmpty && manager)
            _Section(
              title: 'النهارده',
              empty: 'مفيش زيارات ولا شيكات النهارده.',
              children: const [],
            ),
        ],
        _Tab.month => [
          _MonthChart(daily: d.daily),
          if (d.topDebtors.isNotEmpty)
            _Section(
              title: 'أعلى المديونيات',
              empty: '',
              children: [
                for (final t in d.topDebtors)
                  _Row(
                    title: t.name,
                    subtitle: t.governorate,
                    trailing: money(t.debit),
                    trailingColor: c.danger,
                  ),
              ],
            ),
        ],
        _Tab.reps => [
          _Section(
            title: 'أعلى المناديب هذا الشهر',
            empty: '',
            children: [
              for (final r in ([
                ...d.reps!,
              ]..sort((a, b) => b.sales.compareTo(a.sales))).take(5))
                _RepRow(
                  name: r.name,
                  sales: r.sales,
                  cashHeld: r.cashHeld,
                  progress: r.salesProgress ?? r.yearSalesProgress,
                  yearly: r.salesProgress == null,
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => _open('التارجت', const TargetsScreen()),
              child: const Text('عرض الكل ‹'),
            ),
          ),
        ],
      },
    ];

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => sections[i],
    );
  }
}

String _dueIn(DateTime due) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final l = due.toLocal();
  final days = DateTime(l.year, l.month, l.day).difference(today).inDays;
  return switch (days) {
    0 => 'النهارده',
    1 => 'بكرة',
    _ => 'بعد $days يوم',
  };
}

// ---------- building blocks ----------

/// A rep's most used actions, one tap from home.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onDone});

  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    Future<void> open(Widget? screen) async {
      if (screen == null) return;
      await push(context, screen);
      await onDone();
    }

    Future<void> forCustomer(
      String type,
      Widget Function(String id) screen,
    ) async {
      final id = await pickParty(context, type);
      if (id != null && context.mounted) await open(screen(id));
    }

    return Row(
      children: [
        for (final (label, icon, onTap) in [
          (
            'زيارة جديدة',
            Icons.event_available_outlined,
            () => open(const VisitFormScreen()),
          ),
          (
            'فاتورة بيع',
            Icons.receipt_long_outlined,
            () =>
                forCustomer('SALE', (id) => InvoiceFormScreen(customerId: id)),
          ),
          (
            'تحصيل',
            Icons.payments_outlined,
            () => forCustomer(
              'COLLECTION',
              (id) => CollectionFormScreen(customerId: id),
            ),
          ),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(0, 76),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 26),
                    const SizedBox(height: 4),
                    Text(label, maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'أهلاً، $name',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          fullDate(DateTime.now()),
          style: TextStyle(color: context.colors.muted),
        ),
      ],
    );
  }
}

/// Two columns on phones, more on wider screens.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.hint,
    this.valueColor,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;

  /// Dark card for the money that matters most (treasury / the rep's cash box).
  final bool highlight;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = highlight ? c.onHighlight.withValues(alpha: 0.75) : c.muted;
    return Card(
      color: highlight ? c.highlight : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: highlight ? c.onHighlight : valueColor,
                  ),
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "محتاج متابعة" line; opens where it can be handled.
class _Alert extends StatelessWidget {
  const _Alert({required this.title, this.subtitle, required this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, size: 20, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// A rep in one glance: sales, target bar (monthly, else yearly), cash not handed over.
class _RepRow extends StatelessWidget {
  const _RepRow({
    required this.name,
    required this.sales,
    required this.cashHeld,
    required this.progress,
    required this.yearly,
  });

  final String name;
  final num sales;
  final num cashHeld;
  final int? progress;
  final bool yearly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final color = p == null
        ? c.muted
        : p >= 50
        ? c.chartCollected
        : c.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                money(sales),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (p == null)
                Expanded(
                  child: Text(
                    'بدون تارجت',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                )
              else ...[
                Expanded(
                  child: Semantics(
                    label: yearly ? 'تارجت مبيعات السنة' : 'تارجت المبيعات',
                    value: '$p%',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (p / 100).clamp(0, 1).toDouble(),
                        minHeight: 6,
                        color: color,
                        backgroundColor: c.border,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${yearly ? 'السنة ' : ''}${number(p)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (cashHeld > 0) ...[
                const SizedBox(width: 10),
                Text(
                  'معاه ${money(cashHeld)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _VisitsCard extends StatelessWidget {
  const _VisitsCard({required this.d, required this.showRep});

  final Dashboard d;
  final bool showRep;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'زيارات اليوم (${d.visitsTodayCount})',
      empty: 'مفيش زيارات النهارده.',
      children: [
        for (final v in d.visits)
          _Row(
            title: v.customer,
            subtitle:
                '${time(v.scheduledAt)} · ${v.governorate}${showRep ? ' · ${v.rep}' : ''}',
            badge: visitStatusLabels[v.status],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.children,
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          Divider(height: 1, color: c.border),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                empty,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            )
          else
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              children[i],
            ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingHint,
    this.trailingColor,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final String? trailingHint;
  final Color? trailingColor;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(subtitle, style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: c.warningBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge!,
                style: TextStyle(fontSize: 12, color: c.warningFg),
              ),
            ),
          if (trailing != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailing!,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: trailingColor,
                  ),
                ),
                if (trailingHint != null)
                  Text(
                    trailingHint!,
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Sales vs collected for every day of the month so far. Bars grow in on load.
class _MonthChart extends StatelessWidget {
  const _MonthChart({required this.daily});

  final Map<String, ({num sales, num collected})> daily;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    String key(int day) =>
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final days = [
      for (var i = 1; i <= now.day; i++) (day: i, v: daily[key(i)]),
    ];
    final max = days.fold<num>(
      1,
      (m, d) => [
        m,
        d.v?.sales ?? 0,
        d.v?.collected ?? 0,
      ].reduce((a, b) => a > b ? a : b),
    );

    Widget bar(num value, Color color) => Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value / max),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, f, _) => FractionallySizedBox(
          heightFactor: f,
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );

    Widget legend(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );

    return Semantics(
      label: 'رسم المبيعات والتحصيل لكل يوم في الشهر',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'حركة الشهر يوم بيوم',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  legend(c.chartSales, 'مبيعات'),
                  const SizedBox(width: 12),
                  legend(c.chartCollected, 'تحصيل'),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 130,
                // Days run left to right like a calendar, even in RTL.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    bar(d.v?.sales ?? 0, c.chartSales),
                                    bar(d.v?.collected ?? 0, c.chartCollected),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                d.day % 5 == 0 || d.day == 1
                                    ? dayNumber(d.day)
                                    : '',
                                style: TextStyle(fontSize: 9, color: c.muted),
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
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: context.colors.muted,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
