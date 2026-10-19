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

String _norm(String name) => name.trim().toLowerCase();

class _Line {
  _Line([this.supplierId]);

  final name = TextEditingController();
  final focus = FocusNode();
  String? supplierId;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  // New product only.
  final price = TextEditingController();
  String? unit;

  void dispose() {
    for (final c in [name, qty, cost, price]) {
      c.dispose();
    }
    focus.dispose();
  }
}

typedef _Data = ({
  List<Warehouse> warehouses,
  List<Product> products,
  List<Supplier> suppliers,
});

/// فاتورة شراء (managers only). Each line is typed by name: a known product is picked, anything
/// else is added as a new product. Lines may come from different suppliers; the backend saves one
/// purchase invoice per supplier.
class PurchaseScreen extends StatelessWidget {
  const PurchaseScreen({
    super.key,
    this.supplierId,
    this.warehouseId,
    this.productId,
  });

  /// From the supplier pages: preselects the first line's supplier.
  final String? supplierId;

  /// From the warehouse page: preselects the warehouse.
  final String? warehouseId;

  /// From the products pages: preselects the first line's product.
  final String? productId;

  @override
  Widget build(BuildContext context) {
    final inv = context.app.inventory;
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة شراء جديدة')),
      body: AsyncView<_Data>(
        refreshable: false,
        load: () async {
          final (w, p, s) = await (
            inv.warehouses(),
            inv.products(active: true),
            inv.suppliers(active: true),
          ).wait;
          return (
            warehouses: w.where((x) => x.isActive).toList(),
            products: p,
            suppliers: s,
          );
        },
        builder: (context, d) => _Form(
          data: d,
          supplierId: supplierId,
          warehouseId: warehouseId,
          productId: productId,
        ),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({
    required this.data,
    this.supplierId,
    this.warehouseId,
    this.productId,
  });

  final _Data data;
  final String? supplierId;
  final String? warehouseId;
  final String? productId;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final _byName = {for (final p in widget.data.products) _norm(p.name): p};
  late final _supplierNames = {
    for (final s in widget.data.suppliers) s.id: s.name,
  };
  late String? _warehouseId =
      widget.data.warehouses.any((w) => w.id == widget.warehouseId)
      ? widget.warehouseId
      : null;
  late final _lines = [
    _Line(
      _supplierNames.containsKey(widget.supplierId) ? widget.supplierId : null,
    ),
  ];
  final _paid = <String, TextEditingController>{};
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.data.products
        .where((p) => p.id == widget.productId)
        .firstOrNull;
    if (p != null) {
      _lines.first.name.text = p.name;
      _onPicked(_lines.first);
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    for (final c in [..._paid.values, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The known product this line's name matches, or null (a new product).
  Product? _match(_Line l) => _byName[_norm(l.name.text)];

  num _qty(_Line l) => int.tryParse(l.qty.text) ?? 0;
  num _lineTotal(_Line l) => round2(_qty(l) * (num.tryParse(l.cost.text) ?? 0));
  num _grandTotal() =>
      round2(_lines.fold<num>(0, (sum, l) => sum + _lineTotal(l)));

  /// Suppliers in the invoice (line order) with their totals.
  Map<String, num> get _totals {
    final totals = <String, num>{};
    for (final l in _lines) {
      if (l.supplierId == null) continue;
      totals[l.supplierId!] = round2(
        (totals[l.supplierId!] ?? 0) + _lineTotal(l),
      );
    }
    return totals;
  }

  TextEditingController _paidOf(String supplierId) =>
      _paid.putIfAbsent(supplierId, TextEditingController.new);

  /// Empty means paid in full.
  num _paidAmount(String supplierId, num total) {
    final t = _paidOf(supplierId).text.trim();
    return t.isEmpty ? total : num.tryParse(t) ?? 0;
  }

  /// The same existing product twice from the same supplier.
  bool _isDuplicate(_Line l) {
    final p = _match(l);
    if (p == null || l.supplierId == null) return false;
    final i = _lines.indexOf(l);
    return _lines
        .take(i)
        .any((x) => x.supplierId == l.supplierId && _match(x)?.id == p.id);
  }

  bool get _canSubmit =>
      _warehouseId != null &&
      _lines.every(
        (l) =>
            l.name.text.trim().length >= 2 &&
            l.supplierId != null &&
            _qty(l) >= 1 &&
            num.tryParse(l.cost.text) != null &&
            (_match(l) != null || num.tryParse(l.price.text) != null) &&
            !_isDuplicate(l),
      ) &&
      _totals.entries.every((e) => _paidAmount(e.key, e.value) <= e.value);

  /// A known product fills its last purchase price and main / last supplier when those are empty.
  void _onPicked(_Line l) {
    final p = _match(l);
    if (p == null) return;
    if (l.cost.text.isEmpty && p.lastCost != null) {
      l.cost.text = '${p.lastCost}';
    }
    final supplier = p.supplier?.id ?? p.lastSupplier?.id;
    if (l.supplierId == null && _supplierNames.containsKey(supplier)) {
      l.supplierId = supplier;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.purchase(_warehouseId!, {
        'items': [
          for (final l in _lines)
            {
              if (_match(l) case final p?)
                'productId': p.id
              else
                'newProduct': {
                  'name': l.name.text.trim(),
                  'price': num.parse(l.price.text),
                  'unit': l.unit,
                },
              'supplierId': l.supplierId,
              'quantity': _qty(l),
              'unitCost': num.parse(l.cost.text),
            },
        ],
        'payments': [
          for (final e in _totals.entries)
            if (_paidOf(e.key).text.trim().isNotEmpty)
              {'supplierId': e.key, 'paidAmount': _paidAmount(e.key, e.value)},
        ],
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر حفظ الفاتورة. حاول مرة أخرى.');
      });
    }
  }

  /// Known product: stock and prices now, and the average after saving (same weighted moving average as the backend).
  Widget _costPreview(_Line l, Product p) {
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.subtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          cell('الكمية', '${number(oldQty)} ← ${number(oldQty + qty)}'),
          cell('متوسط سعر الشراء', m(avg)),
          cell('سعر الشراء', [m(p.lastCost), ?p.lastSupplier?.name].dotted()),
          cell('المتوسط الجديد', m(newAvg), strong: true),
        ],
      ),
    );
  }

  Widget _nameField(_Line l) => RawAutocomplete<Product>(
    textEditingController: l.name,
    focusNode: l.focus,
    displayStringForOption: (p) => p.name,
    optionsBuilder: (v) {
      final q = _norm(v.text);
      if (q.isEmpty) return const [];
      return widget.data.products
          .where((p) => _norm(p.name).contains(q))
          .take(8);
    },
    onSelected: (_) => setState(() => _onPicked(l)),
    fieldViewBuilder: (context, controller, focus, _) => TextFormField(
      controller: controller,
      focusNode: focus,
      decoration: const InputDecoration(hintText: 'اكتب اسم الصنف'),
      onChanged: (_) => setState(() => _onPicked(l)),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: AlignmentDirectional.topStart,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final p in options)
                ListTile(
                  dense: true,
                  title: Text(p.label),
                  subtitle: Text('الكمية ${number(p.quantity)}'),
                  onTap: () => onSelected(p),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totals = _totals;
    return PageList(
      children: [
        Text(
          'اكتب اسم الصنف: لو موجود اختاره من الاقتراحات، ولو مش موجود هيتضاف صنف جديد. كل سطر ليه مورده، وكل مورد بيتسجل له فاتورة شراء لوحده.',
          style: TextStyle(color: colors.muted),
        ),
        FormCard(
          children: [
            Select<String>(
              label: 'المخزن *',
              value: _warehouseId,
              hint: 'اختر المخزن',
              items: {for (final w in widget.data.warehouses) w.id: w.name},
              onChanged: (v) => setState(() => _warehouseId = v),
            ),
          ],
        ),
        FormCard(
          title: 'الأصناف',
          children: [
            if (widget.data.suppliers.isEmpty)
              const Note('مفيش موردين. أضف مورد الأول من تبويب الموردين.'),
            for (final (i, l) in _lines.indexed)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _nameField(l)),
                        if (_lines.length > 1)
                          IconButton(
                            tooltip: 'حذف السطر ${i + 1}',
                            onPressed: () => setState(() {
                              _lines.removeAt(i).dispose();
                            }),
                            icon: Icon(
                              Icons.delete_outline,
                              color: colors.danger,
                            ),
                          ),
                      ],
                    ),
                    if (l.name.text.trim().length >= 2)
                      if (_match(l) case final p?)
                        _costPreview(l, p)
                      else ...[
                        Text(
                          'صنف جديد',
                          style: TextStyle(
                            color: colors.warningFg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Input(
                                label: 'سعر البيع *',
                                controller: l.price,
                                keyboard: Input.decimal,
                                ltr: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Select<String?>(
                                label: 'الوحدة',
                                value: l.unit,
                                items: {null: 'بدون', ...unitLabels},
                                onChanged: (v) => setState(() => l.unit = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    Select<String>(
                      label: 'المورد',
                      value: l.supplierId,
                      hint: 'اختر المورد',
                      items: _supplierNames,
                      onChanged: (v) => setState(() => l.supplierId = v),
                    ),
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
                    ),
                    Text(
                      'الإجمالي: ${money(_lineTotal(l))}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_isDuplicate(l))
                      Text(
                        'الصنف ده متكرر من نفس المورد. زوّد الكمية في السطر الأول.',
                        style: TextStyle(color: colors.danger, fontSize: 12),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                OutlinedButton.icon(
                  // A new line keeps the last line's supplier: most invoices are from one supplier.
                  onPressed: () => setState(
                    () => _lines.add(_Line(_lines.lastOrNull?.supplierId)),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صنف'),
                ),
                const Spacer(),
                Text(
                  'الإجمالي: ${money(_grandTotal())}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
        if (totals.isNotEmpty)
          FormCard(
            title: 'المدفوع للموردين',
            children: [
              Text(
                'سيب الحقل فاضي لو مدفوع بالكامل. الباقي بيتسجل دين على الشركة عند المورد.',
                style: TextStyle(color: colors.muted, fontSize: 12.5),
              ),
              for (final e in totals.entries) ...[
                Input(
                  label: 'المدفوع لـ ${_supplierNames[e.key] ?? '—'}',
                  controller: _paidOf(e.key),
                  keyboard: Input.decimal,
                  ltr: true,
                  hint:
                      '${_supplierNames[e.key] ?? '—'} — الإجمالي ${money(e.value)}',
                  onChanged: (_) => setState(() {}),
                ),
                if (_paidAmount(e.key, e.value) > e.value)
                  Text(
                    'المدفوع أكبر من الإجمالي.',
                    style: TextStyle(color: colors.danger, fontSize: 12),
                  )
                else if (round2(e.value - _paidAmount(e.key, e.value)) > 0)
                  Text(
                    'الباقي دين: ${money(round2(e.value - _paidAmount(e.key, e.value)))}',
                    style: TextStyle(
                      color: colors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ],
          ),
        FormCard(
          children: [
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: 'رقم فاتورة المورد',
            ),
          ],
        ),
        SubmitButton(
          label: 'حفظ الفاتورة',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
