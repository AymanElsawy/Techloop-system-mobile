import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/customer.dart';
import '../../data/models/treasury.dart';
import '../../data/models/visit.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'visit_details_screen.dart';

typedef _Data = ({List<Customer> customers, List<ManagedUser> reps});

/// New visit. Reps always visit for themselves; managers pick the rep first and see that rep's region.
class VisitFormScreen extends StatelessWidget {
  const VisitFormScreen({super.key, this.customerId});

  /// Preselected customer (from the customer page).
  final String? customerId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final manager = context.isManager;
    return Scaffold(
      appBar: AppBar(title: const Text('زيارة جديدة')),
      body: AsyncView<_Data>(
        refreshable: false,
        load: () async {
          final (customers, users) = await (
            app.customers.list(),
            manager ? app.users.list() : Future.value(<ManagedUser>[]),
          ).wait;
          return (
            customers: customers.where((c) => c.status != 'REJECTED').toList(),
            reps: users.where((u) => u.isRep && u.isActive).toList(),
          );
        },
        builder: (context, d) => _Form(data: d, customerId: customerId),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.data, this.customerId});

  final _Data data;
  final String? customerId;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late String? _customerId = widget.customerId;
  String? _repId;
  String _purpose = 'SALE';
  DateTime _at = DateTime.now();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final manager = context.isManager;
    if (_customerId == null || (manager && _repId == null) || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final v = await context.app.visits.create(
        customerId: _customerId!,
        salesRepId: manager ? _repId : null,
        purpose: _purpose,
        scheduledAt: _at,
      );
      if (mounted) replace(context, VisitDetailsScreen(id: v.id));
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(e, 'تعذر إنشاء الزيارة. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    final rep = widget.data.reps.where((r) => r.id == _repId).firstOrNull;
    // A rep can only visit customers in their region; managers see the chosen rep's customers.
    final customers = !manager
        ? widget.data.customers
        : rep == null
        ? <Customer>[]
        : widget.data.customers
              .where((c) => rep.governorates.contains(c.governorate))
              .toList();

    return PageList(
      children: [
        FormCard(
          children: [
            if (manager)
              Select<String>(
                label: 'المندوب *',
                value: _repId,
                hint: 'اختر المندوب',
                items: {
                  for (final r in widget.data.reps)
                    r.id:
                        '${r.name}${r.governorates.isEmpty ? ' (بدون منطقة)' : ''}',
                },
                onChanged: (v) => setState(() => _repId = v),
              ),
            Select<String>(
              label: 'العميل *',
              value: customers.any((c) => c.id == _customerId)
                  ? _customerId
                  : null,
              hint: 'اختر العميل',
              items: {
                for (final c in customers) c.id: '${c.name} · ${c.governorate}',
              },
              onChanged: (v) => setState(() => _customerId = v),
            ),
            if (manager)
              Text(
                'تظهر عملاء محافظات المندوب المختار فقط.',
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            Text(
              'غرض الزيارة',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final e in visitPurposeLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _purpose == e.key,
                    onSelected: (_) => setState(() => _purpose = e.key),
                  ),
              ],
            ),
            DateField(
              label: 'التاريخ والوقت',
              value: _at,
              withTime: true,
              onChanged: (d) => setState(() => _at = d ?? DateTime.now()),
            ),
          ],
        ),
        SubmitButton(
          label: 'إنشاء الزيارة',
          loading: _saving,
          onPressed:
              _customerId != null &&
                  customers.any((c) => c.id == _customerId) &&
                  (!manager || _repId != null)
              ? _submit
              : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
