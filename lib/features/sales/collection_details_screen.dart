import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/sales.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../customers/customer_details_screen.dart';
import 'sales_widgets.dart';

class CollectionDetailsScreen extends StatefulWidget {
  const CollectionDetailsScreen({super.key, required this.id, this.uploadFailed = false});

  final String id;

  /// Set by the collection form when it saved but a file upload failed.
  final bool uploadFailed;

  @override
  State<CollectionDetailsScreen> createState() => _CollectionDetailsScreenState();
}

class _CollectionDetailsScreenState extends State<CollectionDetailsScreen> {
  final _ctl = AsyncController<Collection>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة تحصيل')),
      body: AsyncView<Collection>(
        controller: _ctl,
        load: () => context.app.sales.collection(widget.id),
        errorText: 'حدث خطأ أثناء تحميل التحصيل.',
        builder: (context, col) => PageList(
          children: [
            if (widget.uploadFailed)
              const Note('تم حفظ التحصيل، لكن تعذر رفع المرفقات. ارفعها مرة أخرى من قسم المرفقات.'),
            PageHeader(
              title: 'إيصال رقم ${col.receiptNumber}',
              badge: col.cancelled ? const StatusBadge('ملغى', tone: Tone.danger) : DepositBadge(col.deposit),
              actions: [
                PrintButton(type: 'COLLECTION', id: col.id, label: 'طباعة إيصال / PDF'),
                if (context.isManager && !col.cancelled)
                  OutlinedButton(
                    onPressed: () async {
                      final repo = context.app.sales;
                      final updated = await cancelWithReason(
                        context,
                        title: 'إلغاء التحصيل',
                        message: 'الإلغاء يرجع المبلغ على مديونية العميل.',
                        cancel: (r) => repo.cancelCollection(col.id, r),
                      );
                      if (updated != null) _ctl.set(updated);
                    },
                    child: const Text('إلغاء التحصيل'),
                  ),
              ],
            ),
            if (col.cancelled)
              CancelledNote(by: col.cancelledBy, at: col.cancelledAt, reason: col.cancelReason, verb: 'ألغاه'),
            InfoCard(
              items: [
                ('العميل', col.customer.name),
                ('المندوب', col.createdBy.name),
                ('التاريخ', dateTime(col.createdAt)),
                ('المبلغ', money(col.amount)),
                ('طريقة السداد', methodLabel(col.paymentMethod)),
                if (col.paymentMethod == 'CHEQUE')
                  (
                    'الشيك',
                    'رقم ${col.chequeNumber ?? '—'}${col.chequeDueDate == null ? '' : ' · يستحق ${shortDate(col.chequeDueDate!)}'}',
                  ),
                if (col.notes != null) ('ملاحظات', col.notes!),
              ],
              footer: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => push(context, CustomerDetailsScreen(id: col.customer.id)),
                  child: const Text('صفحة العميل'),
                ),
              ),
            ),
            AttachmentsCard(base: '/collections/${col.id}', attachments: col.attachments, onUploaded: _ctl.reload),
          ],
        ),
      ),
    );
  }
}
