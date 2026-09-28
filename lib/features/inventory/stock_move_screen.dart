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
import '../suppliers/supplier_select.dart';
import 'warehouse_details_screen.dart';

typedef _Option = ({String id, String label, num? available, num? lastCost});

class _Line {
  String? productId;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
}

typedef _Data = ({List<Warehouse> warehouses, List<Product> products, List<Supplier> suppliers});

/// Managers only. RECEIVE: goods bought from a supplier (with purchase price);
/// ISSUE: warehouse → rep custody; RETURN: rep custody → warehouse.
class StockMoveScreen extends StatelessWidget {
  const StockMoveScreen({super.key, required this.type, this.warehouseId, this.repId, this.productId, this.supplierId});

  final String type;
  final String? warehouseId;
  final String? repId;
  final String? productId;
  final String? supplierId;

  @override
  Widget build(BuildContext context) {
    final inv = context.app.inventory;
    final receive = type == 'RECEIVE';
    return Scaffold(
      appBar: AppBar(title: Text(receive ? 'وارد من مورد' : movementTypeLabels[type]!)),
      body: AsyncView<_Data>(
        refreshable: false,
        load: () async {
          final (w, p, s) = await (
            inv.warehouses(),
            receive ? inv.products(active: true) : Future.value(<Product>[]),
            receive ? inv.suppliers(active: true) : Future.value(<Supplier>[]),
          ).wait;
          return (warehouses: w.where((x) => x.isActive || x.id == warehouseId).toList(), products: p, suppliers: s);
        },
        builder: (context, d) => _Form(screen: this, data: d),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.screen, required this.data});

  final StockMoveScreen screen;
  final _Data data;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final s = widget.screen;
  late final bool _receive = s.type == 'RECEIVE';
  late String? _warehouseId = s.warehouseId;
  late String? _repId = s.repId;
  late String? _supplierId = s.supplierId;
  WarehouseDetails? _details;
  bool _loadingDetails = false;
  final _lines = [_Line()];
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (s.productId != null) {
      _lines.first.productId = s.productId;
      _defaultCost(_lines.first);
    }
    if (!_receive && _warehouseId != null) _loadDetails();
  }

