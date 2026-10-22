import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../data/models/visit.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/return_details_screen.dart';
import '../visits/visit_details_screen.dart';
import 'targets_pdf_screen.dart';

/// Everything about one sales rep (managers): for the period, target & commission, visits, invoices,
/// returns, collections and expenses; right now, custody and cash box. Opened from the reps tab.
class RepDetailsScreen extends StatefulWidget {
  const RepDetailsScreen({
    super.key,
    required this.id,
    required this.name,
    required this.period,
  });

  final String id;
  final String name;
  final TargetPeriod period;

  @override
  State<RepDetailsScreen> createState() => _RepDetailsScreenState();
}

class _RepDetailsScreenState extends State<RepDetailsScreen> {
  late var _period = widget.period;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'طباعة تقرير ${widget.name}',
            onPressed: () => push(
              context,
              TargetsPdfScreen(period: _period, repId: widget.id),
            ),
          ),
        ],
      ),
      body: AsyncView<RepTargetReport>(
        // A new period loads again.
        key: ValueKey((_period.key, _period.yearly)),
        load: () => context.app.users.repTargets(widget.id, _period),
        builder: _body,
      ),
    );
  }

  Widget _body(BuildContext context, RepTargetReport d) {
    final r = d.rep;
    final c = context.colors;
    String goal(num? goal, int? progress) =>
        goal == null ? 'بدون تارجت' : '${number(progress!)}% من ${money(goal)}';
    return PageList(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    d.warehouse ?? 'من غير مخزن',
                    if (d.governorates.isNotEmpty) d.governorates.join('، '),
                  ].join(' · '),
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: 8),
                ChoiceBar<bool>(
                  options: const {false: 'شهري', true: 'سنوي'},
                  value: _period.yearly,
                  onChanged: (y) =>
                      setState(() => _period = _period.withYearly(y)),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: _period.yearly
                          ? 'السنة السابقة'
                          : 'الشهر السابق',
                      onPressed: () =>
                          setState(() => _period = _period.shift(-1)),
                    ),
                    Expanded(
                      child: Text(
                        _period.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: _period.yearly
                          ? 'السنة التالية'
                          : 'الشهر التالي',
                      onPressed: _period.isCurrent
                          ? null
                          : () => setState(() => _period = _period.shift(1)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        StatGrid(
          children: [
            StatCard(
              label: 'صافي المبيعات',
              value: money(r.netSales),
              hint: goal(r.salesGoal, r.salesProgress),
            ),
            StatCard(
              label: 'التحصيل',
              value: money(r.collected),
              hint: goal(r.collectionGoal, r.collectionProgress),
            ),
            StatCard(
              label: 'العمولة',
              value: money(r.commission),
              hint:
                  'مبيعات ${number(r.salesCommissionRate)}% · تحصيل ${number(r.collectionCommissionRate)}%',
            ),
            StatCard(
              label: 'خزنة المندوب (دلوقتي)',
              value: money(d.cashTotal),
              hint: 'نقدي ${money(d.cash)} · مصروفات ${money(d.cashExpenses)}',
            ),
          ],
        ),
        _PagedSection(
          title: 'الزيارات (${number(d.visits.length)})',
          empty: 'مفيش زيارات في الفترة دي.',
          children: [
            for (final v in d.visits)
              Tile(
                title: v.customer,
                subtitle:
                    '${shortDate(v.date)} · ${visitPurposeLabels[v.purpose]}',
                badge: StatusBadge(
                  visitStatusLabels[v.status]!,
                  tone: statusTones[v.status]!,
                ),
                onTap: () => push(context, VisitDetailsScreen(id: v.id)),
              ),
          ],
        ),
        _PagedSection(
          title: 'فواتير البيع (${number(d.invoices.length)})',
          empty: 'مفيش فواتير في الفترة دي.',
          children: [
            for (final i in d.invoices)
              Tile(
                title: '${i.number} · ${i.customer}',
                subtitle: '${shortDate(i.date)} · ${i.detail}',
                trailing: money(i.amount),
                trailingHint: 'مدفوع ${money(i.paid ?? 0)}',
                onTap: () => push(context, InvoiceDetailsScreen(id: i.id)),
              ),
          ],
        ),
        if (d.returns.isNotEmpty)
          _PagedSection(
            title: 'المرتجعات (${number(d.returns.length)})',
            children: [
              for (final x in d.returns)
                Tile(
                  title: '${x.number} · ${x.customer}',
                  subtitle: '${shortDate(x.date)} · على فاتورة ${x.detail}',
                  trailing: money(x.amount),
                  onTap: () => push(context, ReturnDetailsScreen(id: x.id)),
                ),
            ],
          ),
        _PagedSection(
          title: 'التحصيلات (${number(d.collections.length)})',
          empty: 'مفيش تحصيلات في الفترة دي.',
          children: [
            for (final x in d.collections)
              Tile(
                title: '${x.number} · ${x.customer}',
                subtitle: '${shortDate(x.date)} · ${x.detail}',
                trailing: money(x.amount),
                onTap: () => push(context, CollectionDetailsScreen(id: x.id)),
              ),
          ],
        ),
        _PagedSection(
          title: 'المصروفات (${number(d.expenses.length)})',
          empty: 'مفيش مصروفات في الفترة دي.',
          children: [
            for (final e in d.expenses)
              Tile(
                title: e.category ?? 'مصروف',
                subtitle: [shortDate(e.date), ?e.notes].join(' · '),
                trailing: money(e.amount),
                trailingHint: e.pending ? 'مع المندوب' : 'اتسلمت',
              ),
          ],
        ),
        _PagedSection(
          title: 'العهدة دلوقتي (${number(d.custody.length)} صنف)',
          empty: 'مفيش عهدة مع المندوب.',
          children: [
            for (final s in d.custody)
              Tile(
                title: s.name,
                subtitle: '${number(s.quantity)} ${unitLabels[s.unit] ?? ''}',
                trailing: money(s.value),
                trailingHint: 'بسعر البيع',
              ),
          ],
        ),
      ],
    );
  }
}

/// A collapsible section that shows [_pageSize] rows at a time, with "عرض المزيد" under them.
class _PagedSection extends StatefulWidget {
  const _PagedSection({
    required this.title,
    required this.children,
    this.empty = '',
  });

  final String title;
  final List<Widget> children;
  final String empty;

  @override
  State<_PagedSection> createState() => _PagedSectionState();
}

const _pageSize = 10;

class _PagedSectionState extends State<_PagedSection> {
  var _shown = _pageSize;

  @override
  Widget build(BuildContext context) {
    final all = widget.children;
    final rest = all.length - _shown;
    return SectionCard(
      title: widget.title,
      empty: widget.empty,
      collapsible: true,
      children: [
        ...all.take(_shown),
        if (rest > 0)
          TextButton(
            onPressed: () => setState(() => _shown += _pageSize),
            child: Text('عرض المزيد (${number(rest)} باقي)'),
          ),
      ],
    );
  }
}
