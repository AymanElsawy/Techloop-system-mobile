import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../documents/document_pdf_screen.dart';
import '../documents/purchase_screen.dart';
import '../inventory/stock_move_screen.dart';
import '../sales/sales_widgets.dart';
import 'supplier_form.dart';
import 'supplier_payment_form.dart';

typedef _Data = ({
  Supplier supplier,
  List<Movement> purchases,
  List<SupplierPayment> payments,
});

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
    final (s, m, p) = await (
      inv.supplier(widget.id),
      // Receipts and supplier returns (the only movements with a supplier).
      inv.movements(supplierId: widget.id),
      inv.supplierPayments(widget.id),
    ).wait;
    return (supplier: s, purchases: m, payments: p);
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
          final actions = [
            if (s.isActive)
              FilledButton(
                onPressed: () async {
                  await push(context, PurchaseScreen(supplierId: s.id));
                  _ctl.reload();
                },
                child: const Text('وارد من المورد ده'),
              ),
            if (s.receipts > 0)
              OutlinedButton(
                onPressed: () async {
                  final saved = await push(
                    context,
                    StockMoveScreen(type: 'SUPPLIER_RETURN', supplierId: s.id),
                  );
                  if (saved != null) _ctl.reload();
                },
                child: const Text('مرتجع للمورد ده'),
              ),
            if (s.isActive && s.debt > 0)
              OutlinedButton(
                onPressed: () async {
                  final saved = await push(
                    context,
                    SupplierPaymentFormScreen(supplier: s),
                  );
                  if (saved != null) _ctl.reload();
                },
                child: const Text('تسجيل سداد'),
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
                  if (context.mounted)
                    toast(context, errorMessage(e, 'تعذر حفظ المورد.'));
                }
              },
              child: Text(s.isActive ? 'إيقاف المورد' : 'تفعيل المورد'),
            ),
            OutlinedButton(
              onPressed: () => copyLink(context, repo.supplierShareLink(s.id)),
              child: const Text('نسخ رابط المديونية'),
            ),
          ];
          return PageList(
            children: [
              PageHeader(
                title: s.name,
                badge: s.isActive
                    ? null
                    : const StatusBadge('موقوف', tone: Tone.danger),
              ),
              for (var i = 0; i < actions.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(child: actions[i]),
                      if (i + 1 < actions.length) ...[
                        const SizedBox(width: 8),
                        Expanded(child: actions[i + 1]),
                      ],
                    ],
                  ),
                ),
              StatGrid(
                children: [
                  StatCard(
                    // Negative: returns went beyond the debt, the supplier owes the company.
                    label: s.debt < 0
                        ? 'رصيد لينا عند المورد'
                        : 'المديونية الحالية',
                    value: money(s.debt.abs()),
                    valueColor: s.debt > 0
                        ? context.colors.danger
                        : context.colors.successFg,
                  ),
                  StatCard(
                    label: 'إجمالي المشتريات',
                    value: money(s.totalPurchases),
                  ),
                ],
              ),
              InfoCard(
                items: [
                  ('الهاتف', s.phone ?? '—'),
                  ('الشركة', s.company ?? '—'),
                  ('العنوان', s.address ?? '—'),
                  ('مرات التوريد', '${s.receipts}'),
                  (
                    'آخر توريد',
                    s.lastPurchaseAt == null
                        ? '—'
                        : longDate(s.lastPurchaseAt!),
                  ),
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
                title: 'المشتريات والمرتجعات',
                empty: 'مفيش توريد من المورد ده لسه.',
                children: [
                  for (final m in d.purchases)
                    _PurchaseTile(
                      m: m,
                      onTap: () => push(
                        context,
                        DocumentPdfScreen(type: m.documentType!, id: m.id),
                      ),
                      onCancel:
                          m.type != 'SUPPLIER_RETURN' || m.cancelledAt != null
                          ? null
                          : () async {
                              final updated = await cancelWithReason(
                                context,
                                title: 'إلغاء المرتجع',
                                message:
                                    'الإلغاء يرجع البضاعة للمخزن والمبلغ على مديونية المورد.',
                                cancel: (r) =>
                                    repo.cancelSupplierReturn(m.id, r),
                              );
                              if (updated != null) _ctl.reload();
                            },
                    ),
                ],
              ),
              SectionCard(
                title: 'مدفوعات السداد',
                empty: 'مفيش سداد للمورد ده لسه.',
                children: [
                  for (final p in d.payments)
                    Tile(
                      title: '#${p.number} · ${methodLabel(p.paymentMethod)}',
                      subtitle: p.isCancelled
                          ? 'السبب: ${p.cancelReason ?? '—'}'
                          : p.notes,
                      trailing: money(p.amount),
                      badge: p.isCancelled
                          ? const StatusBadge('ملغى', tone: Tone.danger)
                          : null,
                      dimmed: p.isCancelled,
                      onTap: p.isCancelled
                          ? null
                          : () async {
                              final updated = await cancelWithReason(
                                context,
                                title: 'إلغاء السداد',
                                message:
                                    'الإلغاء يرجع المبلغ على مديونية المورد.',
                                cancel: (r) =>
                                    repo.cancelSupplierPayment(p.id, r),
                              );
                              if (updated != null) _ctl.reload();
                            },
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

/// A purchase receipt row: item quantities/prices stand out in an accent color, and the
/// total is colored by whether it's fully paid.
class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.m, required this.onTap, this.onCancel});

  final Movement m;
  final VoidCallback onTap;

  /// Active supplier returns only.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final owed = m.remaining > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    '${m.type == 'SUPPLIER_RETURN' ? (m.cancelledAt != null ? 'مرتجع ملغى · ' : 'مرتجع · ') : ''}${shortDate(m.createdAt)} · ${m.warehouse?.name ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final i in m.items)
                    Text.rich(
                      TextSpan(
                        text: '${i.name}: ',
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                        children: [
                          TextSpan(
                            text:
                                '${number(i.quantity)} × ${money(i.unitCost ?? 0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (owed)
                    Text(
                      'الباقي على الفاتورة دي: ${money(m.remaining)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.danger,
                      ),
                    ),
                  if (m.cancelReason != null)
                    Text(
                      'سبب الإلغاء: ${m.cancelReason}',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  if (m.notes != null)
                    Text(
                      m.notes!,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${m.type == 'SUPPLIER_RETURN' ? '− ' : ''}${money(m.totalCost)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: owed ? c.danger : c.successFg,
                  ),
                ),
                if (owed)
                  Text(
                    'مدفوع ${money(m.paid)}',
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
              ],
            ),
            if (onCancel != null)
              IconButton(
                tooltip: 'إلغاء المرتجع',
                onPressed: onCancel,
                icon: Icon(Icons.cancel_outlined, color: c.danger),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left, size: 20, color: c.muted),
          ],
        ),
      ),
    );
  }
}
