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

/// New product, or edit when [id] is set. Managers only.
/// A new product is received right away at its purchase price: warehouse and quantity (from its supplier).
class ProductFormScreen extends StatelessWidget {
  const ProductFormScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? 'صنف جديد' : 'تعديل صنف')),
      body: AsyncView<(Product?, List<Supplier>, List<Warehouse>)>(
        load: () {
          final inv = context.app.inventory;
          return (
            id == null ? Future<Product?>.value() : inv.product(id!),
            inv.suppliers(active: true),
            id == null ? inv.warehouses() : Future.value(<Warehouse>[]),
          ).wait;
        },
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل بيانات الصنف.',
        builder: (context, d) => _Form(
          product: d.$1,
          suppliers: d.$2,
          warehouses: d.$3.where((w) => w.isActive).toList(),
        ),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({
    required this.product,
    required this.suppliers,
    required this.warehouses,
  });

  final Product? product;
  final List<Supplier> suppliers;
  final List<Warehouse> warehouses;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late final p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _price = TextEditingController(
    text: p == null ? '' : '${p!.price}',
  );
  late final _lastCost = TextEditingController(
    text: p?.lastCost == null ? '' : '${p!.lastCost}',
  );
  late final _code = TextEditingController(text: p?.code);
  late final _manufacturer = TextEditingController(text: p?.manufacturer);
  late final _min = TextEditingController(
    text: p?.minQuantity == null ? '' : '${p!.minQuantity}',
  );
  late final _notes = TextEditingController(text: p?.notes);
  late String? _unit = p?.unit;
  late String? _supplierId = p?.supplier?.id;
  late DateTime? _expiry = p?.expiryDate;
  late bool _active = p?.isActive ?? true;
  // New product only: the opening receipt.
  String? _warehouseId;
  final _quantity = TextEditingController();
  final _paidAmount = TextEditingController();
  bool _saving = false;
  String? _error;

  num _total() =>
      (int.tryParse(_quantity.text) ?? 0) * (num.tryParse(_lastCost.text) ?? 0);

  /// Empty means paid in full.
  num _remainingDebt() => _paidAmount.text.trim().isEmpty
      ? 0
      : round2(_total() - (num.tryParse(_paidAmount.text) ?? 0));

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    if (p == null && _supplierId == null) {
      setState(() => _error = 'اختار المورد اللي جاي منه الصنف.');
      return;
    }
    if (_remainingDebt() < 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Empty strings clear optional fields on the backend.
    final data = {
      'name': _name.text.trim(),
      'price': num.parse(_price.text),
      'lastCost': num.parse(_lastCost.text),
      'unit': _unit,
      'supplierId': _supplierId,
      'code': _code.text.trim(),
      'manufacturer': _manufacturer.text.trim(),
      'minQuantity': int.tryParse(_min.text),
      'expiryDate': _expiry == null ? null : isoDay(_expiry!),
      'notes': _notes.text.trim(),
      'isActive': _active,
      if (p == null)
        'stock': {
          'warehouseId': _warehouseId,
          'quantity': int.parse(_quantity.text),
          'unitCost': num.parse(_lastCost.text),
          if (_paidAmount.text.trim().isNotEmpty)
            'paidAmount': num.parse(_paidAmount.text),
        },
    };
    final repo = context.app.inventory;
    try {
      p == null
          ? await repo.createProduct(data)
          : await repo.updateProduct(p!.id, data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.status == 409
            ? 'يوجد صنف آخر بنفس الكود.'
            : errorMessage(e, 'تعذر حفظ الصنف. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: PageList(
        children: [
          FormCard(
            children: [
              Input(
                label: 'اسم الصنف *',
                controller: _name,
                validator: (v) => v.trim().length < 2
                    ? 'اسم الصنف مطلوب (حرفان على الأقل).'
                    : null,
              ),
              Input(
                label: 'سعر الشراء (ج.م) *',
                controller: _lastCost,
                keyboard: Input.decimal,
                ltr: true,
                onChanged: (_) => setState(() {}),
                validator: (v) => (num.tryParse(v) ?? -1) < 0
                    ? 'سعر الشراء مطلوب ولا يقل عن 0.'
                    : null,
              ),
              Input(
                label: 'سعر البيع (ج.م) *',
                controller: _price,
                keyboard: Input.decimal,
                ltr: true,
                validator: (v) => (num.tryParse(v) ?? -1) < 0
                    ? 'سعر البيع مطلوب ولا يقل عن 0.'
                    : null,
              ),
              Select<String?>(
                label: 'الوحدة',
                value: _unit,
                items: {null: 'بدون', ...unitLabels},
                onChanged: (v) => setState(() => _unit = v),
              ),
              SupplierSelect(
                suppliers: widget.suppliers,
                value: _supplierId,
                required: p == null,
                onChanged: (v) => setState(() => _supplierId = v),
              ),
            ],
          ),
          if (p == null)
            FormCard(
              children: [
                const Text(
                  'الوارد (أول كمية للصنف، بسعر الشراء)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Select<String>(
                  label: 'المخزن *',
                  value: _warehouseId,
                  hint: 'اختر المخزن',
                  items: {for (final w in widget.warehouses) w.id: w.name},
                  onChanged: (v) => setState(() => _warehouseId = v),
                  validator: (v) => v == null ? 'اختار المخزن.' : null,
                ),
                Input(
                  label: 'الكمية *',
                  controller: _quantity,
                  keyboard: TextInputType.number,
                  ltr: true,
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (int.tryParse(v) ?? 0) < 1
                      ? 'الكمية مطلوبة (رقم صحيح 1 أو أكثر).'
                      : null,
                ),
                Input(
                  label: 'المدفوع الآن للمورد',
                  controller: _paidAmount,
                  keyboard: Input.decimal,
                  ltr: true,
                  hint:
                      'الإجمالي (${money(_total())}) — سيب الحقل فاضي لو مدفوع بالكامل',
                  onChanged: (_) => setState(() {}),
                ),
                if (_remainingDebt() < 0)
                  Text(
                    'المدفوع أكبر من إجمالي الوارد.',
                    style: TextStyle(
                      color: context.colors.danger,
                      fontSize: 12,
                    ),
                  )
                else if (_remainingDebt() > 0)
                  Text(
                    'الباقي دين على الشركة عند المورد: ${money(_remainingDebt())}',
                    style: TextStyle(
                      color: context.colors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          FormCard(
            children: [
              Input(label: 'كود الصنف', controller: _code, ltr: true),
              Input(label: 'الشركة المنتجة', controller: _manufacturer),
              Input(
                label: 'حد التنبيه للكمية',
                controller: _min,
                keyboard: TextInputType.number,
                ltr: true,
                helper:
                    'يظهر تنبيه "كمية منخفضة" لما إجمالي الكمية (كل المخازن والعُهد) يوصل للرقم ده.',
              ),
              DateField(
                label: 'تاريخ الصلاحية',
                value: _expiry,
                onChanged: (d) => setState(() => _expiry = d),
              ),
              Input(label: 'ملاحظات', controller: _notes, maxLines: 3),
              if (p != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('صنف نشط'),
                  subtitle: Text(
                    'الصنف الموقوف لا يظهر للمناديب',
                    style: TextStyle(color: context.colors.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
          SubmitButton(
            label: p == null ? 'إضافة الصنف' : 'حفظ التعديلات',
            loading: _saving,
            onPressed: _submit,
          ),
          if (_error != null) Note(_error!, tone: Tone.danger),
        ],
      ),
    );
  }
}
