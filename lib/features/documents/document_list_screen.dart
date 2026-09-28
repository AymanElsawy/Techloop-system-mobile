import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/return_details_screen.dart';
import '../treasury/deposit_details_screen.dart';
import 'company_form_screen.dart';
import 'document_pdf_screen.dart';

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
Widget? _detailsScreen(DocumentRow d) => switch (d.type) {
  'SALE' => InvoiceDetailsScreen(id: d.id),
  'COLLECTION' => CollectionDetailsScreen(id: d.id),
  'SALE_RETURN' => ReturnDetailsScreen(id: d.id),
  'DEPOSIT' => DepositDetailsScreen(id: d.id),
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'رقم المستند أو الاسم',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
                      },
                    ),
                  ),
                  if (manager)
                    IconButton(
                      tooltip: 'بيانات الشركة على الفواتير',
                      onPressed: () => push(context, const CompanyFormScreen()),
                      icon: const Icon(Icons.business_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DateField(label: 'من', value: _from, onChanged: (d) => setState(() => _from = d)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DateField(label: 'إلى', value: _to, onChanged: (d) => setState(() => _to = d)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ChoiceBar<String?>(
                options: {null: 'الكل', for (final t in types) t: documentTypeLabels[t]!},
                value: _type,
                onChanged: (v) => setState(() => _type = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<DocumentRow>>(
            key: ValueKey((_type, _from, _to, _query)),
            load: () => context.app.documents.list(
              type: _type,
              from: _from == null ? null : isoDay(_from!),
              to: _to == null ? null : isoDay(_to!),
              search: _query,
            ),
            errorText: 'حدث خطأ أثناء تحميل الفواتير.',
            builder: (context, docs) {
              final total = docs.where((d) => !d.cancelled).fold<num>(0, (s, d) => s + (d.amount ?? 0));
              return docs.isEmpty
                  ? const PageList(children: [EmptyCard('مفيش مستندات مطابقة.')])
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: docs.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == docs.length) {
                          return Text(
                            '${docs.length} مستند${_type != null && total > 0 ? ' · الإجمالي (بدون الملغي): ${money(total)}' : ''}',
                            style: TextStyle(color: context.colors.muted, fontSize: 13),
                          );
                        }
                        return _DocumentCard(doc: docs[i]);
                      },
                    );
            },
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
    final details = _detailsScreen(d);
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
        trailing: d.amount != null ? money(d.amount!) : '${number(d.quantity ?? 0)} قطعة',
        trailingHint: details == null ? 'PDF' : null,
        onTap: () => push(context, details ?? DocumentPdfScreen(type: d.type, id: d.id)),
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
