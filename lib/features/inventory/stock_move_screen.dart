import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
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
/// TRANSFER: warehouse → another warehouse. Receipts from suppliers use `PurchaseScreen`.
class StockMoveScreen extends StatelessWidget {
  const StockMoveScreen({
    super.key,
    required this.type,
    this.warehouseId,
    this.repId,
  });

  final String type;
  final String? warehouseId;
  final String? repId;

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

  /// ISSUE and TRANSFER take from the warehouse's main stock.
  bool get _fromMainStock => s.type == 'ISSUE' || _transfer;

  /// Products that can be picked, with the quantity available at the source.
  List<_Option> get _options {
    final d = _details;
    if (d == null) return [];
    final rows = _fromMainStock
        ? d.stock
        : (d.reps.where((r) => r.rep.id == _repId).firstOrNull?.custody ?? []);
    return [
      for (final r in rows)
        (id: r.productId, label: r.label, available: r.quantity),
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
          : _repId != null);

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.move(_warehouseId!, s.type, {
        if (!_transfer) 'repId': _repId,
        if (_transfer) 'toWarehouseId': _toWarehouseId,
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
          _ => 'بضاعة ترجع من عهدة المندوب إلى المخزن.',
        }, style: TextStyle(color: colors.muted)),
        FormCard(
          children: [
            Select<String>(
              label: 'المخزن *',
              value: _warehouseId,
              hint: 'اختر المخزن',
              items: {for (final w in widget.warehouses) w.id: w.name},
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
            if (_transfer)
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
                _fromMainStock
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
          ],
        ),
        FormCard(
          children: [
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: _transfer ? 'سبب التحويل' : 'رقم الإذن',
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
