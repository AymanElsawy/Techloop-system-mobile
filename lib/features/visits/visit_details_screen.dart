import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../data/models/sales.dart';
import '../../data/models/visit.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../customers/customer_details_screen.dart';
import '../sales/collection_details_screen.dart';
import '../sales/collection_form_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/invoice_form_screen.dart';

typedef _Data = ({Visit visit, List<Invoice> invoices, List<Collection> collections});

/// Visit page: start (with GPS) / complete / cancel, the customer card, and the sales and
/// collections made during the visit.
class VisitDetailsScreen extends StatefulWidget {
  const VisitDetailsScreen({super.key, required this.id});

  final String id;

  @override
  State<VisitDetailsScreen> createState() => _VisitDetailsScreenState();
}

class _VisitDetailsScreenState extends State<VisitDetailsScreen> {
  final _ctl = AsyncController<_Data>();
  bool _busy = false;

  Future<_Data> _load() async {
    final app = context.app;
    final (visit, invoices, collections) = await (
      app.visits.get(widget.id),
      app.sales.invoices(visitId: widget.id),
      app.sales.collections(visitId: widget.id),
    ).wait;
    return (visit: visit, invoices: invoices, collections: collections);
  }

  Future<void> _run(Future<Visit> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _ctl.reload();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _ctl.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الزيارة')),
      body: AsyncView<_Data>(controller: _ctl, load: _load, errorText: 'حدث خطأ أثناء تحميل الزيارة.', builder: _body),
    );
  }

  Widget _body(BuildContext context, _Data d) {
    final v = d.visit;
    final repo = context.app.visits;
    final assigned = v.salesRep.id == context.user.id;
    final manager = context.isManager;
    final colors = context.colors;

    final active = [...d.invoices.where((i) => !i.cancelled)];
    final salesTotal = active.fold<num>(0, (s, i) => s + i.total);
    // Money received: up-front invoice payments + collections.
    final collected =
        active.fold<num>(0, (s, i) => s + i.paidAmount) +
        d.collections.where((c) => !c.cancelled).fold<num>(0, (s, c) => s + c.amount);

    return PageList(
      children: [
        PageHeader(
          title: 'زيارة ${visitPurposeLabels[v.purpose]}',
          badge: StatusBadge(visitStatusLabels[v.status]!, tone: statusTones[v.status]!),
          actions: [
            if (v.status == 'PLANNED' && assigned)
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(() async => repo.start(v.id, await currentLocation())),
                icon: const Icon(Icons.play_arrow),
                label: Text(_busy ? 'جاري بدء الزيارة...' : 'بدء الزيارة'),
              ),
            if (v.status == 'PLANNED' && (assigned || manager))
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final reason = await askReason(context, title: 'إلغاء الزيارة', minLength: 0);
                        if (reason != null) _run(() => repo.cancel(v.id, reason.isEmpty ? null : reason));
                      },
                child: const Text('إلغاء الزيارة'),
              ),
            if (v.status == 'IN_PROGRESS' && assigned)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final body = await showModalBottomSheet<Json>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => const _CompleteSheet(),
                        );
                        if (body != null) _run(() => repo.complete(v.id, body));
                      },
                icon: const Icon(Icons.check),
                label: const Text('إنهاء الزيارة'),
              ),
          ],
        ),
        InfoCard(
          items: [
            ('المندوب', v.salesRep.name),
            ('التاريخ', longDate(v.scheduledAt)),
            ('الوقت', time(v.scheduledAt)),
            if (v.startedAt != null) ...[
              ('وقت البداية', time(v.startedAt!)),
              ('الموقع', v.hasLocation ? 'تم التسجيل' : 'غير متاح'),
            ],
            if (v.completedAt != null) ('وقت الانتهاء', time(v.completedAt!)),
            if (v.nextVisitAt != null) ('الزيارة القادمة', longDate(v.nextVisitAt!)),
            if (v.notes != null) ('ملاحظات', v.notes!),
            if (v.productsDiscussed.isNotEmpty) ('المنتجات التي تمت مناقشتها', v.productsDiscussed.join('، ')),
            if (v.customerFeedback != null) ('ملاحظات العميل', v.customerFeedback!),
            if (v.cancelReason != null) ('سبب الإلغاء', v.cancelReason!),
          ],
        ),
        _CustomerCard(
          customer: v.customer,
          onOpen: () => _open(CustomerDetailsScreen(id: v.customer.id)),
        ),
        SectionCard(
          title: 'خلال الزيارة',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (v.status == 'IN_PROGRESS' && assigned) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _open(InvoiceFormScreen(customerId: v.customer.id, visitId: v.id)),
                            child: const Text('فاتورة بيع'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _open(CollectionFormScreen(customerId: v.customer.id, visitId: v.id)),
                            child: const Text('فاتورة تحصيل'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else if (v.status == 'PLANNED') ...[
                    Text(
                      'ابدأ الزيارة لتسجيل فاتورة بيع أو فاتورة تحصيل.',
                      style: TextStyle(fontSize: 12.5, color: colors.muted),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _SummaryRow(sales: salesTotal, collected: collected),
                ],
              ),
            ),
            for (final i in d.invoices)
              Tile(
                title: 'فاتورة بيع ${i.invoiceNumber}',
                dimmed: i.cancelled,
                trailing: money(i.total),
                onTap: () => _open(InvoiceDetailsScreen(id: i.id)),
              ),
            for (final c in d.collections)
              Tile(
                title: 'تحصيل ${c.receiptNumber}',
                dimmed: c.cancelled,
                trailing: money(c.amount),
                onTap: () => _open(CollectionDetailsScreen(id: c.id)),
              ),
            if (d.invoices.isEmpty && d.collections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('لا توجد فواتير أو تحصيلات في هذه الزيارة.', style: TextStyle(color: colors.muted)),
              ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sales, required this.collected});

  final num sales;
  final num collected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(String label, num value) => Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          Text(money(value), style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [cell('المبيعات', sales), cell('المحصّل', collected)]),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onOpen});

  final VisitCustomer customer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return InfoCard(
      items: [('العميل', c.name), ('العنوان', c.fullAddress), ('المديونية', money(c.debit))],
      footer: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('صفحة العميل'),
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
              label: const Text('عرض على الخريطة'),
            ),
        ],
      ),
    );
  }
}

