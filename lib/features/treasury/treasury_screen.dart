import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/offline.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import 'deposit_details_screen.dart';
import 'entry_form_screen.dart';
import 'rep_expense_screen.dart';
import 'handover_screen.dart';

typedef _Data = ({
  TreasurySummary? summary,
  List<Payment> pending,
  PageOf<Deposit> deposits, // latest [_preview]
  List<Payment> cheques,
  PageOf<TreasuryEntry>? outflows, // managers: latest [_preview]
  List<TreasuryEntry> entries, // a rep: their own expenses
  CashBox? cashBox, // a rep only
});

/// الخزنة. Managers: company treasury + money still with reps. A rep: their own cash box (خزنتي).
class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

/// Rows shown per section; the rest are behind "عرض الكل".
const _preview = 5;

class _TreasuryScreenState extends State<TreasuryScreen> {
  final _ctl = AsyncController<_Data>();

  Future<_Data> _load() async {
    final t = context.app.treasury;
    final manager = context.isManager;
    final (
      summary,
      pending,
      deposits,
      cheques,
      outflows,
      entries,
      cashBox,
    ) = await (
      manager ? t.summary() : Future<TreasurySummary?>.value(),
      manager ? Future.value(<Payment>[]) : t.pending(),
      t.deposits(1, limit: _preview),
      manager ? t.cheques() : Future.value(<Payment>[]),
      manager
          ? t.entriesPage(1, limit: _preview)
          : Future<PageOf<TreasuryEntry>?>.value(),
      manager ? Future.value(<TreasuryEntry>[]) : t.entries(),
      manager ? Future<CashBox?>.value() : t.cashBox(),
    ).wait;
    return (
      summary: summary,
      pending: pending,
      deposits: deposits,
      cheques: cheques,
      outflows: outflows,
      entries: entries,
      cashBox: cashBox,
    );
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    try {
      await action();
      await _ctl.reload();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e, fallback));
    }
  }

  /// "Cashed" moves the cheque to the bank; "bounced" puts it back on the customer's debt.
  Future<void> _cheque(Payment p) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'شيك ${p.chequeNumber ?? p.number} · ${money(p.amount)}',
              ),
              subtitle: Text(p.customer.name),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text('اتصرف'),
              subtitle: const Text('يتنقل للبنك'),
              onTap: () => Navigator.pop(context, 'CLEARED'),
            ),
            ListTile(
              leading: Icon(Icons.undo, color: context.colors.danger),
              title: Text(
                'مرتد',
                style: TextStyle(color: context.colors.danger),
              ),
              subtitle: const Text(
                'يطلع من الخزنة ومبلغه يرجع على مديونية العميل',
              ),
              onTap: () => Navigator.pop(context, 'BOUNCED'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('فتح المستند'),
              onTap: () => Navigator.pop(context, 'OPEN'),
            ),
          ],
        ),
      ),
    );
    if (status == null || !mounted) return;
    if (status == 'OPEN') {
      return _open(
        p.isInvoice
            ? InvoiceDetailsScreen(id: p.id)
            : CollectionDetailsScreen(id: p.id),
      );
    }
    await _run(
      () => context.app.treasury.setChequeStatus(p, status),
      'تعذر تحديث الشيك. حدّث الصفحة وحاول مرة أخرى.',
    );
  }

  Future<void> _cancelEntry(TreasuryEntry e) async {
    final reason = await askReason(
      context,
      title: 'إلغاء ${entryTypeLabels[e.type]} #${e.number}',
    );
    if (reason == null || !mounted) return;
    await _run(
      () => context.app.treasury.cancelEntry(e.id, reason),
      'تعذر الإلغاء. حاول مرة أخرى.',
    );
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  Widget _entryTile(TreasuryEntry e, [VoidCallback? onCancelled]) {
    final colors = context.colors;
    return Tile(
      title:
          '${e.rep == null ? entryTypeLabels[e.type] : 'مصروف مندوب'} #${e.number}${e.category == null ? '' : ' · ${e.category}'}',
      subtitle: [
        dateTime(e.createdAt),
        'من ${bucketLabel(e.paymentMethod)}',
        e.createdBy.name,
        if (e.cancelReason != null)
          'سبب الإلغاء: ${e.cancelReason}'
        else
          ?e.notes,
      ].dotted(),
      dimmed: e.cancelled,
      badge: e.cancelled
          ? const StatusBadge('ملغاة', tone: Tone.danger)
          : e.pending
          ? const StatusBadge('مع المندوب', tone: Tone.warning)
          : null,
      trailing: money(e.amount),
      trailingHint: e.cancelled ? null : 'إلغاء',
      trailingHintColor: colors.danger,
      onTap: e.cancelled
          ? null
          : () => _cancelEntry(e).then((_) => onCancelled?.call()),
    );
  }

  Widget _depositTile(Deposit dep) => Tile(
    title: 'استلام #${dep.number}',
    subtitle: [
      dateTime(dep.createdAt),
      if (context.isManager) dep.rep.name,
      'استلمها ${dep.receivedBy.name}',
    ].dotted(),
    trailing: money(dep.total),
    onTap: () => _open(DepositDetailsScreen(id: dep.id)),
  );

  /// "عرض الكل (N)" when a section shows only part of its rows.
  Widget? _showAll<T>(
    PageOf<T> page,
    String title,
    Future<PageOf<T>> Function(int page) load,
    Widget Function(T item, PagedController list) tile,
  ) {
    if (page.total <= page.items.length) return null;
    return TextButton(
      onPressed: () {
        final list = PagedController();
        _open(
          PagedScreen<T>(
            title: title,
            controller: list,
            load: load,
            emptyText: 'لا يوجد.',
            itemBuilder: (context, item) =>
                Card(clipBehavior: Clip.antiAlias, child: tile(item, list)),
          ),
        );
      },
      child: Text('عرض الكل (${page.total})'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    return AsyncView<_Data>(
      controller: _ctl,
      load: _load,
      errorText: manager
          ? 'حدث خطأ أثناء تحميل الخزنة.'
          : 'حدث خطأ أثناء تحميل خزنتك.',
      builder: (context, d) {
        final colors = context.colors;
        return PageList(
          children: [
            if (d.summary case final s?) ...[
              HighlightCard(
                label: 'رصيد خزنة الشركة',
                value: money(s.total),
                lines: [
                  for (final m in s.byMethod)
                    '${bucketLabel(m.method)}: ${money(m.total)}',
                  'بعد خصم المصروفات والسحب ومدفوعات الموردين (من 30/9/2026).',
                ],
              ),
              SectionCard(
                title: 'صرف من الخزنة',
                collapsible: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in entryTypes)
                          OutlinedButton(
                            onPressed: () async {
                              final saved = await push<bool>(
                                context,
                                EntryFormScreen(type: type, summary: s),
                              );
                              if (saved == true) _ctl.reload();
                            },
                            child: Text(entryTypeLabels[type]!),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SectionCard(
                title:
                    'فلوس مع المناديب (${s.pendingByRep.length}) · ${money(sumPayments(s.pendingByRep.map((r) => r.total)))}',
                collapsible: true,
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
              SectionCard(
                title: 'شيكات في الخزنة (${d.cheques.length})',
                collapsible: true,
                empty: 'مفيش شيكات في الخزنة.',
                children: [
                  for (final p in d.cheques)
                    Tile(
                      title: 'شيك ${p.chequeNumber ?? ''}'.trim(),
                      subtitle: [
                        p.customer.name,
                        p.title,
                        if (p.chequeDueDate != null)
                          'يستحق ${shortDate(p.chequeDueDate!)}',
                      ].dotted(),
                      trailing: money(p.amount),
                      trailingHint: 'اتصرف / مرتد',
                      onTap: () => _cheque(p),
                    ),
                ],
              ),
              SectionCard(
                title: 'حركات الصرف (${d.outflows!.total})',
                collapsible: true,
                empty: 'لا يوجد صرف بعد.',
                trailing: _showAll<TreasuryEntry>(
                  d.outflows!,
                  'حركات الصرف',
                  context.app.treasury.entriesPage,
                  (e, list) => _entryTile(e, list.reload),
                ),
                children: [for (final e in d.outflows!.items) _entryTile(e)],
              ),
            ] else ...[
              HighlightCard(
                label: 'معك لم يُسلَّم للخزنة',
                value: money(
                  d.cashBox?.total ??
                      sumPayments(d.pending.map((p) => p.amount)),
                ),
                lines: [
                  for (final m in totalsByMethod(d.pending))
                    '${methodLabel(m.method)} (${m.count}): ${money(m.total)}',
                  if ((d.cashBox?.expenses ?? 0) > 0)
                    'مصروفات: − ${money(d.cashBox!.expenses)}',
                ],
              ),
              Text(
                'المبالغ دي بتتخصم من مديونية العميل لما الإدارة تستلمها منك.',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
              PaymentsCard(
                title: 'في عهدتك',
                payments: d.pending,
                empty: 'مفيش فلوس معاك حاليًا.',
              ),
              const _Unsent(),
              SectionCard(
                title: 'مصروفاتي',
                trailing: TextButton.icon(
                  onPressed: (d.cashBox?.cash ?? 0) <= 0
                      ? null
                      : () async {
                          final saved = await push<bool>(
                            context,
                            RepExpenseScreen(cash: d.cashBox!.cash),
                          );
                          if (saved == true) _ctl.reload();
                        },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('مصروف'),
                ),
                empty:
                    'من النقدية اللي معاك (${money(d.cashBox?.cash ?? 0)} متاح). بيتخصم وقت التسليم.',
                children: [
                  for (final e in d.entries)
                    Tile(
                      title:
                          '#${e.number}${e.category == null ? '' : ' · ${e.category}'}',
                      subtitle: [shortDate(e.createdAt), ?e.notes].dotted(),
                      dimmed: e.cancelled,
                      badge: e.cancelled
                          ? const StatusBadge('ملغي', tone: Tone.danger)
                          : e.pending
                          ? const StatusBadge(
                              'مستني الاستلام',
                              tone: Tone.warning,
                            )
                          : StatusBadge(
                              'اتقبل · استلام #${e.depositNumber ?? ''}',
                              tone: Tone.success,
                            ),
                      trailing: money(e.amount),
                      trailingHint: !e.cancelled && e.pending ? 'إلغاء' : null,
                      trailingHintColor: colors.danger,
                      onTap: !e.cancelled && e.pending
                          ? () => _cancelEntry(e)
                          : null,
                    ),
                ],
              ),
            ],
            SectionCard(
              title:
                  '${manager ? 'سجل الاستلام' : 'اللي سلّمته'} (${d.deposits.total})',
              collapsible: true,
              empty: 'لا يوجد استلام بعد.',
              trailing: _showAll<Deposit>(
                d.deposits,
                manager ? 'سجل الاستلام' : 'اللي سلّمته',
                context.app.treasury.deposits,
                (dep, _) => _depositTile(dep),
              ),
              children: [for (final dep in d.deposits.items) _depositTile(dep)],
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
                : Checkbox(
                    value: selected!.contains(p.key),
                    onChanged: (_) => onToggle!(p),
                  ),
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
                : () => push(
                    context,
                    p.isInvoice
                        ? InvoiceDetailsScreen(id: p.id)
                        : CollectionDetailsScreen(id: p.id),
                  ),
          ),
      ],
    );
  }
}

/// Collections saved on the phone while offline: with the rep, but not on the server yet.
class _Unsent extends StatelessWidget {
  const _Unsent();

  @override
  Widget build(BuildContext context) {
    final session = context.app.session;
    final store = session.store;
    if (store == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: store.queue,
      builder: (context, _, _) {
        final ops = [
          for (final op in store.queueOf(session.user?.id))
            if (op.meta['kind'] == 'COLLECTION' || op.meta['kind'] == 'EXPENSE')
              op,
        ];
        if (ops.isEmpty) return const SizedBox.shrink();
        num signed(PendingOp o) =>
            (o.meta['kind'] == 'EXPENSE' ? -1 : 1) * (o.meta['amount'] as num);
        return SectionCard(
          title: 'لم يُرسل بعد · ${money(sumPayments(ops.map(signed)))}',
          titleColor: context.colors.warningFg,
          children: [
            for (final op in ops)
              Tile(
                title: op.label,
                subtitle: [
                  dateTime(op.createdAt),
                  if (op.meta['kind'] == 'COLLECTION')
                    methodLabel(op.meta['paymentMethod'] as String?),
                  op.error ?? 'هيتبعت أول ما النت يرجع',
                ].dotted(),
                trailing:
                    '${op.meta['kind'] == 'EXPENSE' ? '− ' : ''}${money(op.meta['amount'] as num)}',
                badge: op.error == null
                    ? null
                    : const StatusBadge('اترفض', tone: Tone.danger),
              ),
          ],
        );
      },
    );
  }
}
