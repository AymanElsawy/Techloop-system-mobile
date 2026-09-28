import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../data/models/sales.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'return_details_screen.dart';

typedef _Data = ({List<Invoice> invoices, List<Warehouse> warehouses});

/// فاتورة مرتجع from one of the customer's sales invoices. Reduces their debt;
/// goods go back to the rep's custody (managers pick the warehouse).
class ReturnFormScreen extends StatelessWidget {
  const ReturnFormScreen({super.key, required this.customerId, this.invoiceId});

  final String customerId;

  /// Preselected invoice.
  final String? invoiceId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة مرتجع')),
      body: AsyncView<_Data>(
        refreshable: false,
        errorText: 'حدث خطأ أثناء تحميل الفواتير.',
        // Only active invoices can take a return. Reps get their own invoices only.
        load: () async {
          final (invoices, warehouses) = await (
            app.sales.invoices(customerId: customerId),
            context.isManager ? app.inventory.warehouses() : Future.value(<Warehouse>[]),
          ).wait;
          return (
            invoices: invoices.where((i) => !i.cancelled).toList(),
            warehouses: warehouses.where((w) => w.isActive).toList(),
          );
        },
        builder: (context, d) => d.invoices.isEmpty
            ? const PageList(children: [EmptyCard('مفيش فواتير بيع لهذا العميل يترجع منها.')])
            : _Form(invoices: d.invoices, warehouses: d.warehouses, initialInvoice: invoiceId),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.invoices, required this.warehouses, this.initialInvoice});

  final List<Invoice> invoices;
  final List<Warehouse> warehouses;
  final String? initialInvoice;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _notes = TextEditingController();
  Invoice? _invoice;
  Map<String, num> _returned = {};
  bool _loadingReturns = false;

  /// productId -> quantity field; reset when the invoice changes.
  final Map<String, TextEditingController> _qty = {};
  String? _warehouseId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pre = widget.invoices.where((i) => i.id == widget.initialInvoice).firstOrNull;
    if (pre != null) _select(pre);
  }

  Future<void> _select(Invoice inv) async {
    final repo = context.app.sales;
    setState(() {
      _invoice = inv;
      _qty
        ..clear()
        ..addAll({for (final i in inv.items) i.product: TextEditingController()});
      _returned = {};
      _loadingReturns = true;
      _warehouseId = inv.warehouse?.id;
    });
    try {
      final previous = await repo.returns(invoiceId: inv.id);
      if (mounted && _invoice == inv) setState(() => _returned = returnedByProduct(previous));
    } catch (_) {} // the backend still checks what's left
    if (mounted) setState(() => _loadingReturns = false);
  }

  num _left(LineItem i) => i.quantity - (_returned[i.product] ?? 0);
  int _q(String product) => int.tryParse(_qty[product]?.text ?? '') ?? 0;
  num get _total => round2(_invoice?.items.fold<num>(0, (s, i) => s + _q(i.product) * i.unitPrice) ?? 0);
  bool get _invalid => _invoice?.items.any((i) => _q(i.product) > _left(i)) ?? false;

  Future<void> _submit() async {
    final items = [
      for (final i in _invoice!.items)
        if (_q(i.product) > 0) {'productId': i.product, 'quantity': _q(i.product)},
    ];
    if (items.isEmpty || _invalid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await context.app.sales.createReturn({
        'invoiceId': _invoice!.id,
        'warehouseId': context.isManager ? _warehouseId : null,
        'items': items,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (mounted) replace(context, ReturnDetailsScreen(id: r.id));
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(
          e,
          e is ApiException && e.serverMessage.isNotEmpty
              ? 'تعذر حفظ المرتجع: الكمية أكبر من المتاح أو الفاتورة اتغيرت. حدّث الصفحة وحاول مرة أخرى.'
              : null,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final manager = context.isManager;
    final inv = _invoice;
    return PageList(
      children: [
        Text(
          'قيمة المرتجع بتتخصم من مديونية العميل. ${manager ? 'البضاعة بترجع للمخزن اللي تختاره.' : 'البضاعة بترجع لعهدتك.'}',
          style: TextStyle(color: colors.muted, fontSize: 13),
        ),
        FormCard(
          children: [
            Select<String>(
              label: 'فاتورة البيع *',
              value: inv?.id,
              hint: 'اختار الفاتورة',
              items: {
                for (final i in widget.invoices)
                  i.id: '${i.invoiceNumber} · ${shortDate(i.createdAt)} · ${money(i.total)}',
              },
              onChanged: (id) => _select(widget.invoices.firstWhere((i) => i.id == id)),
            ),
            if (manager && inv != null)
              Select<String>(
                label: 'البضاعة ترجع لمخزن',
                value: _warehouseId,
                items: {for (final w in widget.warehouses) w.id: w.name},
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
          ],
        ),
        if (inv != null) ...[
          SectionCard(
            title: 'الأصناف',
            trailing: TextButton(
              onPressed: () => setState(() {
                for (final i in inv.items) {
                  _qty[i.product]!.text = '${_left(i).toInt()}';
                }
              }),
              child: const Text('إرجاع الكل'),
            ),
            children: [
              if (_loadingReturns) const LinearProgressIndicator(),
              for (final i in inv.items) _line(context, i),
            ],
          ),
          FormCard(
            children: [
              Input(label: 'ملاحظات / سبب المرتجع', controller: _notes, maxLines: 2),
              Text(
                'إجمالي المرتجع: ${money(_total)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SubmitButton(
            label: 'حفظ فاتورة المرتجع',
            loading: _saving,
            onPressed: _total > 0 && !_invalid && !_loadingReturns ? _submit : null,
          ),
          if (_error != null) Note(_error!, tone: Tone.danger),
        ],
      ],
    );
  }

  Widget _line(BuildContext context, LineItem i) {
    final colors = context.colors;
    final left = _left(i);
    final q = _q(i.product);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'السعر ${money(i.unitPrice)} · المباع ${number(i.quantity)}${(_returned[i.product] ?? 0) > 0 ? ' · اترجع ${number(_returned[i.product]!)}' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
                if (q > 0) Text('الإجمالي ${money(q * i.unitPrice)}', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          if (left <= 0)
            Text('اترجع كله', style: TextStyle(fontSize: 12, color: colors.muted))
          else
            Column(
              children: [
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _qty[i.product],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(hintText: '0', isDense: true, errorText: q > left ? '' : null),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Text(
                  'المتاح ${number(left)}',
                  style: TextStyle(fontSize: 11.5, color: q > left ? colors.danger : colors.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
