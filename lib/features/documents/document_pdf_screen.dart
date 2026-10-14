import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';

/// What the A4 sheet renders; every document type is mapped into this one shape (same as the web print view).
class PrintDoc {
  const PrintDoc({
    required this.title,
    required this.number,
    required this.date,
    required this.cancelled,
    required this.partyLabel,
    required this.partyLines,
    required this.meta,
    required this.columns,
    required this.rows,
    required this.totals,
    required this.notes,
    required this.signatures,
  });

  final String title;
  final String number;
  final DateTime date;

  /// Cancel reason ('' when cancelled without one); null when active.
  final String? cancelled;
  final String partyLabel;
  final List<String> partyLines;
  final List<(String, String)> meta;
  final List<String> columns;
  final List<List<String>> rows;
  final List<(String, String)> totals;
  final String? notes;
  final (String, String) signatures;
}

List<String> _lines(List<String?> values) => [
  for (final v in values)
    if (v != null && v.isNotEmpty) v,
];

List<(String, String)> _payment(
  String? method,
  String? chequeNumber,
  DateTime? due,
) => [
  ('طريقة الدفع', methodLabel(method)),
  if (method == 'CHEQUE') ...[
    ('رقم الشيك', chequeNumber ?? '—'),
    ('تاريخ الاستحقاق', due == null ? '—' : shortDate(due)),
  ],
];

