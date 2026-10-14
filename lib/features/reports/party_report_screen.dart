import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/report.dart';
import '../../data/models/treasury.dart';
import '../documents/document_pdf_screen.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../inventory/movement_list.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/return_details_screen.dart';

/// Totals of one customer / supplier row (or of a detailed report): same cards in both views.
List<Widget> partyStats(BuildContext context, PartyRow r, bool customers) {
  final danger = context.colors.danger;
  return customers
      ? [
          StatCard(
            label: 'صافي المبيعات',
            value: money(r.amount),
            hint: '${r.count} فاتورة · مرتجع ${money(r.returns)}',
          ),
          StatCard(
            label: 'الربح',
            value: money(r.profit ?? 0),
            valueColor: (r.profit ?? 0) < 0 ? danger : null,
          ),
          StatCard(label: 'المحصّل', value: money(r.paid)),
          StatCard(
            label: 'الرصيد الحالي',
            value: money(r.balance),
            hint: r.balance >= 0 ? 'عليه النهارده' : 'له النهارده',
            valueColor: r.balance > 0 ? danger : null,
          ),
        ]
      : [
          StatCard(
            label: 'المشتريات',
            value: money(r.amount),
            hint: '${r.count} مرة توريد',
          ),
          StatCard(label: 'المدفوع', value: money(r.paid)),
          StatCard(
            label: 'المديونية الحالية',
            value: money(r.balance),
            hint: 'علينا النهارده',
            valueColor: r.balance > 0 ? danger : null,
          ),
        ];
}

/// تقرير عميل / مورد: totals, products and every document in the period, exportable to Excel.
class PartyReportScreen extends StatefulWidget {
  const PartyReportScreen({
    super.key,
    required this.kind,
    required this.party,
    required this.from,
    required this.to,
  });

  /// customers | suppliers
  final String kind;
  final Ref party;
  final DateTime from;
  final DateTime to;

  @override
  State<PartyReportScreen> createState() => _PartyReportScreenState();
}

class _PartyReportScreenState extends State<PartyReportScreen> {
  bool _exporting = false;