/// إنهاء الزيارة: notes, products discussed (comma separated), customer feedback, next visit.
class _CompleteSheet extends StatefulWidget {
  const _CompleteSheet();

  @override
  State<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends State<_CompleteSheet> {
  final _notes = TextEditingController();
  final _products = TextEditingController();
  final _feedback = TextEditingController();
  DateTime? _next;

  @override
  Widget build(BuildContext context) {
    String? trimmed(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إنهاء الزيارة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Input(label: 'ملاحظات', controller: _notes, maxLines: 3),
            const SizedBox(height: 14),
            Input(label: 'المنتجات التي تمت مناقشتها', controller: _products, helper: 'افصل بين المنتجات بفاصلة.'),
            const SizedBox(height: 14),
            Input(label: 'ملاحظات العميل', controller: _feedback, maxLines: 3),
            const SizedBox(height: 14),
            DateField(
              label: 'موعد الزيارة القادمة',
              value: _next,
              withTime: true,
              onChanged: (d) => setState(() => _next = d),
            ),
            const SizedBox(height: 18),
            SubmitButton(
              label: 'حفظ وإنهاء الزيارة',
              onPressed: () => Navigator.pop<Json>(context, {
                'notes': ?trimmed(_notes),
                'productsDiscussed': [
                  for (final p in _products.text.split(RegExp('[,،\n]')))
                    if (p.trim().isNotEmpty) p.trim(),
                ],
                'customerFeedback': ?trimmed(_feedback),
                'nextVisitAt': ?_next?.toUtc().toIso8601String(),
              }),
            ),
          ],
        ),
      ),
    );
  }
}