/// Loads a document of any type and maps it for printing.
Future<PrintDoc> loadPrintDoc(AppScope app, String type, String id) async {
  final title = documentTypeLabels[type]!;
  switch (type) {
    case 'SALE':
      final i = await app.sales.invoice(id);
      return PrintDoc(
        title: title,
        number: i.invoiceNumber,
        date: i.createdAt,
        cancelled: i.cancelled ? i.cancelReason ?? '' : null,
        partyLabel: 'العميل',
        partyLines: _lines([
          i.customer.name,
          i.customer.place,
          i.customer.phone,
        ]),
        meta: [
          ('المندوب / البائع', i.createdBy.name),
          ('المخزن', i.warehouse?.name ?? '—'),
          ..._payment(i.paymentMethod, i.chequeNumber, i.chequeDueDate),
          if (i.dueDate != null)
            ('تاريخ استحقاق الباقي', shortDate(i.dueDate!)),
        ],
        columns: [
          '#',
          'الصنف',
          'الوحدة',
          'الكمية',
          'سعر البيع',
          if (i.discount > 0) 'الخصم',
          'الإجمالي',
        ],
        rows: [
          for (final (n, it) in i.items.indexed)
            [
              '${n + 1}',
              it.name,
              unitLabels[it.unit] ?? '—',
              number(it.quantity),
              money(it.unitPrice),
              if (i.discount > 0)
                it.discountPercent > 0 ? '${number(it.discountPercent)}%' : '—',
              money(it.total),
            ],
        ],
        totals: [
          if (i.discount > 0) ('إجمالي الخصم', money(i.discount)),
          ('إجمالي الفاتورة', money(i.total)),
          ('المدفوع', money(i.paidAmount)),
          if (i.previousDebtPaid > 0)
            ('منه سداد مديونية سابقة', money(i.previousDebtPaid)),
          ('المتبقي', money(i.remaining)),
        ],
        notes: i.notes,
        signatures: ('توقيع المستلم (العميل)', 'توقيع المندوب'),
      );
    case 'SALE_RETURN':
      final r = await app.sales.salesReturn(id);
      return PrintDoc(
        title: title,
        number: '${r.number}',
        date: r.createdAt,
        cancelled: r.cancelled ? r.cancelReason ?? '' : null,
        partyLabel: 'العميل',
        partyLines: _lines([
          r.customer.name,
          r.customer.place,
          r.customer.phone,
        ]),
        meta: [
          ('من فاتورة بيع رقم', r.invoiceNumber),
          ('سجّله', r.createdBy.name),
          ('البضاعة رجعت', r.destination),
        ],
        columns: ['#', 'الصنف', 'الوحدة', 'الكمية', 'سعر البيع', 'الإجمالي'],
        rows: [
          for (final (n, it) in r.items.indexed)
            [
              '${n + 1}',
              it.name,
              unitLabels[it.unit] ?? '—',
              number(it.quantity),
              money(it.unitPrice),
              money(it.total),
            ],
        ],
        totals: [('إجمالي المرتجع (يخصم من حساب العميل)', money(r.total))],
        notes: r.notes,
        signatures: ('توقيع العميل', 'توقيع المستلم'),
      );
    case 'COLLECTION':
      final c = await app.sales.collection(id);
      return PrintDoc(
        title: title,
        number: c.receiptNumber,
        date: c.createdAt,
        cancelled: c.cancelled ? c.cancelReason ?? '' : null,
        partyLabel: 'استلمنا من السيد / السادة',
        partyLines: _lines([
          c.customer.name,
          c.customer.place,
          c.customer.phone,
        ]),
        meta: [
          ('المحصّل', c.createdBy.name),
          ..._payment(c.paymentMethod, c.chequeNumber, c.chequeDueDate),
        ],
        columns: ['البيان', 'المبلغ'],
        rows: [
          ['تحصيل من الحساب', money(c.amount)],
        ],
        totals: [('المبلغ المستلم', money(c.amount))],
        notes: c.notes,
        signatures: ('توقيع العميل', 'توقيع المحصّل'),
      );
    case 'DEPOSIT':
      final d = await app.treasury.deposit(id);
      return PrintDoc(
        title: title,
        number: '${d.number}',
        date: d.createdAt,
        cancelled: null,
        partyLabel: 'المندوب المورِّد',
        partyLines: [d.rep.name],
        meta: [('المستلم (الخزنة)', d.receivedBy.name)],
        columns: ['#', 'المستند', 'العميل', 'طريقة الدفع', 'المبلغ'],
        rows: [
          for (final (n, p) in d.payments.indexed)
            [
              '${n + 1}',
              '${p.isInvoice ? 'فاتورة' : 'إيصال'} ${p.number}',
              p.customer.name,
              '${methodLabel(p.paymentMethod)}${p.chequeNumber == null ? '' : ' (${p.chequeNumber})'}',
              money(p.amount),
            ],
          // The rep's expenses accepted in this handover come out of the cash.
          for (final (n, e) in d.expenses.indexed)
            [
              '${d.payments.length + n + 1}',
              'مصروف #${e.number}',
              e.category ?? '—',
              'نقدي',
              '− ${money(e.amount)}',
            ],
        ],
        totals: [('إجمالي المبلغ المورَّد', money(d.total))],
        notes: d.notes,
        signatures: ('توقيع المندوب', 'توقيع المستلم'),
      );
    default: // PURCHASE / ISSUE / RETURN
      final m = await app.inventory.movement(id);
      final purchase = type == 'PURCHASE';
      final qty = m.items.fold<num>(0, (s, i) => s + i.quantity);
      final sup = m.supplier;
      return PrintDoc(
        title: title,
        number: '${m.number ?? '—'}',
        date: m.createdAt,
        cancelled: null,
        partyLabel: purchase
            ? 'المورد'
            : (type == 'ISSUE' ? 'صُرف إلى المندوب' : 'مرتجع من المندوب'),
        partyLines: purchase
            ? _lines([sup?.name ?? '—', sup?.company, sup?.phone, sup?.address])
            : [m.rep?.name ?? '—'],
        meta: [
          ('المخزن', m.warehouse?.name ?? '—'),
          ('بواسطة', m.createdBy?.name ?? '—'),
        ],
        columns: purchase
            ? ['#', 'الصنف', 'الكمية', 'سعر الشراء', 'الإجمالي']
            : ['#', 'الصنف', 'الكمية'],
        rows: [
          for (final (n, i) in m.items.indexed)
            purchase
                ? [
                    '${n + 1}',
                    i.name,
                    number(i.quantity),
                    money(i.unitCost ?? 0),
                    money(i.quantity * (i.unitCost ?? 0)),
                  ]
                : ['${n + 1}', i.name, number(i.quantity)],
        ],
        totals: [
          ('إجمالي الكمية', number(qty)),
          if (purchase) ...[
            ('إجمالي الفاتورة', money(m.totalCost)),
            ('المدفوع', money(m.paid)),
            ('المتبقي (مديونية للمورد)', money(m.remaining)),
          ],
        ],
        notes: m.notes,
        signatures: purchase
            ? ('توقيع المورد', 'توقيع أمين المخزن')
            : ('توقيع المندوب', 'توقيع أمين المخزن'),
      );
  }
}

