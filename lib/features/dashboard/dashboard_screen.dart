import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'dashboard.dart';

/// Home tab: everything at a glance. Reps see their own numbers first (today's visits, cash box, custody).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Dashboard> _future = _load();

  Future<Dashboard> _load() async => Dashboard.fromJson(
    await widget.session.api.get('/dashboard') as Map<String, dynamic>,
  );

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {} // shown by the FutureBuilder
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Dashboard>(
      future: _future,
      builder: (context, snap) {
        final Widget child;
        if (snap.hasData) {
          child = RefreshIndicator(
            onRefresh: _refresh,
            child: _Content(d: snap.data!, user: widget.session.user!),
          );
        } else if (snap.hasError) {
          child = _Error(message: snap.error.toString(), onRetry: _refresh);
        } else {
          child = const Center(child: CircularProgressIndicator());
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: child,
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.d, required this.user});

  final Dashboard d;
  final User user;

  @override
  Widget build(BuildContext context) {
    final manager = user.isManager;
    final c = context.colors;

    final sections = <Widget>[
      _Greeting(name: user.name),
      // Reps start the day from their visit list.
      if (!manager) _VisitsCard(d: d, showRep: false),
      _Grid(
        children: [
          _Stat(
            label: 'مبيعات اليوم',
            value: money(d.salesToday.total),
            hint: '${d.salesToday.count} فاتورة',
          ),
          _Stat(
            label: 'مبيعات الشهر',
            value: money(d.salesMonth.total),
            hint: '${d.salesMonth.count} فاتورة',
          ),
          _Stat(
            label: 'المحصّل هذا الشهر',
            value: money(d.collectedMonth),
            hint: 'اليوم: ${money(d.collectedToday)}',
          ),
          _Stat(
            label: manager ? 'مديونية العملاء' : 'مديونية عملائي',
            value: money(d.debt),
            valueColor: c.danger,
            hint:
                '${d.debtors} عميل مدين${d.pendingPayments > 0 ? ' · تحت التسليم ${money(d.pendingPayments)}' : ''}',
          ),
        ],
      ),
      if (d.cashBox case final box?)
        _Highlight(
          label: 'خزنتي (لم تُسلَّم)',
          value: money(box.total),
          lines: ['${box.count} مستند'],
        ),
      if (d.treasury case final t?)
        _Highlight(
          label: 'رصيد الخزنة',
          value: money(t.total),
          lines: [
            for (final m in t.byMethod)
              '${paymentMethodLabels[m.method] ?? m.method}: ${money(m.total)}',
          ],
        ),
      _Grid(
        children: [
          if (d.custody case final cu?)
            _Stat(
              label: 'عهدتي',
              value: number(cu.quantity),
              hint: '${cu.items} صنف',
            ),
          if (d.treasury case final t?)
            _Stat(
              label: 'مع المناديب',
              value: money(t.withReps),
              valueColor: t.withReps > 0 ? c.danger : null,
              hint: 'لم تُسلَّم للخزنة',
            ),
          if (d.stock case final s?)
            _Stat(
              label: 'قيمة المخزون',
              value: money(s.value),
              hint: '${s.products} صنف · ${s.lowStock.length} ناقص',
              hintColor: s.lowStock.isNotEmpty ? c.danger : null,
            ),
          _Stat(
            label: 'زيارات اليوم',
            value: '${d.visitsTodayCount}',
            hint:
                'مكتملة ${d.visitsToday['COMPLETED'] ?? 0} · باقي ${d.visitsLeft} · الشهر ${d.visitsMonthCompleted}',
          ),
          if (manager)
            _Stat(
              label: 'العملاء',
              value: '${d.customersTotal}',
              hint: '${d.pendingApproval} بانتظار الموافقة',
              hintColor: d.pendingApproval > 0 ? c.warningFg : null,
            ),
          if (d.suppliers case final s?)
            _Stat(
              label: 'مديونية الموردين',
              value: money(s.debt),
              valueColor: s.debt > 0 ? c.danger : null,
              hint: '${s.count} مورد مدين له',
            ),
        ],
      ),
      _MonthChart(daily: d.daily),
      if (manager) _VisitsCard(d: d, showRep: true),
      _Section(
        title: 'شيكات مستحقة خلال 14 يوم',
        empty: 'مفيش شيكات مستحقة قريب.',
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
      if (d.reps case final reps?)
        _Section(
          title: 'أداء المناديب هذا الشهر',
          empty: 'مفيش مناديب نشطين.',
          children: [
            for (final r in reps)
              _Row(
                title: r.name,
                subtitle: [
                  'تحصيل ${money(r.collected)} · زيارات ${r.visitsCompleted}',
                  if (r.salesProgress != null)
                    'تارجت المبيعات ${number(r.salesProgress!)}%',
                  if (r.collectionProgress != null)
                    'التحصيل ${number(r.collectionProgress!)}%',
                  if (r.yearSalesProgress != null)
                    'مبيعات السنة ${number(r.yearSalesProgress!)}%',
                  if (r.yearCollectionProgress != null)
                    'تحصيل السنة ${number(r.yearCollectionProgress!)}%',
                  if (r.commission != 0) 'عمولة ${money(r.commission)}',
                ].join(' · '),
                trailing: money(r.sales),
                trailingHint: r.cashHeld > 0
                    ? 'معه ${money(r.cashHeld)}'
                    : null,
                trailingHintColor: c.danger,
              ),
          ],
        ),
      _Section(
        title: 'أعلى المديونيات',
        empty: 'مفيش مديونيات.',
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
      _Section(
        title: 'آخر الفواتير',
        empty: 'مفيش فواتير لسه.',
        children: [
          for (final i in d.recentInvoices)
            _Row(
              title: i.cancelled ? '${i.customer} (ملغاة)' : i.customer,
              subtitle:
                  '#${i.number} · ${dayMonth(i.createdAt)} ${time(i.createdAt)}${manager ? ' · ${i.by}' : ''}',
              trailing: money(i.total),
              trailingHint: !i.cancelled && i.remaining > 0
                  ? 'باقي ${money(i.remaining)}'
                  : null,
              trailingHintColor: c.danger,
            ),
        ],
      ),
      if (d.stock case final s? when s.lowStock.isNotEmpty)
        _Section(
          title: 'نواقص المخزون',
          titleColor: c.danger,
          empty: '',
          children: [
            for (final p in s.lowStock)
              _Row(
                title: p.name,
                subtitle: 'الحد الأدنى ${number(p.minQuantity)}',
                trailing: number(p.quantity),
                trailingColor: c.danger,
              ),
          ],
        ),
    ];

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => sections[i],
    );
  }

  static String _dueIn(DateTime due) {
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
}

// ---------- building blocks ----------

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
    this.hintColor,
  });

  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;
  final Color? hintColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: hintColor ?? c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dark card for the money that matters most (treasury / the rep's cash box).
class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.label,
    required this.value,
    required this.lines,
  });

  final String label;
  final String value;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dim = c.onHighlight.withValues(alpha: 0.75);
    return Card(
      color: c.highlight,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: dim)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: c.onHighlight,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final l in lines)
                  Text(l, style: TextStyle(color: dim, fontSize: 12)),
              ],
            ),
          ],
        ),
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
    this.titleColor,
  });

  final String title;
  final String empty;
  final List<Widget> children;
  final Color? titleColor;

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
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: titleColor,
              ),
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
    this.trailingHintColor,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final String? trailingHint;
  final Color? trailingColor;
  final Color? trailingHintColor;
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
                    style: TextStyle(
                      fontSize: 11.5,
                      color: trailingHintColor ?? c.muted,
                    ),
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
