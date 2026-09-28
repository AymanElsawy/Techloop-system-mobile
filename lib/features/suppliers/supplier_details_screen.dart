import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../documents/document_pdf_screen.dart';
import '../inventory/stock_move_screen.dart';
import 'supplier_form.dart';

typedef _Data = ({Supplier supplier, List<Movement> purchases});

/// Supplier info and everything bought from them.
class SupplierDetailsScreen extends StatefulWidget {
  const SupplierDetailsScreen({super.key, required this.id});

  final String id;

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  final _ctl = AsyncController<_Data>();

  Future<_Data> _load() async {
    final inv = context.app.inventory;
    final (s, m) = await (inv.supplier(widget.id), inv.movements(supplierId: widget.id, type: 'RECEIVE')).wait;
    return (supplier: s, purchases: m);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.app.inventory;
    return Scaffold(
      appBar: AppBar(title: const Text('المورد')),
      body: AsyncView<_Data>(
        controller: _ctl,
        load: _load,
        errorText: 'حدث خطأ أثناء تحميل المورد.',
        builder: (context, d) {
          final s = d.supplier;
          return PageList(
            children: [
              PageHeader(
                title: s.name,
                badge: s.isActive ? null : const StatusBadge('موقوف', tone: Tone.danger),
                actions: [
                  if (s.isActive)
                    FilledButton(
                      onPressed: () async {
                        await push(context, StockMoveScreen(type: 'RECEIVE', supplierId: s.id));
                        _ctl.reload();
                      },
                      child: const Text('وارد من المورد ده'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      final saved = await showSupplierForm(
                        context,
                        supplier: s,
                        onSave: (data) => repo.updateSupplier(s.id, data),
                      );
                      if (saved != null) _ctl.reload();
                    },
                    child: const Text('تعديل'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await repo.updateSupplier(s.id, {'isActive': !s.isActive});
                        _ctl.reload();
                      } catch (e) {
                        if (context.mounted) toast(context, errorMessage(e, 'تعذر حفظ المورد.'));
                      }
                    },
                    child: Text(s.isActive ? 'إيقاف المورد' : 'تفعيل المورد'),
                  ),
                ],
              ),
              InfoCard(
                items: [
                  ('الهاتف', s.phone ?? '—'),
                  ('الشركة', s.company ?? '—'),
                  ('العنوان', s.address ?? '—'),
                  ('مرات التوريد', '${s.receipts}'),
                  ('إجمالي المشتريات', money(s.totalPurchases)),
                  ('آخر توريد', s.lastPurchaseAt == null ? '—' : longDate(s.lastPurchaseAt!)),
                  if (s.notes != null) ('ملاحظات', s.notes!),
                ],
                footer: s.phone == null
                    ? null
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: () => openUrl(context, 'tel:${s.phone}'),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: const Text('اتصال'),
                        ),
                      ),
              ),
              SectionCard(
                title: 'المشتريات',
                empty: 'مفيش توريد من المورد ده لسه.',
                children: [
                  for (final m in d.purchases)
                    Tile(
                      title: '${shortDate(m.createdAt)} · ${m.warehouse?.name ?? '—'}',
                      subtitle: [
                        for (final i in m.items) '${i.name}: ${number(i.quantity)} × ${money(i.unitCost ?? 0)}',
                        ?m.notes,
                      ].join('\n'),
                      trailing: money(m.totalCost),
                      onTap: () => push(context, DocumentPdfScreen(type: 'PURCHASE', id: m.id)),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
