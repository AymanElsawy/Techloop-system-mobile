import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/visit.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'visit_details_screen.dart';
import 'visit_form_screen.dart';

enum _Period {
  today('اليوم', 'لا توجد زيارات اليوم.'),
  week('الأسبوع', 'لا توجد زيارات هذا الأسبوع.'),
  all('الكل', 'لا توجد زيارات.');

  const _Period(this.label, this.empty);
  final String label;
  final String empty;

  /// Week starts on Saturday.
  (DateTime?, DateTime?) range() {
    if (this == all) return (null, null);
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, now.day);
    if (this == week)
      from = from.subtract(Duration(days: (from.weekday + 1) % 7));
    return (from, from.add(Duration(days: this == week ? 7 : 1)));
  }
}

class VisitListScreen extends StatefulWidget {
  const VisitListScreen({super.key});

  @override
  State<VisitListScreen> createState() => _VisitListScreenState();
}

class _VisitListScreenState extends State<VisitListScreen> {
  final _list = PagedController();
  _Period _period = _Period.today;
  String? _status;

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _list.reload();
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _period.range();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const VisitFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('زيارة جديدة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                SegmentedButton<_Period>(
                  showSelectedIcon: false,
                  segments: [
                    for (final p in _Period.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
                const SizedBox(height: 8),
                Select<String?>(
                  label: 'الحالة',
                  value: _status,
                  items: {null: 'كل الحالات', ...visitStatusLabels},
                  onChanged: (v) => setState(() => _status = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<Visit>(
              key: ValueKey((_period, _status)),
              controller: _list,
              load: (page) => context.app.visits.page(
                page,
                from: from,
                to: to,
                status: _status,
              ),
              errorText: 'حدث خطأ أثناء تحميل الزيارات.',
              emptyText: _period.empty,
              itemBuilder: (context, v) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Tile(
                    title: v.customer.name,
                    subtitle: [
                      visitPurposeLabels[v.purpose]!,
                      v.customer.governorate,
                      if (context.isManager) v.salesRep.name,
                      '${dayMonth(v.scheduledAt)} ${time(v.scheduledAt)}',
                    ].dotted(),
                    badge: StatusBadge(
                      visitStatusLabels[v.status]!,
                      tone: statusTones[v.status]!,
                    ),
                    onTap: () => _open(VisitDetailsScreen(id: v.id)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
