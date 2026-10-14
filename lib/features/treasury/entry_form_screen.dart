import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// Expense / withdrawal / bank deposit out of the treasury. Not capped: a bucket may go negative.
/// Pops `true` when saved.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, required this.type, required this.summary});

  final String type;
  final TreasurySummary summary;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  String? _method = 'CASH';
  bool _saving = false;
  String? _error;

  bool get _isExpense => widget.type == 'EXPENSE';

  /// Any bucket, even at zero or below; money already in the bank can't be deposited again.
  List<String> get _methods => [
    for (final m in paymentMethods)
      if (!(widget.type == 'BANK_DEPOSIT' && m == 'BANK_TRANSFER')) m,
  ];
  num get _available =>
      widget.summary.byMethod
          .where((m) => m.method == _method)
          .firstOrNull
          ?.total ??
      0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _method == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.treasury.createEntry({
        'type': widget.type,
        'amount': round2(parseAmount(_amount.text)!),
        'paymentMethod': _method,
        'category': _isExpense && _category.text.trim().isNotEmpty
            ? _category.text.trim()
            : null,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(
          e,
          'المبلغ أكبر من المتاح في الخزنة. حدّث الصفحة وحاول مرة أخرى.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = entryTypeLabels[widget.type]!;
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            FormCard(
              children: [
                Select<String>(
                  label: widget.type == 'BANK_DEPOSIT' ? 'من *' : 'اتدفع من *',
                  value: _method,
                  items: {for (final m in _methods) m: bucketLabel(m)},
                  onChanged: (m) => setState(() => _method = m),
                ),
                Input(
                  label: 'المبلغ *',
                  controller: _amount,
                  keyboard: Input.decimal,
                  ltr: true,
                  helper: 'الرصيد الحالي: ${money(_available)}',
                  validator: (v) {
                    final n = parseAmount(v) ?? 0;
                    if (n <= 0) return 'أدخل مبلغًا أكبر من 0.';
                    return null;
                  },
                ),
                if (_isExpense) ...[
                  Input(label: 'نوع المصروف', controller: _category),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in expenseCategories)
                        ActionChip(
                          label: Text(c),
                          onPressed: () => setState(() => _category.text = c),
                        ),
                    ],
                  ),
                ],
                Input(label: 'ملاحظات', controller: _notes, maxLines: 2),
              ],
            ),
            SubmitButton(
              label: 'حفظ $label',
              loading: _saving,
              onPressed: _submit,
            ),
            if (_error != null) Note(_error!, tone: Tone.danger),
            if (widget.type == 'BANK_DEPOSIT')
              Text(
                'الإيداع بينقل المبلغ للبنك، ورصيد الشركة الإجمالي مبيتغيرش.',
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}
