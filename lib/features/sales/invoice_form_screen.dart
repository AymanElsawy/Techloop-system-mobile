import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/inventory.dart';
import '../../data/repositories/sales_repository.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'invoice_details_screen.dart';
import 'invoice_form_view_model.dart';
import 'sales_widgets.dart';

/// فاتورة بيع for a customer, optionally during an in-progress visit.
class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key, required this.customerId, this.visitId});

  final String customerId;
  final String? visitId;

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _cheque = TextEditingController();
  final _notes = TextEditingController();
  UploadFile? _receipt;
  UploadFile? _chequeImage;
  String? _error;

  late final InvoiceFormViewModel vm = InvoiceFormViewModel(
    customerId: widget.customerId,
    visitId: widget.visitId,
    isManager: context.isManager,
    customers: context.app.customers,
    inventory: context.app.inventory,
    sales: context.app.sales,
  )..load();

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || !vm.canSubmit) return;
    setState(() => _error = null);
    final repo = context.app.sales;
    try {
      final invoice = await vm.submit(
        vm.body(invoiceNumber: _number.text, chequeNumber: _cheque.text, notes: _notes.text),
      );
      final uploaded = await uploadAll(repo, '/invoices/${invoice.id}', {
        'RECEIPT': _receipt,
        if (vm.isCheque) 'CHEQUE': _chequeImage,
      });
      if (!mounted) return;
      replace(context, InvoiceDetailsScreen(id: invoice.id, uploadFailed: !uploaded));
    } catch (e) {
      setState(
        () => _error = e is ApiException && e.status == 409
            ? 'رقم الفاتورة مستخدم من قبل.'
            : e is ApiException && e.status == 400 && e.serverMessage.contains('previous debt')
            ? 'المبلغ المدفوع أكبر من المسموح. المديونية تغيرت، حدّث الصفحة وحاول مرة أخرى.'
            : e is ApiException && e.serverMessage.contains('stock')
            ? 'الكمية غير متاحة في المخزون. حدّث الصفحة وحاول مرة أخرى.'
            : errorMessage(e, 'تعذر حفظ الفاتورة. حاول مرة أخرى.'),
      );
    }
  }

  Future<void> _pickProduct(int index) async {
    final options = vm.available(index);
    final chosen = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(products: options, vm: vm),
    );
    if (chosen != null) vm.update(() => vm.lines[index].productId = chosen.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة بيع جديدة')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          if (vm.loading) return const Center(child: CircularProgressIndicator());
          if (vm.loadError != null) {
            return ErrorState(message: 'حدث خطأ أثناء تحميل البيانات.', onRetry: vm.load);
          }
          final c = vm.customer!;
          if (c.status == 'REJECTED') {
            return const PageList(children: [Note('لا يمكن إنشاء فاتورة لعميل مرفوض.', tone: Tone.danger)]);
          }
          return Form(key: _form, child: _body(context));
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = vm.customer!;
    final colors = context.colors;
    return PageList(
      children: [
        Text('${c.name} · ${c.governorate}', style: TextStyle(color: colors.muted)),
        if (widget.visitId != null)
          const Note('مرتبطة بالزيارة الجارية. بعد الحفظ ارجع للزيارة من زر الرجوع.', tone: Tone.info),
        FormCard(
          children: [
            Input(
              label: 'رقم الفاتورة *',
              controller: _number,
              ltr: true,
              helper: 'الرقم المكتوب في دفتر الفواتير.',
              validator: (v) => requiredText(v, 'رقم الفاتورة مطلوب.'),
            ),
            if (vm.isManager)
              Select<String>(
                label: 'البيع من مخزن *',
                value: vm.warehouseId,
                hint: 'اختر المخزن',
                items: {for (final w in vm.warehouses) w.id: w.name},
                onChanged: (v) => vm.selectWarehouse(v!),
              )
            else if (vm.warehouseName != null)
              Text('البيع من عهدتك أولاً، والباقي من مخزن ${vm.warehouseName}.', style: TextStyle(color: colors.muted)),
          ],
        ),
        if (vm.noWarehouse)
          const Note('لم يتم ربطك بمخزن بعد، لذلك لا يمكنك البيع. تواصل مع الإدارة.', tone: Tone.danger),
        _itemsCard(context),
        _paymentCard(context),
        NewAttachments(
          receipt: _receipt,
          cheque: _chequeImage,
          showCheque: vm.isCheque,
          hint: 'صور أو PDF، بحد أقصى 5 ميجابايت. يمكن رفعها لاحقًا من صفحة الفاتورة.',
          onChanged: (kind, f) => setState(() => kind == 'RECEIPT' ? _receipt = f : _chequeImage = f),
        ),
        FormCard(
          children: [Input(label: 'ملاحظات', controller: _notes, maxLines: 2)],
        ),
        SubmitButton(label: 'حفظ الفاتورة', loading: vm.saving, onPressed: vm.canSubmit ? _submit : null),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }

  Widget _itemsCard(BuildContext context) {
    final colors = context.colors;
    return FormCard(
      title: 'الأصناف',
      children: [
        for (final (i, line) in vm.lines.indexed)
          Builder(
            builder: (context) {
              final l = vm.calc(line);
              final p = l.product;
              return Container(
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
                          child: OutlinedButton(
                            onPressed: () => _pickProduct(i),
                            style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
                            child: Text(p?.label ?? 'اختر الصنف', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (vm.lines.length > 1)
                          IconButton(
                            tooltip: 'حذف السطر ${i + 1}',
                            onPressed: () => vm.removeLine(i),
                            icon: Icon(Icons.delete_outline, color: colors.danger),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _QuantityStepper(value: line.quantity, onChanged: (q) => vm.update(() => line.quantity = q)),
                        const Spacer(),
                        if (p != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('السعر: ${money(p.price)}', style: TextStyle(color: colors.muted, fontSize: 12)),
                              Text('الإجمالي: ${money(l.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                      ],
                    ),
                    if (p != null && vm.stockLoaded) ...[
                      const SizedBox(height: 6),
                      if (l.overStock)
                        Text(
                          'المتاح ${number(l.custody + l.warehouse)} فقط${vm.isManager ? '' : ' (عهدتك ${number(l.custody)} + المخزن ${number(l.warehouse)})'}.',
                          style: TextStyle(color: colors.danger, fontSize: 12),
                        )
                      else
                        Text(
                          vm.isManager
                              ? 'المتاح في المخزن: ${number(l.warehouse)}'
                              : 'من عهدتك ${number(l.fromCustody)}${l.fromWarehouse > 0 ? ' + من المخزن ${number(l.fromWarehouse)}' : ''} (المتاح: عهدة ${number(l.custody)}، مخزن ${number(l.warehouse)})',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: vm.addLine,
            icon: const Icon(Icons.add),
            label: const Text('إضافة صنف'),
          ),
        ),
      ],
    );
  }

  Widget _paymentCard(BuildContext context) {
    final colors = context.colors;
    return FormCard(
      title: 'السداد',
      children: [
        if (vm.pendingPayments > 0)
          Text(
            'فيه ${money(vm.pendingPayments)} محصّلة ولسه متسلمتش للخزنة، ومش محسوبة هنا.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        if (!vm.isManager)
          Text(
            'المبلغ اللي تستلمه يفضل في خزنتك لحد ما تسلّمه للإدارة، ووقتها يتخصم من مديونية العميل.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        SummaryPanel(
          items: [
            ('مديونية سابقة', money(vm.previousDebt), null),
            ('إجمالي الفاتورة', money(vm.total), null),
            ('المدفوع', money(vm.paid), null),
            ('المديونية بعد الفاتورة', money(vm.debtAfter), colors.danger),
          ],
        ),
        if (vm.previousDebtPaid > 0)
          Note(
            'الفاتورة مدفوعة بالكامل، و${money(vm.previousDebtPaid)} تُخصم من المديونية السابقة.',
            tone: Tone.success,
          )
        else if (vm.remaining > 0 && vm.paid > 0)
          Text('المتبقي من الفاتورة (آجل): ${money(vm.remaining)}', style: TextStyle(color: colors.muted)),
        Input(
          label: 'المبلغ المدفوع مقدمًا',
          controller: _paid,
          keyboard: Input.decimal,
          ltr: true,
          helper: 'يمكن دفع أكثر من الفاتورة لسداد مديونية سابقة (حتى ${money(vm.maxPaid)}).',
          onChanged: (v) => vm.update(() => vm.paid = num.tryParse(v) ?? 0),
        ),
        if (vm.paid > 0)
          PaymentFields(
            method: vm.method,
            onMethod: (m) => vm.update(() => vm.method = m),
            chequeNumber: _cheque,
            chequeDue: vm.chequeDue,
            onChequeDue: (d) => vm.update(() => vm.chequeDue = d),
          ),
        if (vm.paymentError != null) Text(vm.paymentError!, style: TextStyle(color: colors.danger, fontSize: 12.5)),
      ],
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'نقص',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        InkWell(
          onTap: () async {
            final controller = TextEditingController(text: '$value');
            final q = await showDialog<int>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('الكمية'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
                    child: const Text('تم'),
                  ),
                ],
              ),
            );
            if (q != null && q >= 1) onChanged(q);
          },
          child: SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'زود',
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

/// Bottom sheet: search products, shows price and what is available to sell.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.vm});

  final List<Product> products;
  final InvoiceFormViewModel vm;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.products
        .where((p) => _q.isEmpty || p.name.contains(_q) || (p.code?.toLowerCase().contains(_q.toLowerCase()) ?? false))
        .toList();
    final vm = widget.vm;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'بحث بالاسم أو الكود',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('لا توجد أصناف مطابقة.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = list[i];
                        final avail = (vm.custody[p.id] ?? 0) + (vm.warehouseStock[p.id] ?? 0);
                        return Tile(
                          title: p.label,
                          subtitle: vm.stockLoaded ? 'المتاح ${number(avail)}' : null,
                          trailing: money(p.price),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
