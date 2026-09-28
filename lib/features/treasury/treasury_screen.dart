import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import 'deposit_details_screen.dart';
import 'handover_screen.dart';

typedef _Data = ({TreasurySummary? summary, List<Payment> pending, List<Deposit> deposits});

/// الخزنة. Managers: company treasury + money still with reps. A rep: their own cash box (خزنتي).
class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  final _ctl = AsyncController<_Data>();

  Future<_Data> _load() async {
    final t = context.app.treasury;
    final manager = context.isManager;
    final (summary, pending, deposits) = await (
      manager ? t.summary() : Future<TreasurySummary?>.value(),
      manager ? Future.value(<Payment>[]) : t.pending(),
      t.deposits(),
    ).wait;
    return (summary: summary, pending: pending, deposits: deposits);
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    return AsyncView<_Data>(
      controller: _ctl,
      load: _load,
      errorText: manager ? 'حدث خطأ أثناء تحميل الخزنة.' : 'حدث خطأ أثناء تحميل خزنتك.',
      builder: (context, d) {
        final colors = context.colors;
        return PageList(
          children: [
            if (d.summary case final s?) ...[
              HighlightCard(
                label: 'رصيد خزنة الشركة',
                value: money(s.total),
                lines: [for (final m in s.byMethod) '${methodLabel(m.method)} (${m.count}): ${money(m.total)}'],
              ),
              SectionCard(
                title: 'فلوس مع المناديب · ${money(sumPayments(s.pendingByRep.map((r) => r.total)))}',
                empty: 'كل الفلوس المحصّلة اتسلمت للخزنة.',
                children: [
                  for (final r in s.pendingByRep)
                    Tile(
                      title: r.rep.name,
                      subtitle: '${r.count} مستند',
                      trailing: money(r.total),
                      trailingHint: 'استلام',
                      trailingHintColor: colors.danger,
                      onTap: () => _open(HandoverScreen(repId: r.rep.id)),
                    ),
                ],
              ),
            ] else ...[
              HighlightCard(
                label: 'معك لم يُسلَّم للخزنة',
                value: money(sumPayments(d.pending.map((p) => p.amount))),
                lines: [
                  for (final m in totalsByMethod(d.pending)) '${methodLabel(m.method)} (${m.count}): ${money(m.total)}',
                ],
              ),
              Text(
                'المبالغ دي بتتخصم من مديونية العميل لما الإدارة تستلمها منك.',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
              PaymentsCard(title: 'المستندات اللي معاك', payments: d.pending, empty: 'مفيش فلوس معاك حاليًا.'),
            ],
            SectionCard(
              title: manager ? 'سجل الاستلام' : 'اللي سلّمته',
              empty: 'لا يوجد استلام بعد.',
              children: [
                for (final dep in d.deposits)
                  Tile(
                    title: 'استلام #${dep.number}',
                    subtitle: [
                      dateTime(dep.createdAt),
                      if (manager) dep.rep.name,
                      'استلمها ${dep.receivedBy.name}',
                    ].dotted(),
                    trailing: money(dep.total),
                    onTap: () => _open(DepositDetailsScreen(id: dep.id)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Money entries (invoice up-front payments and collections), optionally selectable.
class PaymentsCard extends StatelessWidget {
  const PaymentsCard({
    super.key,
    required this.title,
    required this.payments,
    this.empty = '',
    this.selected,
    this.onToggle,
    this.showRep = false,
  });

  final String title;
  final List<Payment> payments;
  final String empty;

  /// Selected `KIND:id` keys; null = not selectable.
  final Set<String>? selected;
  final ValueChanged<Payment>? onToggle;
  final bool showRep;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      empty: empty,
      children: [
        for (final p in payments)
          Tile(
            leading: selected == null
                ? null
                : Checkbox(value: selected!.contains(p.key), onChanged: (_) => onToggle!(p)),
            title: p.title,
            subtitle: [
              p.customer.name,
              shortDate(p.createdAt),
              methodLabel(p.paymentMethod),
              if (p.chequeNumber != null)
                'شيك ${p.chequeNumber}${p.chequeDueDate == null ? '' : ' · يستحق ${shortDate(p.chequeDueDate!)}'}',
              if (showRep) p.rep.name,
            ].dotted(),
            trailing: money(p.amount),
            onTap: selected != null
                ? () => onToggle!(p)
                : () => push(context, p.isInvoice ? InvoiceDetailsScreen(id: p.id) : CollectionDetailsScreen(id: p.id)),
          ),
      ],
    );
  }
}
