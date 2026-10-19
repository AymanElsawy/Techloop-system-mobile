import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// جرد: the manager types what is really in a bucket; the difference from the system balance
/// is saved as an adjustment. The first count of a bucket is its opening balance.
/// Pops `true` when saved.
class CountScreen extends StatefulWidget {
  const CountScreen({super.key, required this.summary});

  final TreasurySummary summary;

  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  final _form = GlobalKey<FormState>();
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  String? _method = 'CASH';
  bool _saving = false;
  String? _error;

  num get _balance =>
      widget.summary.byMethod
          .where((m) => m.method == _method)
          .firstOrNull
          ?.total ??
      0;

  num? get _diff {
    final counted = parseAmount(_counted.text);
    return counted == null ? null : round2(counted - _balance);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _method == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.treasury.count(
        _method!,
        round2(parseAmount(_counted.text)!),
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر حفظ الجرد. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final diff = _diff;
    return Scaffold(
      appBar: AppBar(title: const Text('جرد الخزنة')),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            Text(
              'اكتب المبلغ الموجود فعلًا. الفرق بيتسجل "تسوية جرد" والرصيد بيبقى زي اللي اتعدّ.',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
            FormCard(
              children: [
                Select<String>(
                  label: 'الخانة *',
                  value: _method,
                  items: {for (final m in moneyBuckets) m: bucketLabel(m)},
                  onChanged: (m) => setState(() => _method = m),
                ),
                Input(
                  label: 'المبلغ الفعلي *',
                  controller: _counted,
                  keyboard: Input.decimal,
                  ltr: true,
                  helper: 'رصيد السيستم: ${money(_balance)}',
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      parseAmount(v) == null ? 'أدخل المبلغ.' : null,
                ),
                if (diff != null)
                  Text(
                    diff == 0
                        ? 'مطابق، مفيش فرق.'
                        : '${diff > 0 ? 'زيادة' : 'عجز'} ${money(diff.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: diff < 0 ? colors.danger : null,
                    ),
                  ),
                Input(
                  label: 'ملاحظات',
                  controller: _notes,
                  hint: 'مثلاً: رصيد افتتاحي',
                ),
              ],
            ),
            SubmitButton(
              label: 'حفظ الجرد',
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
