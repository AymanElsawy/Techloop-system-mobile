import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../documents/document_pdf_screen.dart' show PdfFonts;

typedef _Section = ({
  String title,
  List<String> columns,
  List<List<String>> rows,
  List<String>? total,
});

/// Same shape as the web /targets/print sheet.
class _Report {
  const _Report(
    this.title,
    this.subtitle,
    this.summary,
    this.sections,
    this.signatures,
  );

  final String title;
  final String subtitle;
  final List<(String, String)> summary;
  final List<_Section> sections;
  final (String, String) signatures;
}

String _target(num? n) => n == null || n == 0 ? '—' : money(n);
String _pct(int? n) => n == null ? '—' : '${number(n)}%';

_Report _allReport(List<TargetRow> reps) {
  num sum(num Function(TargetRow) f) => reps.fold<num>(0, (s, r) => s + f(r));
  return _Report(
    'تقرير التارجت والعمولات',
    'كل المناديب',
    [
      ('عدد المناديب', number(reps.length)),
      ('إجمالي صافي المبيعات', money(sum((r) => r.netSales))),
      ('إجمالي التحصيل', money(sum((r) => r.collected))),
      ('إجمالي العمولات', money(sum((r) => r.commission))),
    ],
    [
      (
        title: 'المناديب',
        columns: [
          '#',
          'المندوب',
          'تارجت المبيعات',
          'صافي المبيعات',
          'الإنجاز',
          'تارجت التحصيل',
          'التحصيل',
          'الإنجاز',
          'العمولة',
        ],
        rows: [
          for (final (i, r) in reps.indexed)
            [
              number(i + 1),
              r.isActive ? r.name : '${r.name} (موقوف)',
              _target(r.salesGoal),
              money(r.netSales),
              _pct(r.salesProgress),
              _target(r.collectionGoal),
              money(r.collected),
              _pct(r.collectionProgress),
              money(r.commission),
            ],
        ],
        total: [
          '',
          'الإجمالي',
          '',
          money(sum((r) => r.netSales)),
          '',
          '',
          money(sum((r) => r.collected)),
          '',
          money(sum((r) => r.commission)),
        ],
      ),
    ],
    ('إعداد', 'اعتماد الإدارة'),
  );
}

_Report _repReport(RepTargetReport d) {
  final r = d.rep;
  List<List<String>> docs(
    List<TargetDoc> list,
    List<String> Function(TargetDoc) cells,
  ) => [
    for (final (i, x) in list.indexed)
      [number(i + 1), x.number, shortDate(x.date), x.customer, ...cells(x)],
  ];
  return _Report(
    'تقرير مندوب',
    r.name,
    [
      (
        'إجمالي الفواتير',
        '${money(r.sales)} (${number(d.invoices.length)} فاتورة)',
      ),
      ('المرتجعات', '${money(r.returns)} (${number(d.returns.length)})'),
      ('صافي المبيعات', money(r.netSales)),
      ('التحصيل', money(r.collected)),
      ('العمولة المستحقة', money(r.commission)),
    ],
    [
      (
        title: 'التارجت والعمولة',
        columns: [
          'البند',
          'التارجت',
          'المحقق',
          'الإنجاز',
          'نسبة العمولة',
          'العمولة',
        ],
        rows: [
          [
            'صافي المبيعات',
            _target(r.salesGoal),
            money(r.netSales),
            _pct(r.salesProgress),
            '${number(r.salesCommissionRate)}%',
            money(r.salesCommission),
          ],
          [
            'التحصيل',
            _target(r.collectionGoal),
            money(r.collected),
            _pct(r.collectionProgress),
            '${number(r.collectionCommissionRate)}%',
            money(r.collectionCommission),
          ],
        ],
        total: ['الإجمالي', '', '', '', '', money(r.commission)],
      ),
      (
        title: 'فواتير البيع',
        columns: [
          '#',
          'رقم الفاتورة',
          'التاريخ',
          'العميل',
          'طريقة الدفع',
          'الإجمالي',
          'المدفوع',
        ],
        rows: docs(
          d.invoices,
          (x) => [x.detail, money(x.amount), money(x.paid ?? 0)],
        ),
        total: ['', 'الإجمالي', '', '', '', money(r.sales), ''],
      ),
      (
        title: 'فواتير المرتجع',
        columns: [
          '#',
          'رقم المرتجع',
          'التاريخ',
          'العميل',
          'من فاتورة',
          'الإجمالي',
        ],
        rows: docs(d.returns, (x) => [x.detail, money(x.amount)]),
        total: ['', 'الإجمالي', '', '', '', money(r.returns)],
      ),
      (
        title: 'التحصيلات',
        columns: [
          '#',
          'رقم الإيصال',
          'التاريخ',
          'العميل',
          'طريقة الدفع',
          'المبلغ',
        ],
        rows: docs(d.collections, (x) => [x.detail, money(x.amount)]),
        total: null,
      ),
    ],
    ('توقيع المندوب', 'اعتماد الإدارة'),
  );
}

