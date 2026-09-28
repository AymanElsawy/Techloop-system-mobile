import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/sales.dart';
import '../../data/repositories/sales_repository.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../documents/document_pdf_screen.dart';
import '../treasury/deposit_details_screen.dart';

/// Where the money of an invoice / collection is: with the rep, or in the treasury.
class DepositBadge extends StatelessWidget {
  const DepositBadge(this.deposit, {super.key});

  final DepositInfo deposit;

  @override
  Widget build(BuildContext context) {
    if (deposit.pending) return const StatusBadge('مع المندوب (لم يُسلَّم للخزنة)', tone: Tone.warning);
    if (deposit.depositId == null) return const StatusBadge('في الخزنة', tone: Tone.success);
    return InkWell(
      onTap: () => push(context, DepositDetailsScreen(id: deposit.depositId!)),
      child: StatusBadge('في الخزنة · استلام #${deposit.depositNumber}', tone: Tone.success),
    );
  }
}

/// "Print / PDF" button that opens the document's A4 PDF.
class PrintButton extends StatelessWidget {
  const PrintButton({super.key, required this.type, required this.id, this.label = 'طباعة / PDF'});

  final String type;
  final String id;
  final String label;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: () => push(context, DocumentPdfScreen(type: type, id: id)),
    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
    label: Text(label),
  );
}

/// Cancelled by X on date. Reason: ...
class CancelledNote extends StatelessWidget {
  const CancelledNote({super.key, required this.by, required this.at, required this.reason, this.verb = 'ألغاها'});

  final Ref? by;
  final DateTime? at;
  final String? reason;
  final String verb;

  @override
  Widget build(BuildContext context) => Note(
    '$verb ${by?.name ?? '—'}${at == null ? '' : ' بتاريخ ${longDate(at!)}'}. السبب: ${reason ?? '—'}',
    tone: Tone.danger,
  );
}

/// Items of an invoice or return: name, quantity × price, total.
class ItemsCard extends StatelessWidget {
  const ItemsCard({super.key, required this.items, this.footer});

  final List<LineItem> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'الأصناف',
      children: [
        for (final i in items)
          Tile(title: i.label, subtitle: '${number(i.quantity)} × ${money(i.unitPrice)}', trailing: money(i.total)),
        ?footer,
      ],
    );
  }
}

/// Runs a cancel with a reason dialog; returns the updated document or null.
Future<T?> cancelWithReason<T>(
  BuildContext context, {
  required String title,
  required String message,
  required Future<T> Function(String reason) cancel,
}) async {
  final reason = await askReason(context, title: title, message: message);
  if (reason == null) return null;
  try {
    return await cancel(reason);
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
    return null;
  }
}

/// Receipt / cheque attachments of an invoice or collection: view (fetched with the token) and upload.
class AttachmentsCard extends StatefulWidget {
  const AttachmentsCard({super.key, required this.base, required this.attachments, required this.onUploaded});

  /// '/invoices/:id' or '/collections/:id'.
  final String base;
  final List<Attachment> attachments;
  final VoidCallback onUploaded;

