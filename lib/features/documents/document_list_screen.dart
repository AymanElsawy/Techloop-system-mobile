import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../../widgets/async_view.dart';
import '../inventory/stock_move_screen.dart';
import '../sales/collection_details_screen.dart';
import '../sales/collection_form_screen.dart';
import '../sales/invoice_form_screen.dart';
import '../sales/return_form_screen.dart';
import '../treasury/handover_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/return_details_screen.dart';
import '../treasury/deposit_details_screen.dart';
import 'document_pdf_screen.dart';
import 'purchase_screen.dart';

/// App page with the full details of a document; movements have none (the PDF is their details).
Widget? documentDetailsScreen(String type, String id) => switch (type) {
  'SALE' => InvoiceDetailsScreen(id: id),
  'COLLECTION' => CollectionDetailsScreen(id: id),
  'SALE_RETURN' => ReturnDetailsScreen(id: id),
  'DEPOSIT' => DepositDetailsScreen(id: id),
  _ => null,
};

/// الفواتير: every printable document (sales, returns, collections, purchases, custody moves, handovers).
class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  Timer? _debounce;
  String? _type;
  DateTimeRange? _period;
  String _query = '';
  int _reload = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Opens the existing form of [type]; sales, returns, collections and handovers pick their customer / rep first.
  Future<void> _create(String type) async {
    final party = switch (type) {
      'SALE' || 'SALE_RETURN' || 'COLLECTION' => 'customer',
      'DEPOSIT' => 'rep',
      _ => null,
    };
    final id = party == null ? '' : await pickParty(context, type);
    if (id == null || !mounted) return;
    await push(context, switch (type) {
      'SALE' => InvoiceFormScreen(customerId: id),
      'SALE_RETURN' => ReturnFormScreen(customerId: id),
      'COLLECTION' => CollectionFormScreen(customerId: id),
      'DEPOSIT' => HandoverScreen(repId: id),
      'PURCHASE' => const PurchaseScreen(),
      _ => StockMoveScreen(
        type: type,
      ), // ISSUE / RETURN: warehouse picked in the form
    });
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    // Reps never see purchases.
    final types = [
      for (final t in documentTypes)
        if (manager || t != 'PURCHASE') t,
    ];
    return Scaffold(
      floatingActionButton: manager
          ? FloatingActionButton.extended(
              onPressed: () async {
                final type = _type ?? await _pickType(context, types);
                if (type != null) await _create(type);
              },
              icon: const Icon(Icons.add),
              label: Text(
                _type == null ? 'مستند جديد' : documentTypeLabels[_type]!,
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'رقم المستند أو الاسم',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => setState(() => _query = v.trim()),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ChoiceBar<String?>(
                  leading: PeriodChip(
                    value: _period,
                    onChanged: (r) => setState(() => _period = r),
                  ),
                  options: {
                    null: 'الكل',
                    for (final t in types) t: documentTypeLabels[t]!,
                  },
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView<DocumentRow>(
              key: ValueKey((_type, _period, _query, _reload)),
              load: (page) => context.app.documents.page(
                page,
                type: _type,
                from: _period == null ? null : isoDay(_period!.start),
                to: _period == null ? null : isoDay(_period!.end),
                search: _query,
              ),
              errorText: 'حدث خطأ أثناء تحميل الفواتير.',
              emptyText: 'مفيش مستندات مطابقة.',
              // Room for the FAB under the last card.
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              // Totals cover every page (from the backend).
              header: (context, last) {
                final sum = last.sum ?? 0;
                return Text(
                  '${last.total} مستند${_type != null && sum > 0 ? ' · الإجمالي (بدون الملغي): ${money(sum)}' : ''}',
                  style: TextStyle(color: context.colors.muted, fontSize: 13),
                );
              },
              itemBuilder: (context, d) => _DocumentCard(doc: d),
            ),
          ),
        ],
      ),
    );
  }
}

/// Which document to create when no type filter is picked.
Future<String?> _pickType(BuildContext context, List<String> types) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in types)
                ListTile(
                  title: Text(documentTypeLabels[t]!),
                  onTap: () => Navigator.pop(context, t),
                ),
            ],
          ),
        ),
      ),
    );

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc});

  final DocumentRow doc;

  @override
  Widget build(BuildContext context) {
    final d = doc;
    final details = documentDetailsScreen(d.type, d.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Tile(
        dimmed: d.cancelled,
        title: '${documentTypeLabels[d.type]} ${d.number}',
        // Two lines: the type is already in the title, who issued it is in the details / PDF.
        subtitle: [d.party?.name ?? '—', shortDate(d.date)].dotted(),
        badge: d.cancelled
            ? const StatusBadge('ملغاة', tone: Tone.danger)
            : null,
        trailing: d.amount != null
            ? money(d.amount!)
            : '${number(d.quantity ?? 0)} قطعة',
        trailingHint: details == null ? 'PDF' : null,
        onTap: () =>
            push(context, details ?? DocumentPdfScreen(type: d.type, id: d.id)),
      ),
    );
  }
}

/// Customers (or sales reps for DEPOSIT) to pick from; returns the picked id.
Future<String?> pickParty(BuildContext context, String type) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PartyPicker(type: type),
    );

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.type});

  final String type;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  String _query = '';

  bool get _rep => widget.type == 'DEPOSIT';

  Future<List<({String id, String name, String? hint})>> _load() async {
    final app = context.app;
    if (_rep) {
      return [
        for (final u in await app.users.list())
          if (u.isRep && u.isActive) (id: u.id, name: u.name, hint: null),
      ];
    }
    return [
      for (final c in await app.customers.list())
        // Rejected customers can still pay (collection) but not buy or return.
        if (widget.type == 'COLLECTION' || c.status != 'REJECTED')
          (id: c.id, name: c.name, hint: c.governorate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: _rep ? 'اختر المندوب' : 'اختر العميل',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: AsyncView(
              refreshable: false,
              load: _load,
              builder: (context, list) {
                final rows = [
                  for (final p in list)
                    if (p.name.contains(_query)) p,
                ];
                return ListView(
                  children: [
                    for (final p in rows)
                      ListTile(
                        title: Text(p.name),
                        subtitle: p.hint == null ? null : Text(p.hint!),
                        onTap: () => Navigator.pop(context, p.id),
                      ),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('مفيش نتايج.')),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
