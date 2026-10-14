import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// New / edit supplier in a bottom sheet. Returns the saved supplier, or null.
Future<Supplier?> showSupplierForm(
  BuildContext context, {
  Supplier? supplier,
  required Future<Supplier> Function(Json data) onSave,
}) => showModalBottomSheet<Supplier>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SupplierForm(supplier: supplier, onSave: onSave),
);

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({required this.supplier, required this.onSave});

  final Supplier? supplier;
  final Future<Supplier> Function(Json data) onSave;

  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  late final s = widget.supplier;
  late final _name = TextEditingController(text: s?.name);
  late final _phone = TextEditingController(text: s?.phone);
  late final _company = TextEditingController(text: s?.company);
  late final _address = TextEditingController(text: s?.address);
  late final _notes = TextEditingController(text: s?.notes);
  bool _saving = false;
  String? _error;

  String? _v(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave({
        'name': _name.text.trim(),
        'phone': _v(_phone),
        'company': _v(_company),
        'address': _v(_address),
        'notes': _v(_notes),
      });
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.serverMessage.contains('already in use')
            ? 'فيه مورد بنفس الاسم.'
            : errorMessage(e, 'تعذر حفظ المورد.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s == null ? 'مورد جديد' : 'تعديل المورد',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Input(
              label: 'اسم المورد *',
              controller: _name,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Input(
              label: 'الهاتف',
              controller: _phone,
              keyboard: TextInputType.phone,
              ltr: true,
            ),
            const SizedBox(height: 14),
            Input(label: 'الشركة', controller: _company),
            const SizedBox(height: 14),
            Input(label: 'العنوان', controller: _address),
            const SizedBox(height: 14),
            Input(label: 'ملاحظات', controller: _notes),
            const SizedBox(height: 18),
            SubmitButton(
              label: s == null ? 'إضافة المورد' : 'حفظ',
              loading: _saving,
              onPressed: _name.text.trim().length < 2 ? null : _save,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Note(_error!, tone: Tone.danger),
            ],
          ],
        ),
      ),
    );
  }
}
