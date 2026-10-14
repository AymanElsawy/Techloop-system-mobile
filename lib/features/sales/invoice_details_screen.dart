import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/sales.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../customers/customer_details_screen.dart';
import 'return_form_screen.dart';
import 'sales_widgets.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  const InvoiceDetailsScreen({
    super.key,
    required this.id,
    this.uploadFailed = false,
  });

  final String id;

  /// Set by the invoice form when the invoice saved but a file upload failed.
  final bool uploadFailed;

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  final _ctl = AsyncController<Invoice>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة بيع')),
      body: AsyncView<Invoice>(
        controller: _ctl,
        load: () => context.app.sales.invoice(widget.id),
        errorText: 'حدث خطأ أثناء تحميل الفاتورة.',
        builder: _body,
      ),
    );
  }

  Widget _body(BuildContext context, Invoice inv) {
    final colors = context.colors;
    final manager = context.isManager;
    return PageList(
      children: [
        if (widget.uploadFailed)
          const Note(
            'تم حفظ الفاتورة، لكن تعذر رفع المرفقات. ارفعها مرة أخرى من قسم المرفقات.',
          ),
        PageHeader(
          title: 'فاتورة رقم ${inv.invoiceNumber}',
          badge: inv.cancelled
              ? const StatusBadge('ملغاة', tone: Tone.danger)
              : inv.paidAmount > 0
              ? DepositBadge(inv.deposit)
              : null,
          actions: [
            PrintButton(type: 'SALE', id: inv.id),
            if (!inv.cancelled)
              OutlinedButton(
                onPressed: () async {
                  await push(
                    context,
                    ReturnFormScreen(
                      customerId: inv.customer.id,
                      invoiceId: inv.id,
                    ),
                  );
                  _ctl.reload();
                },
                child: const Text('مرتجع من الفاتورة'),
              ),
            if (manager && !inv.cancelled)
              OutlinedButton(
                onPressed: () async {
                  final repo = context.app.sales;
                  final updated = await cancelWithReason(
                    context,
                    title: 'إلغاء الفاتورة',
                    message:
                        'الإلغاء يرجع الكميات للمخزون ويحذف المبلغ من رصيد العميل.',
                    cancel: (r) => repo.cancelInvoice(inv.id, r),
                  );
                  if (updated != null) _ctl.set(updated);
                },
                child: const Text('إلغاء الفاتورة'),
              ),
          ],
        ),
        if (inv.cancelled)
          CancelledNote(
            by: inv.cancelledBy,
            at: inv.cancelledAt,
            reason: inv.cancelReason,
          ),
        InfoCard(
          items: [
            ('العميل', inv.customer.name),
            ('المندوب', inv.createdBy.name),
            ('التاريخ', dateTime(inv.createdAt)),
            if (inv.warehouse != null) ('المخزن', inv.warehouse!.name),
          ],
          footer: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  push(context, CustomerDetailsScreen(id: inv.customer.id)),
              child: const Text('صفحة العميل'),
            ),
          ),
        ),
        ItemsCard(items: inv.items),
        StatGrid(
          children: [
            StatCard(
              label: 'إجمالي الفاتورة',
              value: money(inv.total),
              hint: inv.discount > 0 ? 'بعد خصم ${money(inv.discount)}' : null,
            ),
            StatCard(
              label: 'المدفوع · ${methodLabel(inv.paymentMethod)}',
              value: money(inv.paidAmount),
              hint: inv.paymentMethod == 'CHEQUE'
                  ? 'شيك رقم ${inv.chequeNumber ?? '—'}${inv.chequeDueDate == null ? '' : ' · يستحق ${shortDate(inv.chequeDueDate!)}'}'
                  : null,
            ),
            StatCard(
              label: 'المتبقي',
              value: money(inv.remaining),
              valueColor: colors.danger,
              hint: [
                if (inv.previousDebtPaid > 0)
                  '+ ${money(inv.previousDebtPaid)} دُفعت لسداد مديونية سابقة',
                if (inv.dueDate != null && inv.remaining > 0)
                  inv.dueDate!.isBefore(DateTime.now())
                      ? 'متأخرة · كانت مستحقة ${shortDate(inv.dueDate!)}'
                      : 'تستحق ${shortDate(inv.dueDate!)}',
              ].join('\n').nullIfEmpty,
            ),
          ],
        ),
        if (inv.notes != null) InfoCard(items: [('ملاحظات', inv.notes!)]),
        AttachmentsCard(
          base: '/invoices/${inv.id}',
          attachments: inv.attachments,
          onUploaded: _ctl.reload,
        ),
      ],
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
