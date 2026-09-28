import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../inventory/stock_move_screen.dart';
import 'supplier_details_screen.dart';
import 'supplier_form.dart';

/// الموردين (managers only): search, active filter, new supplier.
class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final _ctl = AsyncController<List<Supplier>>();
  Timer? _debounce;
  String _query = '';
  bool? _active = true;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final repo = context.app.inventory;
          final saved = await showSupplierForm(context, onSave: repo.createSupplier);
          if (saved != null) _ctl.reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('مورد جديد'),
      ),
      body: Column(
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
                          hintText: 'بحث بالاسم أو الهاتف أو الشركة',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _open(const StockMoveScreen(type: 'RECEIVE')),
                      child: const Text('وارد جديد'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ChoiceBar<bool?>(
                  options: const {true: 'الموردين النشطين', false: 'الموقوفين', null: 'الكل'},
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Supplier>>(
              key: ValueKey((_query, _active)),
              controller: _ctl,
              load: () => context.app.inventory.suppliers(search: _query, active: _active),
              errorText: 'حدث خطأ أثناء تحميل الموردين.',
              builder: (context, list) => list.isEmpty
                  ? PageList(
                      children: [
                        EmptyCard(
                          _query.isNotEmpty || _active != true
                              ? 'لا يوجد موردين مطابقين.'
                              : 'لا يوجد موردين بعد. أضف أول مورد، أو من فورم الوارد مباشرة.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final s = list[i];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Tile(
                            title: s.name,
                            subtitle: [
                              ?s.company,
                              ?s.phone,
                              '${s.receipts} توريد',
                              if (s.lastPurchaseAt != null) 'آخر توريد ${shortDate(s.lastPurchaseAt!)}',
                            ].dotted(),
                            dimmed: !s.isActive,
                            badge: s.isActive ? null : const StatusBadge('موقوف', tone: Tone.danger),
                            trailing: money(s.totalPurchases),
                            onTap: () => _open(SupplierDetailsScreen(id: s.id)),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
