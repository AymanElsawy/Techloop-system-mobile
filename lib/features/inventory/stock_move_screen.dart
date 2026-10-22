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

typedef _Option = ({String id, String label, num available});

class _Line {
  String? productId;
  final qty = TextEditingController(text: '1');
}

/// Managers only. ISSUE: warehouse → rep custody; RETURN: rep custody → warehouse;
/// TRANSFER: warehouse → another warehouse; SUPPLIER_RETURN: warehouse → back to the supplier,
/// its value off the supplier debt. Receipts from suppliers use `PurchaseScreen`.
class StockMoveScreen extends StatelessWidget {
  const StockMoveScreen({
    super.key,
    required this.type,
    this.warehouseId,
    this.repId,
    this.supplierId,
  });

  final String type;
  final String? warehouseId;
  final String? repId;
  final String? supplierId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(movementTypeLabels[type]!)),
      body: AsyncView<List<Warehouse>>(
        refreshable: false,
        load: () async => (await context.app.inventory.warehouses())
            .where((x) => x.isActive || x.id == warehouseId)
            .toList(),
        builder: (context, w) => _Form(screen: this, warehouses: w),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.screen, required this.warehouses});

  final StockMoveScreen screen;
  final List<Warehouse> warehouses;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final s = widget.screen;
  late final bool _transfer = s.type == 'TRANSFER';
  String? _toWarehouseId; // TRANSFER only
  late final bool _supplierReturn = s.type == 'SUPPLIER_RETURN';
  late String? _supplierId = s.supplierId;
  List<Supplier> _suppliers = [];

  /// SUPPLIER_RETURN: productId -> what's left of it from this supplier and its price (set by the server).
  Map<String, Returnable>? _returnable; // null while loading
  late String? _warehouseId = s.warehouseId;
  late String? _repId = s.repId;
  WarehouseDetails? _details;
  bool _loadingDetails = false;
  final _lines = [_Line()];
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_warehouseId != null) _loadDetails();
    if (_supplierReturn) {
      _loadSuppliers();
      if (_supplierId != null) _loadReturnable();
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final list = await context.app.inventory.suppliers();
      if (mounted) setState(() => _suppliers = list);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = errorMessage(e, 'حدث خطأ أثناء تحميل الموردين.'),
        );
      }
    }
  }

  Future<void> _loadReturnable() async {
    final id = _supplierId!;
    try {
      final list = await context.app.inventory.returnable(id);
      if (mounted && id == _supplierId) {
        setState(() => _returnable = {for (final r in list) r.productId: r});
        // One warehouse to return from: picked on its own.
        final only = _sourceWarehouses;
        if (_warehouseId == null && only.length == 1) {
          setState(() => _warehouseId = only.single.id);
          _loadDetails();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = errorMessage(e, 'حدث خطأ أثناء تحميل بضاعة المورد.'),
        );
      }
    }
  }

  Future<void> _loadDetails() async {
    final id = _warehouseId!;
    setState(() => _loadingDetails = true);
    try {
      final d = await context.app.inventory.warehouse(id);
      if (mounted && id == _warehouseId) setState(() => _details = d);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e, 'حدث خطأ أثناء تحميل المخزن.'));
      }
    }
    if (mounted) setState(() => _loadingDetails = false);
  }

  /// SUPPLIER_RETURN: only the warehouses this supplier delivered to (of what's still returnable).
  List<Warehouse> get _sourceWarehouses {
    if (!_supplierReturn) return widget.warehouses;
    final ids = {for (final r in (_returnable ?? {}).values) ...r.warehouseIds};
    return [
      for (final w in widget.warehouses)
        if (ids.contains(w.id)) w,
    ];
  }

  /// ISSUE, TRANSFER and SUPPLIER_RETURN take from the warehouse's main stock.
  bool get _fromMainStock => s.type == 'ISSUE' || _transfer || _supplierReturn;

  /// Products that can be picked, with the quantity available at the source.
  List<_Option> get _options {
    final d = _details;
    if (d == null) return [];
    final rows = _fromMainStock
        ? d.stock
        : (d.reps.where((r) => r.rep.id == _repId).firstOrNull?.custody ?? []);
    if (!_supplierReturn) {
      return [
        for (final r in rows)
          (id: r.productId, label: r.label, available: r.quantity),
      ];
    }
    // Only what was bought from this supplier, up to what's left of it here.
    return [
      for (final r in rows)
        if (_returnable?[r.productId] case final left?)
          (
            id: r.productId,
            label: r.label,
            available: r.quantity < left.quantity ? r.quantity : left.quantity,
          ),
    ];
  }

  _Option? _option(String? id) => _options.where((o) => o.id == id).firstOrNull;

  /// The rep or warehouse changed: the source stock is different.
  void _resetLines() {
    _lines
      ..clear()
      ..add(_Line());
  }

  num _qty(_Line l) => int.tryParse(l.qty.text) ?? 0;
  num? _cost(_Line l) => _returnable?[l.productId]?.unitCost;
  num get _returnTotal =>
      round2(_lines.fold<num>(0, (s, l) => s + _qty(l) * (_cost(l) ?? 0)));
  num? _overBy(_Line l) {
    final a = _option(l.productId)?.available;
    return a != null && _qty(l) > a ? a : null;
  }

  bool get _canSubmit =>
      _warehouseId != null &&
      _lines.every(
        (l) => l.productId != null && _qty(l) >= 1 && _overBy(l) == null,
      ) &&
      (_transfer
          ? _toWarehouseId != null && _toWarehouseId != _warehouseId
          : _supplierReturn
          ? _supplierId != null
          : _repId != null);

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.move(_warehouseId!, s.type, {
        if (!_transfer && !_supplierReturn) 'repId': _repId,
        if (_transfer) 'toWarehouseId': _toWarehouseId,
        if (_supplierReturn) 'supplierId': _supplierId,
        'items': [
          for (final l in _lines)
            {'productId': l.productId, 'quantity': _qty(l)},
        ],
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر حفظ الحركة. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final options = _options;
    return PageList(
      children: [
        Text(switch (s.type) {
          'ISSUE' => 'بضاعة تخرج من المخزن إلى عهدة المندوب.',
          'TRANSFER' => 'بضاعة تتنقل من المخزن ده لمخزن تاني.',
          'SUPPLIER_RETURN' =>
            'بضاعة ترجع من المخزن للمورد، وقيمتها بتتخصم من مديونية المورد.',
          _ => 'بضاعة ترجع من عهدة المندوب إلى المخزن.',
        }, style: TextStyle(color: colors.muted)),
        FormCard(
          children: [
            Select<String>(
              label: 'المخزن *',
              value: _sourceWarehouses.any((w) => w.id == _warehouseId)
                  ? _warehouseId
                  : null,
              hint: 'اختر المخزن',
              items: {for (final w in _sourceWarehouses) w.id: w.name},
              onChanged: (v) {
                setState(() {
                  _warehouseId = v;
                  _details = null;
                  _repId = null;
                  _resetLines();
                });
                _loadDetails();
              },
            ),
            if (_supplierReturn &&
                _supplierId != null &&
                _returnable != null &&
                _sourceWarehouses.isEmpty)
              const Note('مفيش بضاعة باقية من المورد ده ترجع له.'),
            if (_supplierReturn)
              Select<String>(
                label: 'المورد *',
                value: _suppliers.any((x) => x.id == _supplierId)
                    ? _supplierId
                    : null,
                hint: 'اختر المورد',
                items: {for (final x in _suppliers) x.id: x.name},
                onChanged: (v) {
                  setState(() {
                    _supplierId = v;
                    _returnable = null;
                    _warehouseId = null;
                    _details = null;
                    _resetLines();
                  });
                  _loadReturnable();
                },
              )
            else if (_transfer)
              Select<String>(
                label: 'إلى مخزن *',
                value: _toWarehouseId,
                hint: 'اختر المخزن',
                items: {
                  for (final w in widget.warehouses)
                    if (w.id != _warehouseId && w.isActive) w.id: w.name,
                },
                onChanged: (v) => setState(() => _toWarehouseId = v),
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
                const Note(
                  'لا يوجد مناديب تابعين لهذا المخزن. اربط المندوب بالمخزن من صفحة المستخدمين.',
                ),
            ],
            if (_loadingDetails) const LinearProgressIndicator(),
          ],
        ),
        FormCard(
          title: 'الأصناف',
          children: [
            if (_details != null &&
                options.isEmpty &&
                (_fromMainStock || _repId != null))
              Text(
                _supplierReturn
                    ? (_supplierId == null
                          ? 'اختار المورد الأول.'
                          : 'مفيش بضاعة من المورد ده في المخزن ده.')
                    : _fromMainStock
                    ? 'المخزن فارغ.'
                    : 'لا توجد بضاعة في عهدة هذا المندوب.',
                style: TextStyle(color: colors.muted),
              ),
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
                                if (o.id == l.productId ||
                                    !_lines.any(
                                      (x) => x != l && x.productId == o.id,
                                    ))
                                  o.id:
                                      '${o.label} — المتاح ${number(o.available)}',
                            },
                            onChanged: (v) => setState(() => l.productId = v),
                          ),
                        ),
                        if (_lines.length > 1)
                          IconButton(
                            tooltip: 'حذف السطر ${i + 1}',
                            onPressed: () => setState(() => _lines.removeAt(i)),
                            icon: Icon(
                              Icons.delete_outline,
                              color: colors.danger,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Input(
                      label: 'الكمية',
                      controller: l.qty,
                      keyboard: TextInputType.number,
                      ltr: true,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_supplierReturn && _cost(l) != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'سعر الشراء: ${money(_cost(l)!)}',
                        style: TextStyle(color: colors.muted),
                      ),
                    ],
                    if (_overBy(l) != null)
                      Text(
                        'المتاح ${number(_overBy(l)!)} فقط.',
                        style: TextStyle(color: colors.danger, fontSize: 12),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ),
            if (_supplierReturn)
              Text(
                'إجمالي المرتجع (يتخصم من مديونية المورد): ${money(_returnTotal)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
        ),
        FormCard(
          children: [
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: _transfer
                  ? 'سبب التحويل'
                  : _supplierReturn
                  ? 'سبب المرتجع'
                  : 'رقم الإذن',
            ),
          ],
        ),
        SubmitButton(
          label: 'حفظ ${movementTypeLabels[s.type]}',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
