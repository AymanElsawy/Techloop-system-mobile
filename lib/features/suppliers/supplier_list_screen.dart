import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/inventory.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../documents/purchase_screen.dart';
import 'supplier_details_screen.dart';
import 'supplier_form.dart';

/// الموردين (managers only): search, active filter, new supplier.
class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final _ctl = PagedController();
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
          final saved = await showSupplierForm(
            context,
            onSave: repo.createSupplier,
          );
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
                          _debounce = Timer(
                            const Duration(milliseconds: 300),
                            () => setState(() => _query = v.trim()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _open(const PurchaseScreen()),
                      child: const Text('وارد جديد'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ChoiceBar<bool?>(
                  options: const {
                    true: 'الموردين النشطين',
                    false: 'الموقوفين',
                    null: 'الكل',
                  },
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<Supplier>(
              key: ValueKey((_query, _active)),
              controller: _ctl,
              load: (page) => context.app.inventory.suppliersPage(
                page,
                search: _query,
                active: _active,
              ),
              errorText: 'حدث خطأ أثناء تحميل الموردين.',
              emptyText: _query.isNotEmpty || _active != true
                  ? 'لا يوجد موردين مطابقين.'
                  : 'لا يوجد موردين بعد. أضف أول مورد، أو من فورم الوارد مباشرة.',
              itemBuilder: (context, s) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Tile(
                    title: s.name,
                    subtitle: [
                      ?s.company,
                      ?s.phone,
                      '${s.receipts} توريد',
                      if (s.lastPurchaseAt != null)
                        'آخر توريد ${shortDate(s.lastPurchaseAt!)}',
                      if (s.debt > 0) 'مديونية ${money(s.debt)}',
                    ].dotted(),
                    dimmed: !s.isActive,
                    badge: s.isActive
                        ? null
                        : const StatusBadge('موقوف', tone: Tone.danger),
                    trailing: money(s.totalPurchases),
                    onTap: () => _open(SupplierDetailsScreen(id: s.id)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