/// Arabic PDF fonts + a Text that renders Arabic and Latin correctly. Shared by every PDF in the app.
class PdfFonts {
  PdfFonts._(this.theme, this._latin, this._latinBold);

  final pw.ThemeData theme;
  final pw.Font _latin;
  final pw.Font _latinBold;
  static final _arabic = RegExp(r'[؀-ۿ]');

  // Noto Sans Arabic, not Cairo: with Cairo (and most Arabic Google fonts) the pdf package draws some
  // letters wrong, e.g. the isolated "ي" of "حيوي". It has no Latin, so text without Arabic letters
  // (names, phone numbers) uses Noto Sans; fallback fonts would reverse Latin inside Arabic text.
  static Future<PdfFonts> load() async => PdfFonts._(
    pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansArabicRegular(),
      bold: await PdfGoogleFonts.notoSansArabicBold(),
      fontFallback: [await PdfGoogleFonts.notoSansRegular()],
    ),
    await PdfGoogleFonts.notoSansRegular(),
    await PdfGoogleFonts.notoSansBold(),
  );

  // ponytail: the pdf package does not mirror brackets in right-to-left text, so they are swapped by hand.
  pw.Text text(String s, {pw.TextStyle? style, pw.TextAlign? textAlign}) =>
      _arabic.hasMatch(s)
      ? pw.Text(
          s
              .replaceAll('(', '\u0000')
              .replaceAll(')', '(')
              .replaceAll('\u0000', ')'),
          textAlign: textAlign,
          style: style,
        )
      : pw.Text(
          s,
          textAlign: textAlign,
          style: (style ?? const pw.TextStyle()).copyWith(
            font: _latin,
            fontBold: _latinBold,
          ),
        );
}

