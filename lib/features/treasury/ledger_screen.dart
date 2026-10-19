import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../widgets/form.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../inventory/movement_list.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../suppliers/supplier_details_screen.dart';
import 'deposit_details_screen.dart';

/// حركة الخزنة: every movement of real money with a running balance. Managers.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  String _method = '';
  DateTime? _from;
  DateTime? _to;

  Widget? _target(LedgerRow r) => switch (r.refType) {
    'DEPOSIT' => DepositDetailsScreen(id: r.refId!),
    'INVOICE' => InvoiceDetailsScreen(id: r.refId!),
    'COLLECTION' => CollectionDetailsScreen(id: r.refId!),
    'SUPPLIER' => SupplierDetailsScreen(id: r.refId!),
    'MOVEMENT' => MovementDetailsScreen(id: r.refId!),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('حركة الخزنة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                ChoiceBar<String>(
                  options: {
                    '': 'الكل',
                    for (final m in moneyBuckets) m: bucketLabel(m),
                  },
                  value: _method,
                  onChanged: (m) => setState(() => _method = m),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DateField(
                        label: 'من',
                        value: _from,
                        onChanged: (d) => setState(() => _from = d),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DateField(
                        label: 'إلى',
                        value: _to,
                        onChanged: (d) => setState(() => _to = d),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<LedgerRow>(
              key: ValueKey(
                '$_method|$_from|$_to',
              ), // new filters: reload from page 1
              load: (page) => context.app.treasury.ledger(
                page,
                method: _method.isEmpty ? null : _method,
                from: _from == null ? null : isoDay(_from!),
                to: _to == null ? null : isoDay(_to!),
              ),
              emptyText: 'مفيش حركة في الفترة دي.',
              errorText: 'حدث خطأ أثناء تحميل الحركة.',
              header: (context, last) {
                final l = last as LedgerPage;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StatGrid(
                    children: [
                      StatCard(
                        label: 'رصيد أول المدة',
                        value: money(l.opening),
                      ),
                      StatCard(label: 'داخل', value: money(l.inflow)),
                      StatCard(
                        label: 'خارج',
                        value: money(l.outflow),
                        valueColor: colors.danger,
                      ),
                      StatCard(
                        label: 'رصيد آخر المدة',
                        value: money(l.closing),
                      ),
                    ],
                  ),
                );
              },
              itemBuilder: (context, r) {
                final target = _target(r);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Tile(
                    title: r.title,
                    subtitle: [
                      dateTime(r.date),
                      bucketLabel(r.method),
                      ?r.party,
                    ].dotted(),
                    trailing:
                        '${r.amount > 0 ? '+' : '−'} ${money(r.amount.abs())}',
                    trailingColor: r.amount < 0 ? colors.danger : null,
                    trailingHint: 'الرصيد ${money(r.balance)}',
                    onTap: target == null ? null : () => push(context, target),
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
