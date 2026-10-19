import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'custody_requests.dart';
import 'movement_list.dart';
import 'product_list.dart';
import '../documents/purchase_screen.dart';
import 'warehouse_details_screen.dart';

/// المخزن: warehouses (managers) or my custody (reps), products, custody requests, and the movements log.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.canOperateWarehouses;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            // Scrollable: each tab is as wide as its label, so none gets cut on a narrow phone.
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              tabs: [
                Tab(text: manager ? 'المخازن' : 'عهدتي'),
                const Tab(text: 'الأصناف'),
                const Tab(text: 'الطلبات'),
                const Tab(text: 'سجل الحركات'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                manager ? const _Warehouses() : const _MyStock(),
                const ProductList(),
                const CustodyRequestsView(),
                const MovementList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Warehouses extends StatefulWidget {
  const _Warehouses();

  @override
  State<_Warehouses> createState() => _WarehousesState();
}

class _WarehousesState extends State<_Warehouses> {
  final _ctl = AsyncController<List<Warehouse>>();

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  Future<void> _create() async {
    final repo = context.app.inventory;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NewWarehouseDialog(onSave: repo.createWarehouse),
    );
    if (created == true) _ctl.reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isAdmin = context.isManager;
    return AsyncView<List<Warehouse>>(
      controller: _ctl,
      load: context.app.inventory.warehouses,
      errorText: 'حدث خطأ أثناء تحميل المخازن.',
      builder: (context, list) => PageList(
        children: [
          if (isAdmin)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(const PurchaseScreen()),
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('وارد من مورد'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('مخزن جديد'),
                  ),
                ),
              ],
            ),
          if (list.isEmpty)
            const EmptyCard(
              'لا توجد مخازن بعد. أضف أول مخزن لتسجيل البضاعة الواردة.',
            ),
          for (final w in list)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(WarehouseDetailsScreen(id: w.id)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              w.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!w.isActive)
                            const StatusBadge('موقوف', tone: Tone.danger),
                        ],
                      ),
                      if (w.notes != null)
                        Text(
                          w.notes!,
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      Divider(height: 24, color: colors.border),
                      Row(
                        children: [
                          Expanded(
                            child: _Figure(
                              label: 'الكمية في المخزن',
                              value: number(w.totalQuantity),
                            ),
                          ),
                          Expanded(
                            child: _Figure(
                              label: 'المناديب',
                              value: '${w.repsCount}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.muted)),
      Text(
        value,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _NewWarehouseDialog extends StatefulWidget {
  const _NewWarehouseDialog({required this.onSave});

  final Future<Warehouse> Function(String name, String? notes) onSave;

  @override
  State<_NewWarehouseDialog> createState() => _NewWarehouseDialogState();
}

class _NewWarehouseDialogState extends State<_NewWarehouseDialog> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _name.text.trim(),
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر إضافة المخزن.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مخزن جديد'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Input(
              label: 'اسم المخزن',
              controller: _name,
              hint: 'مثلاً: القاهرة - الجيزة',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: 'العنوان أو أمين المخزن',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Note(_error!, tone: Tone.danger),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving || _name.text.trim().length < 2 ? null : _save,
          child: Text(_saving ? 'جاري الحفظ...' : 'إضافة المخزن'),
        ),
      ],
    );
  }
}

/// A rep's custody + their warehouse's main stock.
class _MyStock extends StatelessWidget {
  const _MyStock();

  @override
  Widget build(BuildContext context) {
    return AsyncView<MyStock>(
      load: context.app.inventory.myStock,
      errorText: 'حدث خطأ أثناء تحميل عهدتك.',
      builder: (context, s) => PageList(
        children: [
          if (s.warehouse == null)
            const Note(
              'لم يتم ربطك بمخزن بعد، لذلك لا يمكنك البيع. تواصل مع الإدارة.',
            )
          else
            Text(
              'تبيع من ${warehouseLabel(s.warehouse!.name)}. الفاتورة تخصم من عهدتك أولاً، والباقي من المخزن.',
              style: TextStyle(color: context.colors.muted),
            ),
          StockCard(
            title: 'عهدتي',
            rows: s.custody,
            empty: 'لا توجد بضاعة في عهدتك.',
          ),
          if (s.warehouse != null)
            StockCard(
              title: warehouseLabel(s.warehouse!.name),
              rows: s.warehouseStock,
              empty: 'المخزن فارغ.',
            ),
        ],
      ),
    );
  }
}

/// Product quantities with a total in the title bar.
class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.title,
    required this.rows,
    required this.empty,
    this.trailing,
  });

  final String title;
  final List<StockRow> rows;
  final String empty;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '$title · الإجمالي ${number(totalQuantity(rows))}',
      trailing: trailing,
      empty: empty,
      children: [
        for (final r in rows)
          Tile(title: r.label, subtitle: r.code, trailing: number(r.quantity)),
      ],
    );
  }
}
