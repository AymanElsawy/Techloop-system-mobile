import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// Supplier dropdown with a "+" button that adds a supplier (name + phone) and selects it.
class SupplierSelect extends StatefulWidget {
  const SupplierSelect({
    super.key,
    required this.suppliers,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  final List<Supplier> suppliers;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Optional pickers get a "بدون" entry.
  final bool required;

  @override
  State<SupplierSelect> createState() => _SupplierSelectState();
}

class _SupplierSelectState extends State<SupplierSelect> {
  late final _suppliers = [...widget.suppliers];

  Future<void> _add() async {
    final repo = context.app.inventory;
    final created = await showDialog<Supplier>(
      context: context,
      builder: (_) => _QuickSupplierDialog(onSave: repo.createSupplier),
    );
    if (created == null) return;
    setState(
      () => _suppliers
        ..add(created)
        ..sort((a, b) => a.name.compareTo(b.name)),
    );
    widget.onChanged(created.id);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Select<String?>(
            label: widget.required ? 'المورد *' : 'المورد',
            value: widget.value,
            hint: 'اختر المورد',
            items: {
              if (!widget.required) null: 'بدون',
              for (final x in _suppliers)
                x.id: '${x.name}${x.phone == null ? '' : ' — ${x.phone}'}',
            },
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _add,
          tooltip: 'مورد جديد',
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _QuickSupplierDialog extends StatefulWidget {
  const _QuickSupplierDialog({required this.onSave});

  final Future<Supplier> Function(Json data) onSave;

  @override
  State<_QuickSupplierDialog> createState() => _QuickSupplierDialogState();
}

class _QuickSupplierDialogState extends State<_QuickSupplierDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final s = await widget.onSave({
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'company': null,
        'address': null,
        'notes': null,
      });
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.serverMessage.contains('already in use')
            ? 'فيه مورد بنفس الاسم. اختاره من القائمة.'
            : errorMessage(e, 'تعذر إضافة المورد.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مورد جديد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'الاسم *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'الهاتف'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Note(_error!, tone: Tone.danger),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving || _name.text.trim().length < 2 ? null : _save,
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
