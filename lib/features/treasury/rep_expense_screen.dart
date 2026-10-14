import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// A rep's expense (بنزين، أكل…) paid from the cash they hold; taken off at the next handover.
/// Works offline (queued). Pops `true` when saved.
class RepExpenseScreen extends StatefulWidget {
  const RepExpenseScreen({super.key, required this.cash});

  /// Cash the rep still holds: the most they can spend.
  final num cash;

  @override
  State<RepExpenseScreen> createState() => _RepExpenseScreenState();
}

class _RepExpenseScreenState extends State<RepExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await context.app.treasury.createRepExpense(
        round2(parseAmount(_amount.text)!),
        _category.text.trim().isEmpty ? null : _category.text.trim(),
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (!mounted) return;
      if (saved == null) toast(context, savedOfflineMessage);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'المبلغ أكبر من النقدية اللي معاك.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مصروف')),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            Text(
              'من النقدية اللي معاك (${money(widget.cash)} متاح). بيتخصم من المبلغ اللي هتسلّمه، والإدارة بتوافق عليه وقت الاستلام.',
            ),
            FormCard(
              children: [
                Input(
                  label: 'المبلغ *',
                  controller: _amount,
                  keyboard: Input.decimal,
                  ltr: true,
                  validator: (v) {
                    final n = parseAmount(v) ?? 0;
                    if (n <= 0) return 'أدخل مبلغًا أكبر من 0.';
                    if (n > widget.cash) return 'أكبر من النقدية اللي معاك.';
                    return null;
                  },
                ),
                Input(label: 'النوع', controller: _category),
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
                Input(label: 'ملاحظات', controller: _notes, maxLines: 2),
              ],
            ),
            SubmitButton(
              label: 'حفظ المصروف',
              loading: _saving,
              onPressed: _submit,
            ),
            if (_error != null) Note(_error!, tone: Tone.danger),
          ],
        ),
      ),
    );
  }
}
