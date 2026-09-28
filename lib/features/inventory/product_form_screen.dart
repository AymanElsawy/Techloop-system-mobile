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
import 'stock_move_screen.dart';

/// New product, or edit when [id] is set. Managers only. The quantity comes from warehouse receipts.
class ProductFormScreen extends StatelessWidget {
  const ProductFormScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? 'صنف جديد' : 'تعديل صنف')),
      body: AsyncView<(Product?, List<Supplier>)>(
        load: () {
          final inv = context.app.inventory;
          return (id == null ? Future<Product?>.value() : inv.product(id!), inv.suppliers(active: true)).wait;
        },
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل بيانات الصنف.',
        builder: (context, d) => _Form(product: d.$1, suppliers: d.$2),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.product, required this.suppliers});

  final Product? product;
  final List<Supplier> suppliers;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late final p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _price = TextEditingController(text: p == null ? '' : '${p!.price}');
  late final _code = TextEditingController(text: p?.code);
  late final _manufacturer = TextEditingController(text: p?.manufacturer);
  late final _min = TextEditingController(text: p?.minQuantity == null ? '' : '${p!.minQuantity}');
  late final _notes = TextEditingController(text: p?.notes);
  late String? _unit = p?.unit;
  late String? _supplierId = p?.supplier?.id;
  late DateTime? _expiry = p?.expiryDate;
  late bool _active = p?.isActive ?? true;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Empty strings clear optional fields on the backend.
    final data = {
      'name': _name.text.trim(),
      'price': num.parse(_price.text),
      'unit': _unit,
      'supplierId': _supplierId,
      'code': _code.text.trim(),
      'manufacturer': _manufacturer.text.trim(),
      'minQuantity': int.tryParse(_min.text),
      'expiryDate': _expiry == null ? null : isoDay(_expiry!),
      'notes': _notes.text.trim(),
      'isActive': _active,
    };
    final repo = context.app.inventory;
    try {
      if (p == null) {
        final created = await repo.createProduct(data);
        // A new product has no stock yet: continue straight to receiving it (from its supplier).
        if (mounted) {
          replace(context, StockMoveScreen(type: 'RECEIVE', productId: created.id, supplierId: _supplierId));
        }
      } else {
        await repo.updateProduct(p!.id, data);
        if (mounted) Navigator.pop(context, true);
      }
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
                validator: (v) => v.trim().length < 2 ? 'اسم الصنف مطلوب (حرفان على الأقل).' : null,
              ),
              Input(
                label: 'السعر (ج.م) *',
                controller: _price,
                keyboard: Input.decimal,
                ltr: true,
                validator: (v) => (num.tryParse(v) ?? -1) < 0 ? 'السعر مطلوب ولا يقل عن 0.' : null,
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
                onChanged: (v) => setState(() => _supplierId = v),
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
                    'يظهر تنبيه "كمية منخفضة" لما إجمالي الكمية (كل المخازن والعُهد) يوصل للرقم ده. الكمية نفسها بتتسجل من المخزن (وارد).',
              ),
              DateField(label: 'تاريخ الصلاحية', value: _expiry, onChanged: (d) => setState(() => _expiry = d)),
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
          SubmitButton(label: p == null ? 'إضافة الصنف' : 'حفظ التعديلات', loading: _saving, onPressed: _submit),
          if (_error != null) Note(_error!, tone: Tone.danger),
        ],
      ),
    );
  }
}