/// A4 PDF with the company header, in Arabic (right to left). Black on white so it prints well.
Future<Uint8List> buildDocumentPdf(
  Company company,
  PrintDoc doc,
  PdfPageFormat format,
) async {
  final fonts = await PdfFonts.load();
  final theme = fonts.theme;
  final text = fonts.text;
  const grey = PdfColors.grey700;
  const border = PdfColors.grey500;
  final small = const pw.TextStyle(fontSize: 9, color: grey);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget box(List<pw.Widget> children) => pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: border),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    ),
  );

  final companyLines = [
    ?company.address,
    if (company.phone != null) 'تليفون: ${company.phone}',
    if (company.taxNumber != null) 'الرقم الضريبي: ${company.taxNumber}',
    if (company.commercialRegister != null)
      'سجل تجاري: ${company.commercialRegister}',
  ];

  // pw.Table ignores text direction: reverse the columns so the first one sits on the right.
  final columns = doc.columns.reversed.toList();
  final rows = [for (final r in doc.rows) r.reversed.toList()];

  final pdf = pw.Document(
    title: '${doc.title} ${doc.number}',
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
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        buildForeground: doc.cancelled == null
            ? null
            : (_) => pw.Center(
                child: pw.Transform.rotateBox(
                  angle: 0.5,
                  child: text(
                    'ملغاة',
                    style: pw.TextStyle(
                      fontSize: 90,
                      color: PdfColors.red200,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
              '${company.name} — ${doc.title}${doc.number.isEmpty ? '' : ' رقم ${doc.number}'}${context.pagesCount > 1 ? ' — (${context.pageNumber}/${context.pagesCount})' : ''}',
              style: small,
            ),
          ],
        ),
      ),
      build: (context) => [
        // Company header
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
                    for (final l in companyLines) text(l, style: small),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  text(
                    doc.title,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (doc.number.isNotEmpty)
                    text('رقم: ${doc.number}', style: bold),
                  text(
                    'التاريخ: ${longDate(doc.date)} - ${time(doc.date)}',
                    style: small,
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        // Party + meta
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: box([
                text(doc.partyLabel, style: small),
                for (final (i, l) in doc.partyLines.indexed)
                  text(
                    l,
                    style: i == 0
                        ? pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          )
                        : null,
                  ),
              ]),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: box([
                for (final (k, v) in doc.meta)
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: text(k, style: const pw.TextStyle(color: grey)),
                      ),
                      text(v, style: bold),
                    ],
                  ),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [
            for (final c in columns)
              text(
                c,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
          ],
          data: [
            for (final r in rows)
              [
                for (final c in r)
                  text(c, style: const pw.TextStyle(fontSize: 10)),
              ],
          ],
          border: pw.TableBorder.all(color: border),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 4,
          ),
        ),
        pw.SizedBox(height: 10),
        // Totals on the left (end side in RTL)
        pw.Row(
          children: [
            pw.Spacer(),
            pw.Container(
              width: 220,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border),
              ),
              child: pw.Column(
                children: [
                  for (final (i, (k, v)) in doc.totals.indexed)
                    pw.Container(
                      color: i == doc.totals.length - 1
                          ? PdfColors.grey200
                          : null,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: text(
                              k,
                              style: i == doc.totals.length - 1 ? bold : null,
                            ),
                          ),
                          text(
                            v,
                            style: i == doc.totals.length - 1 ? bold : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (doc.notes != null) ...[
          pw.SizedBox(height: 10),
          box([text('ملاحظات: ${doc.notes}')]),
        ],
        if (doc.cancelled != null && doc.cancelled!.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          text(
            'سبب الإلغاء: ${doc.cancelled}',
            style: const pw.TextStyle(color: PdfColors.red700),
          ),
        ],
        pw.SizedBox(height: 50),
        pw.Row(
          children: [
            for (final s in [doc.signatures.$1, doc.signatures.$2]) ...[
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.only(top: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide()),
                  ),
                  child: text(s, textAlign: pw.TextAlign.center),
                ),
              ),
              if (s == doc.signatures.$1) pw.SizedBox(width: 60),
            ],
          ],
        ),
      ],
    ),
  );
  return pdf.save();
}

/// A4 print view of any document: preview, print, and share the PDF (e.g. WhatsApp).
class DocumentPdfScreen extends StatelessWidget {
  const DocumentPdfScreen({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: Text(documentTypeLabels[type] ?? 'مستند')),
      body: AsyncView<(Company, PrintDoc)>(
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل المستند.',
        load: () => (app.documents.company(), loadPrintDoc(app, type, id)).wait,
        builder: (context, d) => PdfPreview(
          build: (format) => buildDocumentPdf(d.$1, d.$2, format),
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: '${d.$2.title} ${d.$2.number}.pdf',
        ),
      ),
    );
  }
}

/// A PDF attachment (receipt / cheque) opened from an invoice or collection.
class PdfBytesScreen extends StatelessWidget {
  const PdfBytesScreen({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PdfPreview(
      build: (_) => bytes,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: '$title.pdf',
    ),
  );
}
