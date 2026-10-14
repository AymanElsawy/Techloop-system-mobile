import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../documents/document_pdf_screen.dart';
import '../suppliers/supplier_details_screen.dart';
import 'product_form_screen.dart';
import 'stock_move_screen.dart';

typedef _Data = ({Product product, PurchaseHistory history});

/// A product's purchase history from every supplier, with average prices (managers only).
class ProductPurchasesScreen extends StatefulWidget {
  const ProductPurchasesScreen({super.key, required this.id});

  final String id;

  @override
  State<ProductPurchasesScreen> createState() => _ProductPurchasesScreenState();
}

class _ProductPurchasesScreenState extends State<ProductPurchasesScreen> {
  final _ctl = AsyncController<_Data>();

  Future<_Data> _load() async {
    final inv = context.app.inventory;
    final (p, m) = await (
      inv.product(widget.id),
      inv.movements(type: 'RECEIVE', productId: widget.id),
    ).wait;
    return (product: p, history: PurchaseHistory(m, widget.id));
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  @override
  Widget build(BuildContext context) {
    String cost(num? v) => v == null ? '—' : money(v);
    return Scaffold(
      appBar: AppBar(title: const Text('مشتريات الصنف')),
      body: AsyncView<_Data>(
        controller: _ctl,
        load: _load,
        errorText: 'حدث خطأ أثناء التحميل.',
        builder: (context, d) {
          final p = d.product;
          final h = d.history;
          return PageList(
            children: [
              PageHeader(
                title: p.label,
                badge: p.isActive
                    ? null
                    : const StatusBadge('موقوف', tone: Tone.danger),
              ),
              Row(
                children: [
                  if (p.isActive) ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _open(
                          StockMoveScreen(type: 'RECEIVE', productId: p.id),
                        ),
                        child: const Text('وارد'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _open(ProductFormScreen(id: p.id)),
                      child: const Text('تعديل'),
                    ),
                  ),
                ],
              ),
              StatGrid(
                children: [
                  StatCard(label: 'الكمية الحالية', value: number(p.quantity)),
                  StatCard(label: 'سعر البيع', value: money(p.price)),
                  StatCard(label: 'سعر الشراء', value: cost(p.lastCost)),
                  StatCard(
                    label: 'متوسط سعر الشراء',
                    value: cost(p.avgCost),
                    hint: 'للمخزون الحالي',
                  ),
                ],
              ),
              InfoCard(
                items: [
                  ('عدد مرات الشراء', '${h.lines.length}'),
                  ('الكمية المشتراة', number(h.quantity)),
                  ('إجمالي المشتريات', money(h.total)),
                  ('متوسط كل المشتريات', cost(h.avgCost)),
                  ('أقل / أعلى سعر', '${cost(h.minCost)} / ${cost(h.maxCost)}'),
                ],
              ),
              SectionCard(
                title: 'حسب المورد',
                empty: 'مفيش مشتريات للصنف ده لسه.',
                children: [
                  for (final s in h.suppliers)
                    Tile(
                      title: s.supplier?.name ?? '—',
                      subtitle: [
                        '${s.count} مرة',
                        'كمية ${number(s.quantity)}',
                        'آخر سعر ${money(s.lastCost)}',
                        shortDate(s.lastDate),
                      ].dotted(),
                      trailing: money(s.avgCost),
                      trailingHint: 'متوسط · ${money(s.total)}',
                      onTap: s.supplier == null
                          ? null
                          : () => _open(
                              SupplierDetailsScreen(id: s.supplier!.id),
                            ),
                    ),
                ],
              ),
              SectionCard(
                title: 'كل عمليات الشراء',
                empty: 'مفيش مشتريات للصنف ده لسه.',
                children: [
                  for (final l in h.lines)
                    Tile(
                      title:
                          '${l.movement.supplier?.name ?? '—'} · #${l.movement.number ?? '—'}',
                      subtitle: [
                        dateTime(l.movement.createdAt),
                        ?l.movement.warehouse?.name,
                        '${number(l.quantity)} × ${money(l.unitCost)}',
                      ].dotted(),
                      trailing: money(l.total),
                      onTap: () => push(
                        context,
                        DocumentPdfScreen(type: 'PURCHASE', id: l.movement.id),
                      ),
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
