import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../data/models/sales.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../sales/collection_details_screen.dart';
import '../sales/collection_form_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/invoice_form_screen.dart';
import '../sales/return_details_screen.dart';
import '../sales/return_form_screen.dart';
import '../visits/visit_form_screen.dart';
import 'customer_form_screen.dart';

typedef _Data = ({Customer customer, List<StatementLine> statement});

/// Customer page: actions, approval, balances, info and the account statement (كشف حساب).
class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({super.key, required this.id});

  final String id;

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  final _ctl = AsyncController<_Data>();
  bool _busy = false;

  /// Statement lines shown; "عرض المزيد" adds [pageSize] more (the statement is built whole for the running balance).
  int _shown = pageSize;

  Future<_Data> _load() async {
    final app = context.app;
    // Reps only get their own invoices / collections / returns from the backend.
    final (customer, invoices, collections, returns) = await (
      app.customers.get(widget.id),
      app.sales.invoices(customerId: widget.id),
      app.sales.collections(customerId: widget.id),
      app.sales.returns(customerId: widget.id),
    ).wait;
    return (
      customer: customer,
      statement: buildStatement(invoices, collections, returns),
    );
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  Future<void> _review(Future<Customer> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _ctl.reload();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات العميل')),
      body: AsyncView<_Data>(
        controller: _ctl,
        load: _load,
        errorText: 'حدث خطأ أثناء تحميل بيانات العميل.',
        builder: (context, d) => _body(context, d.customer, d.statement),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Customer c,
    List<StatementLine> statement,
  ) {
    final colors = context.colors;
    final manager = context.isManager;
    final canSell = c.status != 'REJECTED';
    // Mirrors the backend: managers edit any customer; reps any non-rejected one.
    final canEdit = manager || c.status != 'REJECTED';
    final returns = statement
        .where((l) => l.kind == StatementKind.salesReturn && !l.cancelled)
        .toList();
    final returnsTotal = returns.fold<num>(0, (s, l) => s + l.credit);

    return PageList(
      children: [
        PageHeader(
          title: c.name,
          badge: StatusBadge(
            customerStatusLabels[c.status]!,
            tone: statusTones[c.status]!,
          ),
        ),
        const SizedBox(height: 12),
        _ActionGrid([
          if (canSell) ...[
            FilledButton.icon(
              onPressed: () => _open(InvoiceFormScreen(customerId: c.id)),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('فاتورة بيع'),
            ),
            OutlinedButton.icon(
              onPressed: () => _open(VisitFormScreen(customerId: c.id)),
              icon: const Icon(Icons.event_outlined, size: 18),
              label: const Text('زيارة جديدة'),
            ),
            OutlinedButton.icon(
              onPressed: () => _open(ReturnFormScreen(customerId: c.id)),
              icon: const Icon(Icons.keyboard_return_outlined, size: 18),
              label: const Text('فاتورة مرتجع'),
            ),
          ],
          FilledButton.icon(
            onPressed: () => _open(CollectionFormScreen(customerId: c.id)),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('فاتورة تحصيل'),
          ),
          if (manager)
            OutlinedButton.icon(
              onPressed: () =>
                  copyLink(context, context.app.customers.shareLink(c.id)),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('نسخ رابط المديونية'),
            ),
        ]),
        if (c.status == 'REJECTED' && c.rejectionReason != null)
          Note('سبب الرفض: ${c.rejectionReason}', tone: Tone.danger),
        if (manager && c.status != 'APPROVED')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'أضافه ${c.createdBy?.name ?? '—'} بتاريخ ${longDate(c.createdAt)}.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _review(
                                  () => context.app.customers.approve(c.id),
                                ),
                          child: const Text('اعتماد العميل'),
                        ),
                      ),
                      if (c.status == 'PENDING') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final repo = context.app.customers;
                                    final reason = await askReason(
                                      context,
                                      title: 'رفض العميل',
                                    );
                                    if (reason != null)
                                      _review(() => repo.reject(c.id, reason));
                                  },
                            child: const Text('رفض'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        StatGrid(
          children: [
            StatCard(
              label: 'مدين',
              value: money(c.debit),
              valueColor: c.debit > 0 ? colors.danger : null,
            ),
            StatCard(
              label: 'تحت التسليم',
              value: money(c.pendingPayments),
              valueColor: c.pendingPayments > 0 ? colors.warningFg : null,
              hint: 'مع المندوب، متخصومة من المديونية',
            ),
            if (c.paymentTermDays != null ||
                (c.discountPercent ?? 0) > 0 ||
                c.overdue > 0)
              StatCard(
                label: 'متأخرات',
                value: money(c.overdue),
                valueColor: c.overdue > 0 ? colors.danger : null,
                hint: [
                  c.paymentTermDays == null
                      ? 'بدون مدة سداد'
                      : 'السداد خلال ${c.paymentTermDays} يوم',
                  if ((c.discountPercent ?? 0) > 0)
                    'خصم ${number(c.discountPercent!)}%',
                ].join(' · '),
              ),
            if (c.creditLeft case final left?)
              StatCard(
                label: 'حد الائتمان',
                value: money(c.creditLimit!),
                valueColor: left <= 0 ? colors.danger : null,
                hint: left <= 0
                    ? 'وصل للحد: المندوب مش هيقدر يبيع آجل'
                    : 'متاح ${money(left)}',
              ),
            StatCard(label: 'دائن', value: money(c.credit)),
            StatCard(
              label: 'آخر فاتورة',
              value: c.lastInvoice == null ? '—' : money(c.lastInvoice!.amount),
              hint: c.lastInvoice == null
                  ? null
                  : longDate(c.lastInvoice!.date),
            ),
            StatCard(
              label: 'آخر تحصيل',
              value: c.lastCollection == null
                  ? '—'
                  : money(c.lastCollection!.amount),
              hint: c.lastCollection == null
                  ? null
                  : longDate(c.lastCollection!.date),
            ),
            StatCard(
              label: 'المرتجعات',
              value: money(returnsTotal),
              valueColor: returns.isNotEmpty ? colors.danger : null,
              hint: '${returns.length} فاتورة مرتجع',
            ),
          ],
        ),
        _InfoCard(
          customer: c,
          canEdit: canEdit,
          onEdit: () => _open(CustomerFormScreen(id: c.id)),
        ),
        SectionCard(
          title:
              '${manager ? 'كشف الحساب' : 'فواتيري وتحصيلاتي لهذا العميل'} · ${statement.length}',
          collapsible: true,
          empty: 'لا توجد فواتير أو تحصيلات أو مرتجعات لهذا العميل.',
          children: [
            for (final line in statement.take(_shown))
              _StatementTile(line: line, manager: manager, onOpen: _open),
            if (statement.length > _shown)
              TextButton(
                onPressed: () => setState(() => _shown += pageSize),
                child: Text('عرض المزيد (${statement.length - _shown})'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Lays action buttons two per row, each filling half the width.
class _ActionGrid extends StatelessWidget {
  const _ActionGrid(this.buttons);

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < buttons.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: buttons[i]),
              if (i + 1 < buttons.length) ...[
                const SizedBox(width: 8),
                Expanded(child: buttons[i + 1]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.customer,
    required this.canEdit,
    required this.onEdit,
  });

  final Customer customer;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoCard(
            items: [
              ('النوع', customerTypeLabels[c.type] ?? c.type),
              ('المحافظة / المدينة', c.place),
              ('العنوان', c.address ?? '—'),
            ],
            footer: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                if (c.phone != null)
                  OutlinedButton.icon(
                    onPressed: () => openUrl(context, 'tel:${c.phone}'),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text(c.phone!, textDirection: TextDirection.ltr),
                  ),
                if (c.location != null)
                  OutlinedButton.icon(
                    onPressed: () => openUrl(context, mapsUrl(c.location!)),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('الخريطة'),
                  ),
              ],
            ),
          ),
          ExpansionTile(
            title: Text(
              'بيانات أكتر',
              style: TextStyle(color: context.colors.muted, fontSize: 14),
            ),
            shape: const Border(),
            childrenPadding: EdgeInsets.zero,
            children: [
              InfoCard(
                items: [
                  ('الشخص المسؤول', c.contactPerson ?? '—'),
                  (
                    'أضافه',
                    '${c.createdBy?.name ?? '—'} · ${longDate(c.createdAt)}',
                  ),
                  if (c.reviewedBy != null)
                    (
                      'راجعه',
                      '${c.reviewedBy!.name} · ${longDate(c.reviewedAt!)}',
                    ),
                  if (c.notes != null) ('ملاحظات', c.notes!),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({
    required this.line,
    required this.manager,
    required this.onOpen,
  });

  final StatementLine line;
  final bool manager;
  final Future<void> Function(Widget) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = line;
    return Tile(
      title: '${l.kind.label} ${l.number}',
      subtitle: [
        shortDate(l.date),
        l.method,
        if (manager) l.createdBy,
      ].dotted(),
      dimmed: l.cancelled,
      badge: l.cancelled
          ? const StatusBadge('ملغاة', tone: Tone.danger)
          : l.bounced
          ? const StatusBadge('شيك مرتد', tone: Tone.danger)
          : l.pending
          ? const StatusBadge('تحت التسليم', tone: Tone.warning)
          : null,
      trailing: l.debit > 0
          ? 'عليه ${money(l.debit)}'
          : 'دفع ${money(l.credit)}',
      trailingColor: l.debit > 0 ? context.colors.danger : null,
      trailingHint: [
        if (l.debit > 0 && l.credit > 0) 'دفع ${money(l.credit)}',
        if (manager && l.balance != null) 'الرصيد ${money(l.balance!)}',
      ].dotted(),
      onTap: () => onOpen(switch (l.kind) {
        StatementKind.invoice => InvoiceDetailsScreen(id: l.id),
        StatementKind.collection => CollectionDetailsScreen(id: l.id),
        StatementKind.salesReturn => ReturnDetailsScreen(id: l.id),
      }),
    );
  }
}
