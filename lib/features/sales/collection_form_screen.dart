import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../data/repositories/sales_repository.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'collection_details_screen.dart';
import 'sales_widgets.dart';

/// فاتورة تحصيل: money received without a sale. Capped at the debt still collectable.
class CollectionFormScreen extends StatelessWidget {
  const CollectionFormScreen({super.key, required this.customerId, this.visitId});

  final String customerId;
  final String? visitId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة تحصيل')),
      body: AsyncView<Customer>(
        load: () => context.app.customers.get(customerId),
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل بيانات العميل.',
        builder: (context, c) => _Form(customer: c, visitId: visitId),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.customer, this.visitId});

  final Customer customer;
  final String? visitId;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _cheque = TextEditingController();
  final _notes = TextEditingController();
  String? _method;
  DateTime? _chequeDue;
  UploadFile? _receipt;
  UploadFile? _chequeImage;
  bool _saving = false;
  String? _error;

  num get _debt => widget.customer.collectable;
  num get _entered => num.tryParse(_amount.text) ?? 0;
  num get _remainingAfter => round2(_debt - _entered);
  bool get _isCheque => _method == 'CHEQUE';

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _method == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = context.app.sales;
    try {
      final col = await repo.createCollection({
        'receiptNumber': _number.text.trim(),
        'customerId': widget.customer.id,
        'visitId': widget.visitId,
        'amount': round2(_entered),
        'paymentMethod': _method,
        'chequeNumber': _isCheque && _cheque.text.trim().isNotEmpty ? _cheque.text.trim() : null,
        'chequeDueDate': _isCheque && _chequeDue != null ? isoDay(_chequeDue!) : null,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      final uploaded = await uploadAll(repo, '/collections/${col.id}', {
        'RECEIPT': _receipt,
        if (_isCheque) 'CHEQUE': _chequeImage,
      });
      if (!mounted) return;
      replace(context, CollectionDetailsScreen(id: col.id, uploadFailed: !uploaded));
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.status == 409
            ? 'رقم الإيصال مستخدم من قبل.'
            : e is ApiException && e.status == 400
            ? 'المبلغ أكبر من مديونية العميل الحالية. حدّث الصفحة وحاول مرة أخرى.'
            : errorMessage(e, 'تعذر حفظ التحصيل. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final colors = context.colors;
    final pending = c.pendingPayments;

    return Form(
      key: _form,
      child: PageList(
        children: [
          Text('${c.name} · ${c.governorate}', style: TextStyle(color: colors.muted)),
          if (widget.visitId != null) const Note('مرتبطة بالزيارة الجارية.', tone: Tone.info),
          if (_debt <= 0)
            EmptyCard(
              pending > 0
                  ? 'كل مديونية العميل اتحصّلت، ومنها ${money(pending)} مع المندوب لسه متسلمتش للخزنة.'
                  : 'لا توجد مديونية على هذا العميل.',
            )
          else ...[
            if (!context.isManager)
              Text(
                'المبلغ يفضل في خزنتك لحد ما تسلّمه للإدارة، ووقتها يتخصم من مديونية العميل.',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            if (pending > 0)
              Text(
                'فيه ${money(pending)} محصّلة ولسه متسلمتش، ومش محسوبة في المديونية المتاحة.',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            SummaryPanel(
              items: [
                ('المديونية الحالية', money(_debt), null),
                ('المتبقي بعد التحصيل', money(_remainingAfter), colors.danger),
              ],
            ),
            FormCard(
              children: [
                Input(
                  label: 'رقم الإيصال *',
                  controller: _number,
                  ltr: true,
                  helper: 'الرقم المكتوب في دفتر الإيصالات.',
                  validator: (v) => requiredText(v, 'رقم الإيصال مطلوب.'),
                ),
                Input(
                  label: 'المبلغ المحصّل *',
                  controller: _amount,
                  keyboard: Input.decimal,
                  ltr: true,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = num.tryParse(v) ?? 0;
                    if (n <= 0) return 'أدخل مبلغًا أكبر من 0.';
                    if (n > _debt) return 'المبلغ أكبر من المديونية الحالية.';
                    return null;
                  },
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() => _amount.text = '$_debt'),
                    child: const Text('تحصيل كامل المديونية'),
                  ),
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
            NewAttachments(
              receipt: _receipt,
              cheque: _chequeImage,
              showCheque: _isCheque,
              hint: 'صور أو PDF، بحد أقصى 5 ميجابايت. يمكن رفعها لاحقًا من صفحة التحصيل.',
              onChanged: (kind, f) => setState(() => kind == 'RECEIPT' ? _receipt = f : _chequeImage = f),
            ),
            FormCard(
              children: [Input(label: 'ملاحظات', controller: _notes, maxLines: 2)],
            ),
            SubmitButton(
              label: 'حفظ التحصيل',
              loading: _saving,
              onPressed: _method == null || _entered <= 0 || _remainingAfter < 0 ? null : _submit,
            ),
            if (_error != null) Note(_error!, tone: Tone.danger),
          ],
        ],
      ),
    );
  }
}