  @override
  State<AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends State<AttachmentsCard> {
  String _kind = 'RECEIPT';
  bool _uploading = false;
  String? _opening;

  Future<void> _upload() async {
    final repo = context.app.sales;
    final file = await pickAttachment(context);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await repo.upload(widget.base, _kind, file);
      widget.onUploaded();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e, 'تعذر رفع الملف.'));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _view(Attachment a) async {
    setState(() => _opening = a.id);
    try {
      final file = await context.app.sales.download(widget.base, a.id);
      if (!mounted) return;
      push(context, AttachmentViewer(title: attachmentKindLabels[a.kind] ?? a.originalName, file: file));
    } catch (_) {
      if (mounted) toast(context, 'تعذر تحميل الملف.');
    }
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'المرفقات',
      children: [
        for (final a in widget.attachments)
          Tile(
            leading: Icon(a.mimeType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
            title: '${attachmentKindLabels[a.kind] ?? a.kind} · ${a.originalName}',
            subtitle: '${a.uploadedBy?.name ?? ''}${a.uploadedAt == null ? '' : '، ${longDate(a.uploadedAt!)}'}',
            trailing: _opening == a.id ? '...' : 'عرض',
            onTap: _opening == null ? () => _view(a) : null,
          ),
        if (widget.attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('لا توجد مرفقات.', style: TextStyle(color: context.colors.muted)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Select<String>(
                  label: 'نوع المرفق',
                  value: _kind,
                  items: attachmentKindLabels,
                  onChanged: (v) => setState(() => _kind = v!),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file, size: 18),
                label: const Text('رفع'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-screen image, or the PDF viewer for PDFs.
class AttachmentViewer extends StatelessWidget {
  const AttachmentViewer({super.key, required this.title, required this.file});

  final String title;
  final ({Uint8List bytes, String contentType}) file;

  @override
  Widget build(BuildContext context) {
    if (file.contentType.contains('pdf')) return PdfBytesScreen(title: title, bytes: file.bytes);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: Colors.black,
      body: InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(file.bytes))),
    );
  }
}

/// Picked receipt + cheque images on a new invoice / collection form, uploaded after saving.
class NewAttachments extends StatelessWidget {
  const NewAttachments({
    super.key,
    required this.receipt,
    required this.cheque,
    required this.showCheque,
    required this.onChanged,
    required this.hint,
  });

  final UploadFile? receipt;
  final UploadFile? cheque;
  final bool showCheque;
  final void Function(String kind, UploadFile? file) onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    Widget slot(String kind, String label, UploadFile? file) => Row(
      children: [
        Expanded(
          child: Text(file == null ? '$label (اختياري)' : '$label: ${file.name}', overflow: TextOverflow.ellipsis),
        ),
        if (file != null)
          IconButton(tooltip: 'إزالة', onPressed: () => onChanged(kind, null), icon: const Icon(Icons.close))
        else
          OutlinedButton.icon(
            onPressed: () async {
              final f = await pickAttachment(context);
              if (f != null) onChanged(kind, f);
            },
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('إرفاق'),
          ),
      ],
    );
    return FormCard(
      title: 'المرفقات',
      children: [
        slot('RECEIPT', 'صورة الإيصال', receipt),
        if (showCheque) slot('CHEQUE', 'صورة الشيك', cheque),
        Text(hint, style: TextStyle(fontSize: 12, color: context.colors.muted)),
      ],
    );
  }
}

/// Uploads the picked files after the document was created. Returns false if any upload failed
/// (the document exists; files can be re-uploaded from its page).
Future<bool> uploadAll(SalesRepository repo, String base, Map<String, UploadFile?> files) async {
  try {
    for (final e in files.entries) {
      if (e.value != null) await repo.upload(base, e.key, e.value!);
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Payment method chips + cheque number / due date.
class PaymentFields extends StatelessWidget {
  const PaymentFields({
    super.key,
    required this.method,
    required this.onMethod,
    required this.chequeNumber,
    required this.chequeDue,
    required this.onChequeDue,
  });

  final String? method;
  final ValueChanged<String> onMethod;
  final TextEditingController chequeNumber;
  final DateTime? chequeDue;
  final ValueChanged<DateTime?> onChequeDue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('طريقة السداد *', style: TextStyle(color: context.colors.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in paymentMethods)
              ChoiceChip(label: Text(paymentMethodLabels[m]!), selected: method == m, onSelected: (_) => onMethod(m)),
          ],
        ),
        if (method == 'CHEQUE') ...[
          const SizedBox(height: 14),
          Input(label: 'رقم الشيك', controller: chequeNumber, ltr: true),
          const SizedBox(height: 14),
          DateField(label: 'تاريخ استحقاق الشيك', value: chequeDue, onChanged: onChequeDue),
        ],
      ],
    );
  }
}

/// Summary numbers in a light panel (form totals).
class SummaryPanel extends StatelessWidget {
  const SummaryPanel({super.key, required this.items});

  final List<(String, String, Color?)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(12)),
      child: Wrap(
        runSpacing: 10,
        children: [
          for (final (label, value, color) in items)
            FractionallySizedBox(
              widthFactor: 0.5,
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: c.muted),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
