import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../sales/sales_widgets.dart';
import 'treasury_screen.dart';

/// One handover (استلام) with its payments.
class DepositDetailsScreen extends StatelessWidget {
  const DepositDetailsScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استلام')),
      body: AsyncView<Deposit>(
        load: () => context.app.treasury.deposit(id),
        builder: (context, d) => PageList(
          children: [
            PageHeader(
              title: 'استلام #${d.number}',
              actions: [PrintButton(type: 'DEPOSIT', id: d.id, label: 'طباعة إيصال / PDF')],
            ),
            InfoCard(
              items: [
                ('المندوب', d.rep.name),
                ('استلمها', d.receivedBy.name),
                ('التاريخ', dateTime(d.createdAt)),
                ('الإجمالي', money(d.total)),
                for (final m in totalsByMethod(d.payments)) (methodLabel(m.method), money(m.total)),
                if (d.notes != null) ('ملاحظات', d.notes!),
              ],
            ),
            PaymentsCard(title: 'المستندات', payments: d.payments),
          ],
        ),
      ),
    );
  }
}