  Future<void> _loadDetails() async {
    final id = _warehouseId!;
    setState(() => _loadingDetails = true);
    try {
      final d = await context.app.inventory.warehouse(id);
      if (mounted && id == _warehouseId) setState(() => _details = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'حدث خطأ أثناء تحميل المخزن.'));
    }
    if (mounted) setState(() => _loadingDetails = false);
  }

  /// Products that can be picked, with the quantity available at the source.
  List<_Option> get _options {
    if (_receive) {
      return [for (final p in widget.data.products) (id: p.id, label: p.label, available: null, lastCost: p.lastCost)];
    }
    final d = _details;
    if (d == null) return [];
    final rows = s.type == 'ISSUE' ? d.stock : (d.reps.where((r) => r.rep.id == _repId).firstOrNull?.custody ?? []);
    return [for (final r in rows) (id: r.productId, label: r.label, available: r.quantity, lastCost: null)];
  }

  _Option? _option(String? id) => _options.where((o) => o.id == id).firstOrNull;

  /// Receipt: default the purchase price to the product's last one.
  void _defaultCost(_Line l) {
    final last = widget.data.products.where((p) => p.id == l.productId).firstOrNull?.lastCost;
    if (_receive && last != null && l.cost.text.isEmpty) l.cost.text = '$last';
  }

  /// The rep or warehouse changed: the source stock is different.
  void _resetLines() {
    if (_receive) return;
    _lines
      ..clear()
      ..add(_Line());
  }

  num _qty(_Line l) => int.tryParse(l.qty.text) ?? 0;
  num _lineTotal(_Line l) => round2(_qty(l) * (num.tryParse(l.cost.text) ?? 0));
  num? _overBy(_Line l) {
    final a = _option(l.productId)?.available;
    return a != null && _qty(l) > a ? a : null;
  }

  bool get _canSubmit =>
      _warehouseId != null &&
      _lines.every(
        (l) =>
            l.productId != null &&
            _qty(l) >= 1 &&
            _overBy(l) == null &&
            (!_receive || num.tryParse(l.cost.text) != null),
      ) &&
      (_receive ? _supplierId != null : _repId != null);

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.move(_warehouseId!, s.type, {
        if (!_receive) 'repId': _repId,
        if (_receive) 'supplierId': _supplierId,
        'items': [
          for (final l in _lines)
            {'productId': l.productId, 'quantity': _qty(l), if (_receive) 'unitCost': num.parse(l.cost.text)},
        ],
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      // Opened from the warehouse page: go back to it (it reloads); otherwise show the warehouse.
      s.warehouseId != null
          ? Navigator.pop(context, true)
          : replace(context, WarehouseDetailsScreen(id: _warehouseId!));
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر حفظ الحركة. حاول مرة أخرى.');
      });
    }
  }

  /// Receipt: stock and prices now, and the average after saving (same weighted moving average as the backend).
  Widget? _costPreview(_Line l) {
    final p = widget.data.products.where((p) => p.id == l.productId).firstOrNull;
    if (p == null) return null;
    final oldQty = p.quantity < 0 ? 0 : p.quantity;
    final qty = _qty(l);
    final cost = num.tryParse(l.cost.text);
    final avg = p.avgCost;
    final newAvg = cost == null
        ? null
        : oldQty > 0 && avg != null
        ? round2((oldQty * avg + qty * cost) / (oldQty + qty))
        : cost;
    String m(num? v) => v == null ? '—' : money(v);
    final colors = context.colors;
    Widget cell(String label, String value, {bool strong = false}) => Text.rich(
      TextSpan(
        text: '$label: ',
        style: TextStyle(color: colors.muted),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: strong ? Theme.of(context).colorScheme.primary : null,
              fontWeight: strong ? FontWeight.w800 : null,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12.5),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.subtle, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          cell('الكمية', '${number(oldQty)} ← ${number(oldQty + qty)}'),
          cell('السعر القديم (متوسط)', m(avg)),
          cell('آخر شراء', [m(p.lastCost), ?p.lastSupplier?.name].dotted()),
          cell('المتوسط الجديد', m(newAvg), strong: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final options = _options;
    final grandTotal = round2(_lines.fold<num>(0, (sum, l) => sum + _lineTotal(l)));
    return PageList(
      children: [
        Text(switch (s.type) {
          'RECEIVE' => 'بضاعة مشتراة تدخل المخزن. سعر الشراء بيحدّث متوسط سعر الصنف وآخر سعر شراء.',
          'ISSUE' => 'بضاعة تخرج من المخزن إلى عهدة المندوب.',
          _ => 'بضاعة ترجع من عهدة المندوب إلى المخزن.',
        }, style: TextStyle(color: colors.muted)),
        FormCard(
          children: [
            Select<String>(
              label: 'المخزن *',
              value: _warehouseId,
              hint: 'اختر المخزن',
              items: {for (final w in widget.data.warehouses) w.id: w.name},
              onChanged: (v) {
                setState(() {
                  _warehouseId = v;
                  _details = null;
                  _repId = null;
                  _resetLines();
                });
                if (!_receive) _loadDetails();
              },
            ),
            if (_receive)
              SupplierSelect(
                suppliers: widget.data.suppliers,
                value: _supplierId,
                required: true,
                onChanged: (v) => setState(() => _supplierId = v),
              )
            else if (_details != null) ...[
              Select<String>(
                label: 'المندوب *',
                value: _repId,
                hint: 'اختر المندوب',
                items: {for (final r in _details!.reps) r.rep.id: r.rep.name},
                onChanged: (v) => setState(() {
                  _repId = v;
                  _resetLines();
                }),
              ),
              if (_details!.reps.isEmpty)
                const Note('لا يوجد مناديب تابعين لهذا المخزن. اربط المندوب بالمخزن من صفحة المستخدمين.'),
            ],
            if (_loadingDetails) const LinearProgressIndicator(),
          ],
        ),
        FormCard(
          title: 'الأصناف',
          children: [
            if (!_receive && _details != null && options.isEmpty && (s.type == 'ISSUE' || _repId != null))
              Text(
                s.type == 'ISSUE' ? 'المخزن فارغ.' : 'لا توجد بضاعة في عهدة هذا المندوب.',
                style: TextStyle(color: colors.muted),
              ),
            if (_receive && options.isEmpty)
              Text('لا توجد أصناف نشطة. أضف صنف من تبويب الأصناف.', style: TextStyle(color: colors.muted)),
            for (final (i, l) in _lines.indexed)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Select<String>(
                            label: 'الصنف',
                            value: l.productId,
                            hint: 'اختر الصنف',
                            // Products already chosen in other lines are hidden.
                            items: {
                              for (final o in options)
                                if (o.id == l.productId || !_lines.any((x) => x != l && x.productId == o.id))
                                  o.id: '${o.label}${o.available == null ? '' : ' — المتاح ${number(o.available!)}'}',
                            },
                            onChanged: (v) => setState(() {
                              l.productId = v;
                              _defaultCost(l);
                            }),
                          ),
                        ),
                        if (_lines.length > 1)
                          IconButton(
                            tooltip: 'حذف السطر ${i + 1}',
                            onPressed: () => setState(() => _lines.removeAt(i)),
                            icon: Icon(Icons.delete_outline, color: colors.danger),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Input(
                            label: 'الكمية',
                            controller: l.qty,
                            keyboard: TextInputType.number,
                            ltr: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_receive) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Input(
                              label: 'سعر الشراء',
                              controller: l.cost,
                              keyboard: Input.decimal,
                              ltr: true,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_receive) ...[
                      const SizedBox(height: 6),
                      Text('الإجمالي: ${money(_lineTotal(l))}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ?_costPreview(l),
                    ],
                    if (_overBy(l) != null)
                      Text('المتاح ${number(_overBy(l)!)} فقط.', style: TextStyle(color: colors.danger, fontSize: 12)),
                  ],
                ),
              ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صنف'),
                ),
                const Spacer(),
                if (_receive)
                  Text('إجمالي الفاتورة: ${money(grandTotal)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            if (_receive && _lines.any((l) => l.cost.text.isEmpty))
              Text('اكتب سعر الشراء لكل صنف.', style: TextStyle(color: colors.warningFg, fontSize: 12)),
          ],
        ),
        FormCard(
          children: [Input(label: 'ملاحظات', controller: _notes, hint: _receive ? 'رقم فاتورة المورد' : 'رقم الإذن')],
        ),
        SubmitButton(
          label: 'حفظ ${_receive ? 'الوارد' : movementTypeLabels[s.type]}',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
