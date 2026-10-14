import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../sales/sales_widgets.dart';

/// سداد لاحق لمورد: reduces the supplier's debt, capped at its current value.
class SupplierPaymentFormScreen extends StatefulWidget {
  const SupplierPaymentFormScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  State<SupplierPaymentFormScreen> createState() =>
      _SupplierPaymentFormScreenState();
}

class _SupplierPaymentFormScreenState extends State<SupplierPaymentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _cheque = TextEditingController();
  final _notes = TextEditingController();
  String? _method;
  DateTime? _chequeDue;
  bool _saving = false;
  String? _error;

  num get _debt => widget.supplier.debt;
  num get _entered => num.tryParse(_amount.text) ?? 0;
  num get _remainingAfter => round2(_debt - _entered);
  bool get _isCheque => _method == 'CHEQUE';

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _method == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = await context.app.inventory
          .createSupplierPayment(widget.supplier.id, {
            'amount': round2(_entered),
            'paymentMethod': _method,
            'chequeNumber': _isCheque && _cheque.text.trim().isNotEmpty
                ? _cheque.text.trim()
                : null,
            'chequeDueDate': _isCheque && _chequeDue != null
                ? isoDay(_chequeDue!)
                : null,
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          });
      if (!mounted) return;
      Navigator.pop(context, payment);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.status == 400
            ? 'المبلغ أكبر من مديونية المورد الحالية. حدّث الصفحة وحاول مرة أخرى.'
            : errorMessage(e, 'تعذر حفظ السداد. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل سداد للمورد')),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            SummaryPanel(
              items: [
                ('المديونية الحالية', money(_debt), null),
                (
                  'المتبقي بعد السداد',
                  money(_remainingAfter),
                  context.colors.danger,
                ),
              ],
            ),
            FormCard(
              children: [
                Input(
                  label: 'المبلغ *',
                  controller: _amount,
                  keyboard: Input.decimal,
                  ltr: true,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = num.tryParse(v) ?? 0;
                    if (n <= 0) return 'أدخل مبلغًا أكبر من 0.';
                    if (n > _debt) return 'المبلغ أكبر من مديونية المورد.';
                    return null;
                  },
                ),
                PaymentFields(
                  method: _method,
                  onMethod: (m) => setState(() => _method = m),
                  chequeNumber: _cheque,
                  chequeDue: _chequeDue,
                  onChequeDue: (d) => setState(() => _chequeDue = d),
                ),
              ],
            ),
            FormCard(
              children: [
                Input(label: 'ملاحظات', controller: _notes, maxLines: 2),
              ],
            ),
            SubmitButton(
              label: 'حفظ السداد',
              loading: _saving,
              onPressed: _method == null || _entered <= 0 || _remainingAfter < 0
                  ? null
                  : _submit,
            ),
            if (_error != null) Note(_error!, tone: Tone.danger),
          ],
        ),
      ),
    );
  }
}
