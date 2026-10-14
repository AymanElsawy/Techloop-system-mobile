import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import 'inventory_screen.dart';
import 'movement_list.dart';
import 'stock_count_screen.dart';
import 'stock_move_screen.dart';

/// One warehouse: main stock, reps with their custody, stock actions, edit / stop. Managers only.
class WarehouseDetailsScreen extends StatefulWidget {
  const WarehouseDetailsScreen({super.key, required this.id});

  final String id;

  @override
  State<WarehouseDetailsScreen> createState() => _WarehouseDetailsScreenState();
}

class _WarehouseDetailsScreenState extends State<WarehouseDetailsScreen> {
  final _ctl = AsyncController<WarehouseDetails>();

  Future<void> _move(String type, {String? repId}) async {
    await push(
      context,
      StockMoveScreen(type: type, warehouseId: widget.id, repId: repId),
    );
    _ctl.reload();
  }

  Future<void> _save(WarehouseDetails d, Map<String, Object?> data) async {
    try {
      final w = await context.app.inventory.updateWarehouse(widget.id, data);
      _ctl.set(WarehouseDetails.copy(d, w));
    } catch (e) {
      if (mounted) toast(context, errorMessage(e, 'تعذر حفظ المخزن.'));
    }
  }

  Future<void> _edit(WarehouseDetails d) async {
    final name = TextEditingController(text: d.warehouse.name);
    final notes = TextEditingController(text: d.warehouse.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل المخزن'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'اسم المخزن *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().length >= 2) {
      _save(d, {
        'name': name.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المخزن')),
      body: AsyncView<WarehouseDetails>(
        controller: _ctl,
        load: () => context.app.inventory.warehouse(widget.id),
        errorText: 'حدث خطأ أثناء تحميل المخزن.',
        builder: (context, d) {
          final w = d.warehouse;
          final colors = context.colors;
          final isAdmin = context.isManager;
          return PageList(
            children: [
              PageHeader(
                title: w.name,
                subtitle: w.notes,
                badge: w.isActive
                    ? null
                    : const StatusBadge('موقوف', tone: Tone.danger),
                actions: [
                  if (w.isActive) ...[
                    if (isAdmin)
                      FilledButton(
                        onPressed: () => _move('RECEIVE'),
                        child: const Text('وارد من مورد'),
                      ),
                    FilledButton(
                      onPressed: () => _move('ISSUE'),
                      child: const Text('صرف لمندوب'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: () => _move('RETURN'),
                    child: const Text('مرتجع من مندوب'),
                  ),
                  if (isAdmin && w.isActive) ...[
                    OutlinedButton(
                      onPressed: () => _move('TRANSFER'),
                      child: const Text('تحويل لمخزن'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await push(
                          context,
                          StockCountScreen(warehouseId: widget.id),
                        );
                        _ctl.reload();
                      },
                      child: const Text('جرد'),
                    ),
                  ],
                  if (isAdmin)
                    PopupMenuButton<String>(
                      tooltip: 'المزيد',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (v) => v == 'edit'
                          ? _edit(d)
                          : _save(d, {'isActive': !w.isActive}),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            w.isActive ? 'إيقاف المخزن' : 'تفعيل المخزن',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              StockCard(
                title: 'رصيد المخزن',
                rows: d.stock,
                empty: 'المخزن فارغ. سجّل "وارد للمخزن" لإضافة بضاعة.',
              ),
              Text(
                'عُهد المناديب',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'المندوب يتربط بالمخزن من صفحة المستخدمين.',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              if (d.reps.isEmpty)
                const EmptyCard('لا يوجد مناديب تابعين لهذا المخزن.'),
              for (final r in d.reps)
                StockCard(
                  title: r.rep.name,
                  rows: r.custody,
                  empty: 'لا توجد بضاعة في عهدته.',
                  trailing: PopupMenuButton<String>(
                    tooltip: 'إجراءات ${r.rep.name}',
                    onSelected: (v) => v == 'moves'
                        ? push(context, MovementListScreen(repId: r.rep.id))
                        : _move(v, repId: r.rep.id),
                    itemBuilder: (_) => [
                      if (w.isActive)
                        const PopupMenuItem(value: 'ISSUE', child: Text('صرف')),
                      if (r.custody.isNotEmpty)
                        const PopupMenuItem(
                          value: 'RETURN',
                          child: Text('مرتجع'),
                        ),
                      const PopupMenuItem(
                        value: 'moves',
                        child: Text('الحركات'),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () =>
                    push(context, MovementListScreen(warehouseId: w.id)),
                icon: const Icon(Icons.history),
                label: const Text('عرض سجل حركات هذا المخزن'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The movements log as its own page (filtered by warehouse or rep).
class MovementListScreen extends StatelessWidget {
  const MovementListScreen({super.key, this.warehouseId, this.repId});

  final String? warehouseId;
  final String? repId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سجل الحركات')),
    body: MovementList(warehouseId: warehouseId, repId: repId),
  );
}
