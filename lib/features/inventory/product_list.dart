import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import 'product_form_screen.dart';
import 'stock_move_screen.dart';

/// الأصناف: search, unit / status / low-stock filters. Managers edit and receive; reps only read.
class ProductList extends StatefulWidget {
  const ProductList({super.key});

  @override
  State<ProductList> createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  final _ctl = AsyncController<List<Product>>();
  Timer? _debounce;
  String _query = '';
  String? _unit;
  late bool? _active = context.isManager ? true : null;
  bool _lowStock = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  /// Brand-new product, or more stock of an existing one from another supplier (the receipt updates the average cost).
  Future<void> _addProduct() async {
    final screen = await showModalBottomSheet<Widget>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('صنف جديد'),
              subtitle: const Text('صنف أول مرة يدخل المخزن.'),
              onTap: () => Navigator.pop(context, const ProductFormScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('صنف موجود من مورد آخر'),
              subtitle: const Text('زوّد الكمية بسعر المورد الجديد، ومتوسط السعر يتحسب تلقائي.'),
              onTap: () => Navigator.pop(context, const StockMoveScreen(type: 'RECEIVE')),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (screen != null) _open(screen);
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'بحث بالاسم أو الكود أو الشركة',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
                      },
                    ),
                  ),
                  if (manager) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('صنف جديد'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('كمية منخفضة فقط'),
                      selected: _lowStock,
                      onSelected: (v) => setState(() => _lowStock = v),
                    ),
                    const SizedBox(width: 8),
                    for (final u in unitLabels.entries) ...[
                      ChoiceChip(
                        label: Text(u.value),
                        selected: _unit == u.key,
                        onSelected: (s) => setState(() => _unit = s ? u.key : null),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (manager)
                      ChoiceChip(
                        label: Text(
                          _active == true
                              ? 'النشطة'
                              : _active == false
                              ? 'الموقوفة'
                              : 'الكل',
                        ),
                        selected: _active != true,
                        // Cycles: active -> stopped -> all.
                        onSelected: (_) => setState(
                          () => _active = _active == true
                              ? false
                              : _active == false
                              ? null
                              : true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<Product>>(
            key: ValueKey((_query, _unit, _active, _lowStock)),
            controller: _ctl,
            load: () =>
                context.app.inventory.products(search: _query, unit: _unit, active: _active, lowStock: _lowStock),
            errorText: 'حدث خطأ أثناء تحميل الأصناف.',
            builder: (context, list) => list.isEmpty
                ? const PageList(children: [EmptyCard('لا توجد أصناف مطابقة.')])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ProductCard(
                      product: list[i],
                      onTap: manager
                          ? () => _open(ProductFormScreen(id: list[i].id))
                          : () => _showDetails(context, list[i]),
                      onReceive: manager && list[i].isActive
                          ? () => _open(StockMoveScreen(type: 'RECEIVE', productId: list[i].id))
                          : null,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context, Product p) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
        child: InfoCard(
          items: [
            ('الصنف', p.name),
            ('الكود', p.code ?? '—'),
            ('الشركة', p.manufacturer ?? '—'),
            ('السعر', money(p.price)),
            ('الكمية الإجمالية', number(p.quantity)),
            ('الصلاحية', p.expiryDate == null ? '—' : longDate(p.expiryDate!)),
            if (p.notes != null) ('ملاحظات', p.notes!),
          ],
        ),
      ),
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap, this.onReceive});

  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onReceive;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final colors = context.colors;
    final small = TextStyle(fontSize: 12, color: colors.muted);
    final expiry = p.expiryState();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: p.isActive ? 1 : 0.6,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(money(p.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                if (p.code != null || p.manufacturer != null) Text([?p.code, ?p.manufacturer].dotted(), style: small),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('الكمية: ${number(p.quantity)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (p.isLowStock) const StatusBadge('منخفضة', tone: Tone.warning),
                    if (expiry == 'expired') const StatusBadge('منتهي', tone: Tone.danger),
                    if (expiry == 'soon') const StatusBadge('قريب الانتهاء', tone: Tone.warning),
                    if (!p.isActive) const StatusBadge('موقوف', tone: Tone.danger),
                    if (p.expiryDate != null) Text('الصلاحية ${shortDate(p.expiryDate!)}', style: small),
                  ],
                ),
                if (p.avgCost != null || p.lastCost != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      'متوسط الشراء ${p.avgCost == null ? '—' : money(p.avgCost!)}',
                      if (p.lastCost != null) 'آخر شراء ${money(p.lastCost!)}',
                      ?p.lastSupplier?.name,
                      if (p.lastPurchaseAt != null) shortDate(p.lastPurchaseAt!),
                    ].dotted(),
                    style: small,
                  ),
                ],
                if (onReceive != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: onReceive,
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: const Text('وارد'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
