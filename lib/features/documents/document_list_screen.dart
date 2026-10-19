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

const _typeTones = {
  'SALE': Tone.success,
  'SALE_RETURN': Tone.danger,
  'COLLECTION': Tone.info,
  'PURCHASE': Tone.warning,
  'ISSUE': Tone.neutral,
  'RETURN': Tone.neutral,
  'DEPOSIT': Tone.success,
};

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
  DateTime? _from;
  DateTime? _to;
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
    final id = party == null ? '' : await _pickParty(context, type);
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
    return Column(
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
              if (manager) ...[
                if (_type case final type?) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _create(type),
                    icon: const Icon(Icons.add),
                    label: Text('إنشاء ${documentTypeLabels[type]}'),
                  ),
                ],
              ],
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
              const SizedBox(height: 8),
              ChoiceBar<String?>(
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
            key: ValueKey((_type, _from, _to, _query, _reload)),
            load: (page) => context.app.documents.page(
              page,
              type: _type,
              from: _from == null ? null : isoDay(_from!),
              to: _to == null ? null : isoDay(_to!),
              search: _query,
            ),
            errorText: 'حدث خطأ أثناء تحميل الفواتير.',
            emptyText: 'مفيش مستندات مطابقة.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
    );
  }
}

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
        subtitle: [
          '${documentPartyLabels[d.type]}: ${d.party?.name ?? '—'}',
          dateTime(d.date),
          if (d.by != null) d.by!.name,
        ].dotted(),
        badge: d.cancelled
            ? const StatusBadge('ملغاة', tone: Tone.danger)
            : StatusBadge(_short(d.type), tone: _typeTones[d.type]!),
        trailing: d.amount != null
            ? money(d.amount!)
            : '${number(d.quantity ?? 0)} قطعة',
        trailingHint: details == null ? 'PDF' : null,
        onTap: () =>
            push(context, details ?? DocumentPdfScreen(type: d.type, id: d.id)),
      ),
    );
  }

  static String _short(String type) => const {
    'SALE': 'بيع',
    'SALE_RETURN': 'مرتجع',
    'COLLECTION': 'تحصيل',
    'PURCHASE': 'شراء',
    'ISSUE': 'صرف',
    'RETURN': 'مرتجع عهدة',
    'DEPOSIT': 'توريد',
  }[type]!;
}

/// Customers (or sales reps for DEPOSIT) to pick from; returns the picked id.
Future<String?> _pickParty(BuildContext context, String type) =>
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