/// A4 report, same layout as the documents PDF (company header, black on white).
Future<Uint8List> _buildPdf(
  Company company,
  _Report report,
  String period,
  PdfPageFormat format,
) async {
  final fonts = await PdfFonts.load();
  final text = fonts.text;
  const border = PdfColors.grey500;
  const small = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  const cell = pw.TextStyle(fontSize: 8.5);

  // pw.Table ignores text direction: reverse the columns so the first one sits on the right.
  pw.Widget table(_Section s) => pw.Table(
    border: pw.TableBorder.all(color: border),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final c in s.columns.reversed)
            _pad(text(c, style: cell.copyWith(fontWeight: pw.FontWeight.bold))),
        ],
      ),
      for (final r in s.rows)
        pw.TableRow(
          children: [for (final c in r.reversed) _pad(text(c, style: cell))],
        ),
      if (s.total case final t?)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            for (final c in t.reversed)
              _pad(
                text(c, style: cell.copyWith(fontWeight: pw.FontWeight.bold)),
              ),
          ],
        ),
    ],
  );

  final pdf = pw.Document(
    title: '${report.title} ${report.subtitle} $period',
    author: company.name,
  );
  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: format.copyWith(
          marginLeft: 12 * PdfPageFormat.mm,
          marginRight: 12 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        theme: fonts.theme,
        textDirection: pw.TextDirection.rtl,
      ),
      footer: (context) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Column(
          children: [
            if (company.footer != null) text(company.footer!, style: small),
            text(
              '${company.name} — ${report.title} — $period${context.pagesCount > 1 ? ' — (${context.pageNumber}/${context.pagesCount})' : ''}',
              style: small,
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 2)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(
                      company.name,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (company.address != null)
                      text(company.address!, style: small),
                    if (company.phone != null)
                      text('تليفون: ${company.phone}', style: small),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  text(
                    report.title,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  text(report.subtitle, style: bold),
                  text(period, style: small),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: border)),
          child: pw.Column(
            children: [
              for (final (i, (k, v)) in report.summary.indexed)
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: text(
                        k,
                        style: const pw.TextStyle(color: PdfColors.grey700),
                      ),
                    ),
                    text(
                      v,
                      style: i == report.summary.length - 1 ? bold : null,
                    ),
                  ],
                ),
            ],
          ),
        ),
        for (final s in report.sections) ...[
          pw.SizedBox(height: 12),
          text(s.title, style: bold),
          pw.SizedBox(height: 4),
          if (s.rows.isEmpty) text('لا يوجد.', style: small) else table(s),
        ],
        pw.SizedBox(height: 8),
        text(
          'صافي المبيعات = الفواتير − المرتجعات. التحصيل = المدفوع في الفواتير + التحصيلات، من غير الشيكات المرتدة.',
          style: small,
        ),
        pw.SizedBox(height: 50),
        pw.Row(
          children: [
            for (final s in [report.signatures.$1, report.signatures.$2]) ...[
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.only(top: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide()),
                  ),
                  child: text(s, textAlign: pw.TextAlign.center),
                ),
              ),
              if (s == report.signatures.$1) pw.SizedBox(width: 60),
            ],
          ],
        ),
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _pad(pw.Widget child) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  child: child,
);

/// Printed targets report: one rep ([repId]) with their documents, or all reps. Preview, print, share.
class TargetsPdfScreen extends StatelessWidget {
  const TargetsPdfScreen({super.key, required this.period, this.repId});

  final TargetPeriod period;
  final String? repId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final key = period.key;
    final label = period.label;
    return Scaffold(
      appBar: AppBar(
        title: Text(repId == null ? 'تقرير كل المناديب' : 'تقرير مندوب'),
      ),
      body: AsyncView<(Company, _Report)>(
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل التقرير.',
        load: () async {
          final (company, report) = await (
            app.documents.company(),
            repId == null
                ? app.users.targets(period).then(_allReport)
                : app.users.repTargets(repId!, period).then(_repReport),
          ).wait;
          return (company, report);
        },
        builder: (context, d) => PdfPreview(
          build: (format) => _buildPdf(d.$1, d.$2, label, format),
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: '${d.$2.title} ${d.$2.subtitle} $key.pdf',
        ),
      ),
    );
  }
}
