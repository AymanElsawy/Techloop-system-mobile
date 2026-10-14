import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/report.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../customers/customer_details_screen.dart';
import 'party_report_screen.dart';

/// First bucket is "not due yet"; the rest are days past due.
String _bucketLabel(List<String> buckets, int i) =>
    i == 0 ? buckets[0] : 'متأخر ${buckets[i]} يوم';

String _percent(num? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// التقارير (managers): sales by product / governorate / rep with profit, debt aging, purchases,
/// and customers / suppliers (all, or one in detail). All export as a CSV file (opens in Excel)
/// through the share sheet.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _tab = 'sales';
  String _groupBy = 'product';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime.now();
  DateTime? _pFrom; // purchases: empty = everything
  DateTime? _pTo;
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final reports = context.app.reports;
      final (bytes, name) = _tab == 'sales'
          ? (
              await reports.csv('sales', {
                'groupBy': _groupBy,
                'from': isoDay(_from),
                'to': isoDay(_to),
              }),
              'مبيعات-${reportGroupLabels[_groupBy]}-${isoDay(_from)}_${isoDay(_to)}.csv',
            )
          : partyReportLabels.containsKey(_tab)
          ? (
              await reports.csv(_tab, {
                'from': isoDay(_from),
                'to': isoDay(_to),
              }),
              'كل-${partyReportLabels[_tab]}-${isoDay(_from)}_${isoDay(_to)}.csv',
            )
          : _tab == 'aging'
          ? (
              await reports.csv('aging'),
              'أعمار-الديون-${isoDay(DateTime.now())}.csv',
            )
          : (
              await reports.csv('purchases', {
                if (_pFrom != null) 'from': isoDay(_pFrom!),
                if (_pTo != null) 'to': isoDay(_pTo!),
              }),
              'مشتريات-الأصناف-${_pFrom == null ? 'الكل' : isoDay(_pFrom!)}_${isoDay(_pTo ?? DateTime.now())}.csv',
            );
      await Printing.sharePdf(
        bytes: bytes,
        filename: name,
      ); // shares any file, not only PDFs
    } catch (e) {
      if (mounted)
        toast(context, errorMessage(e, 'تعذر التصدير. حاول مرة أخرى.'));
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exporting ? null : _export,
        icon: const Icon(Icons.file_download_outlined),
        label: Text(_exporting ? 'جاري التصدير...' : 'تصدير Excel'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoiceBar<String>(
                  options: const {
                    'sales': 'المبيعات والربح',
                    'aging': 'أعمار الديون',
                    'purchases': 'المشتريات',
                    ...partyReportLabels,
                  },
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
                if (_tab == 'sales') ...[
                  const SizedBox(height: 8),
                  ChoiceBar<String>(
                    options: {
                      for (final e in reportGroupLabels.entries)
                        e.key: 'حسب ${e.value}',
                    },
                    value: _groupBy,
                    onChanged: (v) => setState(() => _groupBy = v),
                  ),
                ],
                // Sales, customers and suppliers share the period.
                if (_tab == 'sales' || partyReportLabels.containsKey(_tab)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DateField(
                          label: 'من',
                          value: _from,
                          onChanged: (d) => setState(() => _from = d ?? _from),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DateField(
                          label: 'إلى',
                          value: _to,
                          onChanged: (d) => setState(() => _to = d ?? _to),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_tab == 'purchases') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DateField(
                          label: 'من (الكل)',
                          value: _pFrom,
                          onChanged: (d) => setState(() => _pFrom = d),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DateField(
                          label: 'إلى',
                          value: _pTo,
                          onChanged: (d) => setState(() => _pTo = d),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _tab == 'sales'
                ? AsyncView<SalesReport>(
                    key: ValueKey((_groupBy, _from, _to)),
                    load: () => context.app.reports.sales(
                      _groupBy,
                      isoDay(_from),
                      isoDay(_to),
                    ),
                    errorText: 'حدث خطأ أثناء تحميل التقرير.',
                    builder: (context, r) => _SalesView(report: r),
                  )
                : partyReportLabels.containsKey(_tab)
                ? AsyncView<List<PartyRow>>(
                    key: ValueKey((_tab, _from, _to)),
                    load: () => context.app.reports.parties(
                      _tab,
                      isoDay(_from),
                      isoDay(_to),
                    ),
                    errorText: 'حدث خطأ أثناء تحميل التقرير.',
                    builder: (context, rows) => _PartiesView(
                      kind: _tab,
                      rows: rows,
                      from: _from,
                      to: _to,
                    ),
                  )
                : _tab == 'aging'
                ? AsyncView<AgingReport>(
                    load: context.app.reports.aging,
                    errorText: 'حدث خطأ أثناء تحميل التقرير.',
                    builder: (context, r) => _AgingView(report: r),
                  )
                : AsyncView<List<PurchaseRow>>(
                    key: ValueKey((_pFrom, _pTo)),
                    load: () => context.app.reports.purchases(
                      _pFrom == null ? null : isoDay(_pFrom!),
                      _pTo == null ? null : isoDay(_pTo!),
                    ),
                    errorText: 'حدث خطأ أثناء تحميل التقرير.',
                    builder: (context, rows) => _PurchasesView(rows: rows),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SalesView extends StatelessWidget {
  const _SalesView({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final t = report.totals;
    final colors = context.colors;
    if (report.rows.isEmpty)
      return const PageList(children: [EmptyCard('مفيش مبيعات في الفترة دي.')]);
    return PageList(
      bottomPadding: 96, // room for the Excel button
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'صافي المبيعات',
              value: money(t.net),
              hint: '${t.invoices} فاتورة · مرتجع ${money(t.returns)}',
            ),
            StatCard(label: 'التكلفة', value: money(t.cost)),
            StatCard(
              label: 'الربح',
              value: money(t.profit),
              valueColor: t.profit < 0 ? colors.danger : null,
            ),
            StatCard(
              label: 'هامش الربح',
              value: _percent(margin(t.net, t.profit)),
            ),
          ],
        ),
        SectionCard(
          title: 'حسب ${reportGroupLabels[report.groupBy]}',
          children: [
            for (final r in report.rows)
              Tile(
                title: '${r.name}${r.costMissing ? ' *' : ''}',
                subtitle: [
                  if (report.groupBy == 'product')
                    'الكمية ${number(r.quantity)}',
                  '${r.invoices} فاتورة',
                  if (r.returns > 0) 'مرتجع ${money(r.returns)}',
                  'تكلفة ${money(r.cost)}',
                ].dotted(),
                trailing: money(r.net),
                trailingHint:
                    'ربح ${money(r.profit)} · ${_percent(margin(r.net, r.profit))}',
                trailingHintColor: r.profit < 0 ? colors.danger : null,
              ),
          ],
        ),
        Text(
          'الربح = صافي المبيعات − التكلفة (متوسط سعر الشراء وقت البيع). المرتجعات بتتحسب على المندوب اللي باع.'
          '${report.rows.any((r) => r.costMissing) ? '\n* فيه أصناف اتباعت من غير سعر شراء، فتكلفتها محسوبة صفر.' : ''}',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _AgingView extends StatelessWidget {
  const _AgingView({required this.report});

  final AgingReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (report.rows.isEmpty)
      return const PageList(
        children: [EmptyCard('مفيش مديونيات على العملاء.')],
      );
    return PageList(
      bottomPadding: 96, // room for the Excel button
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'إجمالي المديونية',
              value: money(report.totalDebt),
              hint: '${report.rows.length} عميل',
            ),
            for (var i = 0; i < report.buckets.length; i++)
              StatCard(
                label: _bucketLabel(report.buckets, i),
                value: money(report.totalBuckets[i]),
                valueColor:
                    i == report.buckets.length - 1 && report.totalBuckets[i] > 0
                    ? colors.danger
                    : null,
              ),
          ],
        ),
        SectionCard(
          title: 'العملاء',
          children: [
            for (final r in report.rows)
              Tile(
                title: r.customer.name,
                subtitle: [
                  r.governorate,
                  for (var i = 0; i < r.buckets.length; i++)
                    if (r.buckets[i] > 0)
                      '${_bucketLabel(report.buckets, i)}: ${money(r.buckets[i])}',
                ].dotted(),
                trailing: money(r.debt),
                trailingHint: r.oldestDays < 0
                    ? 'لم يستحق'
                    : 'متأخر ${r.oldestDays} يوم',
                trailingHintColor: r.buckets.last > 0 ? colors.danger : null,
                onTap: () =>
                    push(context, CustomerDetailsScreen(id: r.customer.id)),
              ),
          ],
        ),
        Text(
          'المدفوع بيسدّد أقدم فاتورة الأول، فالمديونية الباقية بتتوزع على أحدث الفواتير. التأخير من ميعاد الاستحقاق '
          '(مدة سداد العميل)، واللي ملوش مدة سداد من تاريخ الفاتورة.',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// Per product: every supplier it was bought from, cheapest average first.
class _PurchasesView extends StatelessWidget {
  const _PurchasesView({required this.rows});

  final List<PurchaseRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty)
      return const PageList(
        children: [EmptyCard('مفيش مشتريات في الفترة دي.')],
      );
    final byProduct = <String, List<PurchaseRow>>{};
    for (final r in rows) {
      (byProduct[r.product.id] ??= []).add(r);
    }
    return PageList(
      bottomPadding: 96, // room for the Excel button
      children: [
        for (final list in byProduct.values)
          SectionCard(
            title: list.first.product.name,
            trailing: list.first.currentAvgCost == null
                ? null
                : Text(
                    'المتوسط الحالي ${money(list.first.currentAvgCost!)}',
                    style: TextStyle(color: context.colors.muted, fontSize: 12),
                  ),
            children: [
              for (final r in list)
                Tile(
                  title: r.supplier.name,
                  subtitle: [
                    '${r.receipts} مرة',
                    'الكمية ${number(r.quantity)}',
                    'من ${number(r.minCost)} لـ ${number(r.maxCost)}',
                    'آخر سعر ${number(r.lastCost)} (${shortDate(r.lastAt)})',
                  ].dotted(),
                  trailing: money(r.avgCost),
                  trailingHint: 'متوسط',
                ),
            ],
          ),
        Text(
          'الصنف واحد مهما اختلف المورد، ومتوسط سعره بيتحسب من كل المشتريات.',
          style: TextStyle(color: context.colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// كل العملاء / كل الموردين in the period; tap one for their detailed report.
class _PartiesView extends StatefulWidget {
  const _PartiesView({
    required this.kind,
    required this.rows,
    required this.from,
    required this.to,
  });

  final String kind;
  final List<PartyRow> rows;
  final DateTime from;
  final DateTime to;

  @override
  State<_PartiesView> createState() => _PartiesViewState();
}

class _PartiesViewState extends State<_PartiesView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customers = widget.kind == 'customers';
    final colors = context.colors;
    if (widget.rows.isEmpty) {
      return PageList(
        children: [
          EmptyCard(
            customers
                ? 'مفيش عملاء في الفترة دي.'
                : 'مفيش موردين في الفترة دي.',
          ),
        ],
      );
    }
    num total(num Function(PartyRow) f) =>
        widget.rows.fold<num>(0, (s, r) => s + f(r));
    final totals = PartyRow.fromJson({
      customers ? 'customer' : 'supplier': {'id': '', 'name': ''},
      customers ? 'invoices' : 'receipts': total((r) => r.count),
      customers ? 'net' : 'purchases': total((r) => r.amount),
      'returns': total((r) => r.returns),
      if (customers) 'profit': total((r) => r.profit ?? 0),
      customers ? 'collected' : 'paid': total((r) => r.paid),
      customers ? 'balance' : 'debt': total((r) => r.balance),
    }, customers: customers);
    final rows = widget.rows
        .where((r) => _query.isEmpty || r.party.name.contains(_query))
        .toList();
    return PageList(
      bottomPadding: 96, // room for the Excel button
      children: [
        StatGrid(children: partyStats(context, totals, customers)),
        TextField(
          decoration: InputDecoration(
            hintText: customers ? 'اسم العميل' : 'اسم المورد',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        SectionCard(
          title: '${partyReportLabels[widget.kind]} (${rows.length})',
          empty: 'مفيش نتايج.',
          children: [
            for (final r in rows)
              Tile(
                title: r.party.name,
                subtitle: [
                  if (r.hint != null) r.hint!,
                  customers ? '${r.count} فاتورة' : '${r.count} مرة توريد',
                  customers
                      ? 'محصّل ${money(r.paid)}'
                      : 'مدفوع ${money(r.paid)}',
                  if (customers && r.profit != null) 'ربح ${money(r.profit!)}',
                ].dotted(),
                trailing: money(r.amount),
                trailingHint: customers
                    ? 'الرصيد ${money(r.balance)}'
                    : 'المديونية ${money(r.balance)}',
                trailingHintColor: r.balance > 0 ? colors.danger : null,
                onTap: () => push(
                  context,
                  PartyReportScreen(
                    kind: widget.kind,
                    party: r.party,
                    from: widget.from,
                    to: widget.to,
                  ),
                ),
              ),
          ],
        ),
        Text(
          customers
              ? 'الرقم الكبير = صافي المبيعات في الفترة. الرصيد الحالي هو رصيد النهارده بعد خصم اللي مع المندوب (موجب = عليه). دوس على العميل لتقريره.'
              : 'الرقم الكبير = المشتريات في الفترة. المديونية الحالية هي اللي علينا النهارده. دوس على المورد لتقريره.',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}
