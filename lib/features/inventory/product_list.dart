import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'product_form_screen.dart';
import 'product_purchases_screen.dart';
import '../documents/purchase_screen.dart';

/// الأصناف: search, unit / status / low-stock filters. Managers edit, receive and delete; reps only read.
class ProductList extends StatefulWidget {
  const ProductList({super.key});

  @override
  State<ProductList> createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  final _ctl = PagedController();
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
              subtitle: const Text(
                'زوّد الكمية بسعر المورد الجديد، ومتوسط السعر يتحسب تلقائي.',
              ),
              onTap: () => Navigator.pop(context, const PurchaseScreen()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (screen != null) _open(screen);
  }

  /// The server refuses (409) a product with stock or history; it gets deactivated instead.
  Future<void> _delete(Product p) async {
    if (!await confirm(context, 'حذف الصنف', 'حذف "${p.name}"؟') || !mounted)
      return;
    try {
      await context.app.inventory.deleteProduct(p.id);
      _ctl.reload();
    } catch (e) {
      if (!mounted) return;
      toast(
        context,
        e is ApiException && e.status == 409
            ? 'الصنف ده عليه رصيد أو حركات، مينفعش يتحذف. أوقفه من التعديل بدل كده.'
            : errorMessage(e),
      );
    }
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
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () => setState(() => _query = v.trim()),
                        );
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
                        onSelected: (s) =>
                            setState(() => _unit = s ? u.key : null),
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
          child: PagedListView<Product>(
            key: ValueKey((_query, _unit, _active, _lowStock)),
            controller: _ctl,
            load: (page) => context.app.inventory.productsPage(
              page,
              search: _query,
              unit: _unit,
              active: _active,
              lowStock: _lowStock,
            ),
            errorText: 'حدث خطأ أثناء تحميل الأصناف.',
            emptyText: 'لا توجد أصناف مطابقة.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemBuilder: (context, p) => _ProductCard(
              product: p,
              onTap: manager
                  ? () => _open(ProductPurchasesScreen(id: p.id))
                  : () => _showDetails(context, p),
              onEdit: manager ? () => _open(ProductFormScreen(id: p.id)) : null,
              onReceive: manager && p.isActive
                  ? () => _open(PurchaseScreen(productId: p.id))
                  : null,
              onDelete: manager ? () => _delete(p) : null,
            ),
          ),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context, Product p) =>
      showModalBottomSheet<void>(
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
                ('سعر البيع', money(p.price)),
                if (p.lastCost != null) ('سعر الشراء', money(p.lastCost!)),
                ('الكمية الإجمالية', number(p.quantity)),
                (
                  'الصلاحية',
                  p.expiryDate == null ? '—' : longDate(p.expiryDate!),
                ),
                if (p.notes != null) ('ملاحظات', p.notes!),
              ],
            ),
          ),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    this.onEdit,
    this.onReceive,
    this.onDelete,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onReceive;
  final VoidCallback? onDelete;

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
                      child: Text(
                        p.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      'سعر البيع ${money(p.price)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                if (p.code != null || p.manufacturer != null)
                  Text([?p.code, ?p.manufacturer].dotted(), style: small),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'الكمية: ${number(p.quantity)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (p.isLowStock)
                      const StatusBadge('منخفضة', tone: Tone.warning),
                    if (expiry == 'expired')
                      const StatusBadge('منتهي', tone: Tone.danger),
                    if (expiry == 'soon')
                      const StatusBadge('قريب الانتهاء', tone: Tone.warning),
                    if (!p.isActive)
                      const StatusBadge('موقوف', tone: Tone.danger),
                    if (p.expiryDate != null)
                      Text(
                        'الصلاحية ${shortDate(p.expiryDate!)}',
                        style: small,
                      ),
                  ],
                ),
                if (p.avgCost != null || p.lastCost != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (p.lastCost != null)
                        'سعر الشراء ${money(p.lastCost!)}',
                      'متوسط سعر الشراء ${p.avgCost == null ? '—' : money(p.avgCost!)}',
                      ?p.lastSupplier?.name,
                      if (p.lastPurchaseAt != null)
                        shortDate(p.lastPurchaseAt!),
                    ].dotted(),
                    style: small,
                  ),
                ],
                if (onEdit != null || onReceive != null || onDelete != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onEdit != null)
                        TextButton(
                          onPressed: onEdit,
                          child: const Text('تعديل'),
                        ),
                      if (onReceive != null)
                        TextButton(
                          onPressed: onReceive,
                          child: const Text('وارد'),
                        ),
                      if (onDelete != null)
                        TextButton(
                          onPressed: onDelete,
                          child: const Text('حذف'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