  bool get _customers => widget.kind == 'customers';
  Map<String, String> get _period => {
    'from': isoDay(widget.from),
    'to': isoDay(widget.to),
  };

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final bytes = await context.app.reports.csv(
        '${widget.kind}/${widget.party.id}',
        _period,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            '${widget.party.name}-${_period['from']}_${_period['to']}.csv',
      ); // shares any file, not only PDFs
    } catch (e) {
      if (mounted) {
        toast(context, errorMessage(e, 'تعذر التصدير. حاول مرة أخرى.'));
      }
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget? _screen(ReportLine l) => switch (l.kind) {
    'invoice' => InvoiceDetailsScreen(id: l.id),
    'return' => ReturnDetailsScreen(id: l.id),
    'collection' => CollectionDetailsScreen(id: l.id),
    'receipt' => MovementDetailsScreen(id: l.id),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.muted;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'كشف حساب PDF (واتساب)',
            onPressed: () => push(
              context,
              StatementPdfScreen(
                kind: widget.kind,
                party: widget.party,
                from: widget.from,
                to: widget.to,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exporting ? null : _export,
        icon: const Icon(Icons.file_download_outlined),
        label: Text(_exporting ? 'جاري التصدير...' : 'تصدير Excel'),
      ),
      body: AsyncView<PartyReport>(
        load: () => context.app.reports.party(
          widget.kind,
          widget.party.id,
          _period['from']!,
          _period['to']!,
        ),
        errorText: 'حدث خطأ أثناء تحميل التقرير.',
        builder: (context, r) => PageList(
          bottomPadding: 96, // room for the Excel button
          children: [
            Text(
              'من ${shortDate(widget.from)} إلى ${shortDate(widget.to)}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            StatGrid(children: partyStats(context, r.summary, _customers)),
            if (r.products.isNotEmpty)
              SectionCard(
                title: 'الأصناف',
                collapsible: true,
                children: [
                  for (final p in r.products)
                    Tile(
                      title: p.name,
                      subtitle: 'الكمية ${number(p.quantity)}',
                      trailing: money(p.amount),
                      trailingHint: _customers
                          ? 'ربح ${money(p.extra)}'
                          : 'متوسط ${money(p.extra)}',
                    ),
                ],
              ),
            SectionCard(
              title: 'كشف الحساب (${r.lines.length} حركة)',
              children: [
                Tile(title: 'رصيد أول المدة', trailing: money(r.opening)),
                for (final l in r.lines)
                  Tile(
                    title: '${reportLineLabels[l.kind]} ${l.number}',
                    subtitle: [
                      shortDate(l.date),
                      if (l.debit > 0)
                        '${_customers ? 'عليه' : 'مشتريات'} ${money(l.debit)}',
                      if (l.credit > 0)
                        '${_customers ? 'له' : 'مدفوع'} ${money(l.credit)}',
                      if (l.method != null)
                        methodLabel(l.method)
                      else if (l.kind == 'invoice')
                        deferredLabel,
                      if (l.bounced)
                        'شيك مرتد (مش محسوب)'
                      else if (l.pending)
                        'مع المندوب',
                    ].dotted(),
                    trailing: money(l.balance),
                    trailingHint: 'الرصيد',
                    trailingHintColor: l.bounced ? context.colors.danger : null,
                    onTap: _screen(l) == null
                        ? null
                        : () => push(context, _screen(l)!),
                  ),
                Tile(
                  title: 'رصيد آخر المدة',
                  trailing: money(r.closing),
                  trailingColor: r.closing > 0 ? context.colors.danger : null,
                ),
              ],
            ),
            if (_customers)
              Text(
                'الفلوس اللي مع المندوب بتتخصم من الرصيد على طول. الشيك المرتد مش محسوب في المدفوع.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

/// كشف حساب as an A4 PDF for the customer / supplier (no profit or cost): preview, print, and share
/// (WhatsApp) from the preview's share button. Same sheet as the web statement.
PrintDoc statementDoc(
  PartyReport r,
  Ref party,
  DateTime from,
  DateTime to, {
  bool customers = true,
}) {
  final debit = r.lines.fold<num>(0, (s, l) => s + l.debit);
  final credit = r.lines.fold<num>(0, (s, l) => s + l.credit);
  final (debitLabel, creditLabel) = customers
      ? ('مدين (عليه)', 'دائن (له)')
      : ('التوريدات (له)', 'المدفوع (عليه)');
  final owes = r.closing >= 0
      ? (customers ? 'مستحق على العميل' : 'مستحق للمورد')
      : (customers ? 'مستحق للعميل' : 'مستحق على المورد');
  return PrintDoc(
    title: 'كشف حساب',
    number: '',
    date: DateTime.now(),
    cancelled: null,
    partyLabel: customers ? 'العميل' : 'المورد',
    // A supplier's hint is its phone: don't list it twice.
    partyLines: [party.name, if (customers) ?r.summary.hint, ?r.phone],
    meta: [
      ('الفترة', 'من ${shortDate(from)} إلى ${shortDate(to)}'),
      ('رصيد أول المدة', money(r.opening)),
    ],
    columns: [
      'التاريخ',
      'المستند',
      debitLabel,
      creditLabel,
      'الرصيد',
      'ملاحظة',
    ],
    rows: [
      ['', 'رصيد أول المدة', '', '', money(r.opening), ''],
      for (final l in r.lines)
        [
          shortDate(l.date),
          '${l.kind == 'receipt' ? 'توريد' : reportLineLabels[l.kind]} ${l.number}',
          l.debit > 0 ? money(l.debit) : '',
          l.credit > 0 ? money(l.credit) : '',
          money(l.balance),
          [
            if (l.method != null)
              methodLabel(l.method)
            else if (l.kind == 'invoice')
              deferredLabel,
            if (l.bounced) 'شيك مرتد (غير محسوب)',
          ].join(' - '),
        ],
    ],
    totals: [
      ('إجمالي $debitLabel', money(debit)),
      ('إجمالي $creditLabel', money(credit)),
      ('رصيد آخر المدة ($owes)', money(r.closing.abs())),
    ],
    notes: customers
        ? 'مدين = فواتير البيع. دائن = المدفوع في الفواتير والتحصيلات والمرتجعات. الشيك المرتد غير محسوب.'
        : 'التوريدات = قيمة البضاعة الموردة. المدفوع = المدفوع وقت التوريد والدفعات.',
    signatures: (
      customers ? 'توقيع العميل' : 'توقيع المورد',
      'اعتماد الحسابات',
    ),
  );
}

class StatementPdfScreen extends StatelessWidget {
  const StatementPdfScreen({
    super.key,
    required this.kind,
    required this.party,
    required this.from,
    required this.to,
  });

  /// customers | suppliers
  final String kind;
  final Ref party;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final customers = kind == 'customers';
    return Scaffold(
      appBar: AppBar(title: const Text('كشف حساب')),
      body: AsyncView<(Company, PartyReport)>(
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل كشف الحساب.',
        load: () => (
          app.documents.company(),
          app.reports.party(kind, party.id, isoDay(from), isoDay(to)),
        ).wait,
        builder: (context, d) => PdfPreview(
          build: (format) => buildDocumentPdf(
            d.$1,
            statementDoc(d.$2, party, from, to, customers: customers),
            format,
          ),
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName:
              'كشف حساب ${party.name} ${isoDay(from)}_${isoDay(to)}.pdf',
        ),
      ),
    );
  }
}
