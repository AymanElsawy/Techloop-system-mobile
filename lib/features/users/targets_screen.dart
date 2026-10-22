import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'rep_details_screen.dart';
import 'targets_pdf_screen.dart';

/// المناديب (managers): each rep's monthly / yearly targets, progress and commission; tap a rep for everything about them.
class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key});

  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  final _ctl = PagedController();
  var _period = TargetPeriod.thisMonth();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _query = v.trim()),
    );
  }

  /// A new period gets a new list (the list's key).
  void _setPeriod(TargetPeriod p) => setState(() => _period = p);

  Future<void> _edit(TargetRow r) async {
    final data = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _TargetDialog(rep: r),
    );
    if (data == null || !mounted) return;
    try {
      await context.app.users.update(r.id, data);
      if (!mounted) return;
      toast(context, 'تم حفظ تارجت ${r.name}.');
      _ctl.reload();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e, 'تعذر حفظ التارجت.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: _onSearch,
            decoration: const InputDecoration(
              hintText: 'بحث باسم المندوب',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: PagedListView<TargetRow>(
            key: ValueKey((_period.key, _period.yearly, _query)),
            controller: _ctl,
            load: (page) =>
                context.app.users.targetsPage(_period, page, search: _query),
            emptyText: _query.isEmpty
                ? 'مفيش مناديب.'
                : 'مفيش مناديب مطابقين للبحث.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            header: (context, last) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Same as the top of the web page: period, then print all reps.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChoiceBar<bool>(
                          options: const {false: 'شهري', true: 'سنوي'},
                          value: _period.yearly,
                          onChanged: (yearly) =>
                              _setPeriod(_period.withYearly(yearly)),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              tooltip: _period.yearly
                                  ? 'السنة السابقة'
                                  : 'الشهر السابق',
                              onPressed: () => _setPeriod(_period.shift(-1)),
                            ),
                            Expanded(
                              child: Text(
                                _period.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              tooltip: _period.yearly
                                  ? 'السنة التالية'
                                  : 'الشهر التالي',
                              onPressed: _period.isCurrent
                                  ? null
                                  : () => _setPeriod(_period.shift(1)),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              push(context, TargetsPdfScreen(period: _period)),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('طباعة تقرير كل المناديب'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Every matching rep, not only the loaded ones.
                HighlightCard(
                  label: 'إجمالي العمولات',
                  value: money(last.sum ?? 0),
                ),
                const SizedBox(height: 8),
                Text(
                  'المبيعات بعد خصم المرتجعات، والتحصيل من غير الشيكات المرتدة. العمولة = نسبة من صافي المبيعات + نسبة من التحصيل.',
                  style: TextStyle(fontSize: 12, color: context.colors.muted),
                ),
              ],
            ),
            itemBuilder: (context, r) => _RepCard(
              rep: r,
              onEdit: () => _edit(r),
              onOpen: () => push(
                context,
                RepDetailsScreen(id: r.id, name: r.name, period: _period),
              ),
              onPrint: () =>
                  push(context, TargetsPdfScreen(period: _period, repId: r.id)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RepCard extends StatelessWidget {
  const _RepCard({
    required this.rep,
    required this.onEdit,
    required this.onOpen,
    required this.onPrint,
  });

  final TargetRow rep;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final r = rep;
    final muted = TextStyle(fontSize: 12.5, color: context.colors.muted);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  if (!r.isActive)
                    const StatusBadge('موقوف', tone: Tone.danger),
                  IconButton(
                    icon: const Icon(Icons.print_outlined),
                    tooltip: 'طباعة تقرير ${r.name}',
                    onPressed: onPrint,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'تعديل تارجت ${r.name}',
                    onPressed: onEdit,
                  ),
                ],
              ),
              if (r.hasMonthly || r.hasYearly)
                Text(
                  [
                    if (r.hasMonthly) 'تارجت شهري',
                    if (r.hasYearly) 'تارجت سنوي',
                  ].join(' · '),
                  style: muted,
                ),
              _Progress(
                label: 'المبيعات',
                value: r.netSales,
                target: r.salesGoal,
                progress: r.salesProgress,
              ),
              if (r.returns > 0)
                Text('مرتجع ${money(r.returns)}', style: muted),
              const SizedBox(height: 10),
              _Progress(
                label: 'التحصيل',
                value: r.collected,
                target: r.collectionGoal,
                progress: r.collectionProgress,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'عمولة ${number(r.salesCommissionRate)}% مبيعات · ${number(r.collectionCommissionRate)}% تحصيل',
                      style: muted,
                    ),
                  ),
                  Text(
                    money(r.commission),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.value,
    required this.target,
    required this.progress,
  });

  final String label;
  final num value;
  final num? target;
  final int? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final color = p == null
        ? c.muted
        : p >= 100
        ? c.successFg
        : p >= 50
        ? c.warningFg
        : c.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('$label: ${money(value)}')),
            Text(
              target == null
                  ? 'بدون تارجت'
                  : '${number(p!)}% من ${money(target!)}',
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (p != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (p / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: c.border,
            ),
          ),
        ],
      ],
    );
  }
}

