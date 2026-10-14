import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'deposit_details_screen.dart';
import 'treasury_screen.dart';

/// A manager receives the selected payments from a rep. Everything starts selected;
/// untick what was not handed over.
class HandoverScreen extends StatelessWidget {
  const HandoverScreen({super.key, required this.repId});

  final String repId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استلام من مندوب')),
      body: AsyncView<(List<Payment>, List<TreasuryEntry>)>(
        load: () => (
          context.app.treasury.pending(repId),
          context.app.treasury.entries(repId: repId, pending: true),
        ).wait,
        builder: (context, d) => d.$1.isEmpty
            ? const PageList(
                children: [EmptyCard('مفيش فلوس مع المندوب ده لم تُسلَّم.')],
              )
            : _Form(repId: repId, payments: d.$1, expenses: d.$2),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({
    required this.repId,
    required this.payments,
    required this.expenses,
  });

  final String repId;
  final List<Payment> payments;

  /// The rep's expenses not handed over yet: accepted ones come out of the cash received.
  final List<TreasuryEntry> expenses;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final Set<String> _selected = {for (final p in widget.payments) p.key};
  late final Set<String> _expenses = {for (final e in widget.expenses) e.id};
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  List<Payment> get _chosen =>
      widget.payments.where((p) => _selected.contains(p.key)).toList();
  List<TreasuryEntry> get _chosenExpenses =>
      widget.expenses.where((e) => _expenses.contains(e.id)).toList();
  num get _spent => sumPayments(_chosenExpenses.map((e) => e.amount));
  num get _cash => sumPayments(
    _chosen.where((p) => p.paymentMethod == 'CASH').map((p) => p.amount),
  );

  Future<void> _submit() async {
    if (_chosen.isEmpty || _spent > _cash || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final d = await context.app.treasury.createDeposit(
        widget.repId,
        _chosen,
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        _chosenExpenses,
      );
      if (mounted) replace(context, DepositDetailsScreen(id: d.id));
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(
          e,
          'تعذر تسجيل الاستلام. حدّث الصفحة وحاول مرة أخرى.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final all = chosen.length == widget.payments.length;
    return PageList(
      children: [
        PageHeader(
          title: 'استلام من ${widget.payments.first.rep.name}',
          subtitle:
              'علّم على الفلوس والشيكات اللي استلمتها فعلًا. مديونية العملاء بتنزل بعد الحفظ.',
        ),
        PaymentsCard(
          title: 'المستندات',
          payments: widget.payments,
          selected: _selected,
          onToggle: (p) => setState(
            () => _selected.contains(p.key)
                ? _selected.remove(p.key)
                : _selected.add(p.key),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => setState(
              () => all
                  ? _selected.clear()
                  : _selected.addAll(widget.payments.map((p) => p.key)),
            ),
            child: Text(all ? 'إلغاء تحديد الكل' : 'تحديد الكل'),
          ),
        ),
        if (widget.expenses.isNotEmpty)
          SectionCard(
            title: 'مصروفات المندوب (من النقدي)',
            children: [
              for (final e in widget.expenses)
                Tile(
                  leading: Checkbox(
                    value: _expenses.contains(e.id),
                    onChanged: (_) => setState(
                      () => _expenses.contains(e.id)
                          ? _expenses.remove(e.id)
                          : _expenses.add(e.id),
                    ),
                  ),
                  title:
                      'مصروف #${e.number}${e.category == null ? '' : ' · ${e.category}'}',
                  subtitle: [shortDate(e.createdAt), ?e.notes].dotted(),
                  trailing: '− ${money(e.amount)}',
                ),
            ],
          ),
        HighlightCard(
          label:
              'إجمالي المستلم (${chosen.length} من ${widget.payments.length})',
          value: money(
            round2(sumPayments(chosen.map((p) => p.amount)) - _spent),
          ),
          lines: [
            for (final m in totalsByMethod(chosen))
              '${methodLabel(m.method)} (${m.count}): ${money(m.total)}',
            if (_spent > 0) 'مصروفات: − ${money(_spent)}',
          ],
        ),
        if (_spent > _cash)
          Note(
            'المصروفات أكبر من النقدي المستلم (${money(_cash)}). علّم على نقدي أكتر أو شيل مصروف.',
            tone: Tone.danger,
          ),
        FormCard(
          children: [
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: 'مثلاً: الشيكات اتسلمت للمحاسب',
            ),
          ],
        ),
        SubmitButton(
          label: 'تأكيد الاستلام',
          loading: _saving,
          onPressed: chosen.isEmpty || _spent > _cash ? null : _submit,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
