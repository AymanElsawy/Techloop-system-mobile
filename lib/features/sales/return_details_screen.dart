import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/sales.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import 'invoice_details_screen.dart';
import 'sales_widgets.dart';

/// One فاتورة مرتجع; managers can cancel it.
class ReturnDetailsScreen extends StatefulWidget {
  const ReturnDetailsScreen({super.key, required this.id});

  final String id;

  @override
  State<ReturnDetailsScreen> createState() => _ReturnDetailsScreenState();
}

class _ReturnDetailsScreenState extends State<ReturnDetailsScreen> {
  final _ctl = AsyncController<SalesReturn>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة مرتجع')),
      body: AsyncView<SalesReturn>(
        controller: _ctl,
        load: () => context.app.sales.salesReturn(widget.id),
        builder: (context, r) => PageList(
          children: [
            PageHeader(
              title: 'فاتورة مرتجع رقم ${r.number}',
              subtitle: r.customer.name,
              badge: r.cancelled
                  ? const StatusBadge('ملغاة', tone: Tone.danger)
                  : null,
              actions: [
                PrintButton(type: 'SALE_RETURN', id: r.id),
                if (context.isManager && !r.cancelled)
                  OutlinedButton(
                    onPressed: () async {
                      final repo = context.app.sales;
                      final updated = await cancelWithReason(
                        context,
                        title: 'إلغاء المرتجع',
                        message:
                            'إلغاء المرتجع بيرجع قيمته على مديونية العميل، وبيسحب البضاعة تاني من ${r.rep != null ? 'عهدة ${r.rep!.name}' : 'المخزن'}.',
                        cancel: (reason) => repo.cancelReturn(r.id, reason),
                      );
                      if (updated != null) _ctl.set(updated);
                    },
                    child: const Text('إلغاء المرتجع'),
                  ),
              ],
            ),
            if (r.cancelled)
              CancelledNote(
                by: r.cancelledBy,
                at: r.cancelledAt,
                reason: r.cancelReason,
                verb: 'ألغاه',
              ),
            InfoCard(
              items: [
                ('من فاتورة بيع', r.invoiceNumber),
                ('التاريخ', dateTime(r.createdAt)),
                ('سجّله', r.createdBy.name),
                ('البضاعة رجعت', r.destination),
                if (r.notes != null) ('ملاحظات', r.notes!),
              ],
              footer: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () =>
                      push(context, InvoiceDetailsScreen(id: r.invoiceId)),
                  child: const Text('فاتورة البيع'),
                ),
              ),
            ),
            ItemsCard(
              items: r.items,
              footer: Tile(
                title: 'إجمالي المرتجع (يخصم من حساب العميل)',
                trailing: money(r.total),
                trailingHint: r.cancelled ? 'ملغاة' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