/// Returns the PATCH body, or null on cancel. Empty target = no target.
class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.rep});

  final TargetRow rep;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  final _form = GlobalKey<FormState>();
  late final _sales = TextEditingController(
    text: _text(widget.rep.salesTarget),
  );
  late final _collection = TextEditingController(
    text: _text(widget.rep.collectionTarget),
  );
  late final _yearlySales = TextEditingController(
    text: _text(widget.rep.yearlySalesTarget),
  );
  late final _yearlyCollection = TextEditingController(
    text: _text(widget.rep.yearlyCollectionTarget),
  );
  late final _salesRate = TextEditingController(
    text: _text(widget.rep.salesCommissionRate),
  );
  late final _collectionRate = TextEditingController(
    text: _text(widget.rep.collectionCommissionRate),
  );

  static String _text(num? v) => v == null || v == 0 ? '' : '$v';

  static String? _rate(String v) {
    final n = parseAmount(v);
    return v.trim().isNotEmpty && (n == null || n > 100)
        ? 'من 0 لـ 100.'
        : null;
  }

  static String? _amount(String v) =>
      v.trim().isNotEmpty && parseAmount(v) == null ? 'رقم غير صحيح.' : null;

  @override
  void dispose() {
    for (final c in [
      _sales,
      _collection,
      _yearlySales,
      _yearlyCollection,
      _salesRate,
      _collectionRate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تارجت ${widget.rep.name}'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, controller, validator) in [
                ('تارجت المبيعات (شهري)', _sales, _amount),
                ('تارجت التحصيل (شهري)', _collection, _amount),
                ('تارجت المبيعات (سنوي)', _yearlySales, _amount),
                ('تارجت التحصيل (سنوي)', _yearlyCollection, _amount),
                ('عمولة المبيعات %', _salesRate, _rate),
                ('عمولة التحصيل %', _collectionRate, _rate),
              ]) ...[
                // A label above: Input's placeholder disappears once the field has a value.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Input(
                  label: label.contains('%') ? '0' : 'بدون',
                  controller: controller,
                  keyboard: Input.decimal,
                  ltr: true,
                  validator: validator,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            num? target(TextEditingController c) =>
                parseAmount(c.text) == 0 ? null : parseAmount(c.text);
            Navigator.pop(context, {
              'salesTarget': target(_sales),
              'collectionTarget': target(_collection),
              'yearlySalesTarget': target(_yearlySales),
              'yearlyCollectionTarget': target(_yearlyCollection),
              'salesCommissionRate': parseAmount(_salesRate.text) ?? 0,
              'collectionCommissionRate':
                  parseAmount(_collectionRate.text) ?? 0,
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
