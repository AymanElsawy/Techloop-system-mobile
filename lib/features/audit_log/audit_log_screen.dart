import 'package:flutter/material.dart';

import '../documents/document_pdf_screen.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../customers/customer_details_screen.dart';
import '../inventory/product_form_screen.dart';
import '../sales/collection_details_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../sales/return_details_screen.dart';
import '../suppliers/supplier_details_screen.dart';

const _actionLabels = {
  'CREATE': 'سجّل',
  'CANCEL': 'ألغى',
  'UPDATE': 'عدّل',
  'DELETE': 'حذف',
  'APPROVE': 'اعتمد',
  'REJECT': 'رفض',
};

/// Same as the web `AUDIT_ENTITY_LABELS`.
const auditEntityLabels = {
  'INVOICE': 'فاتورة بيع',
  'COLLECTION': 'تحصيل',
  'RETURN': 'مرتجع',
  'SUPPLIER_RETURN': 'مرتجع مورد',
  'TREASURY_ENTRY': 'حركة خزنة',
  'SUPPLIER_PAYMENT': 'دفعة مورد',
  'CUSTOMER': 'عميل',
  'SUPPLIER': 'مورد',
  'PRODUCT': 'صنف',
  'USER': 'مستخدم',
};

/// One line of سجل العمليات; names, labels and values are snapshots from that moment.
class AuditLog {
  AuditLog.fromJson(Json j)
    : id = j['id'] as String,
      actor = Ref.fromJson(j['actor'] as Json),
      action = j['action'] as String,
      entity = j['entity'] as String,
      docId = j['docId'] as String,
      title = toStr(j['title']),
      party = toStr(j['party']),
      amount = j['amount'] as num?,
      reason = toStr(j['reason']),
      changes = [
        for (final c in j['changes'] as List? ?? const [])
          (
            field: (c as Json)['field'] as String,
            from: toStr(c['from']),
            to: toStr(c['to']),
          ),
      ],
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final Ref actor;
  final String action;
  final String entity;

  /// The supplier for SUPPLIER_PAYMENT.
  final String docId;

  /// Document number, or the customer / product / user name.
  final String? title;
  final String? party;
  final num? amount;
  final String? reason;
  final List<({String field, String? from, String? to})> changes;
  final DateTime createdAt;
}

/// سجل العمليات: who cancelled or edited what. The owner only.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String? _entity;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ChoiceBar<String?>(
            options: {null: 'الكل', ...auditEntityLabels},
            value: _entity,
            onChanged: (v) => setState(() => _entity = v),
          ),
        ),
        Expanded(
          child: PagedListView<AuditLog>(
            key: ValueKey(_entity),
            load: (page) async => PageOf.fromJson(
              await context.app.session.api.getPage(
                '/audit-log',
                {'entity': _entity},
                page: page,
                limit: pageSize,
              ),
              AuditLog.fromJson,
            ),
            errorText: 'حدث خطأ أثناء تحميل السجل.',
            emptyText: 'مفيش عمليات متسجلة لسه.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemBuilder: (context, a) => _AuditCard(a: a),
          ),
        ),
      ],
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.a});

  final AuditLog a;

  Widget? _screen() => a.action == 'DELETE'
      ? null
      : switch (a.entity) {
          'INVOICE' => InvoiceDetailsScreen(id: a.docId),
          'COLLECTION' => CollectionDetailsScreen(id: a.docId),
          'RETURN' => ReturnDetailsScreen(id: a.docId),
          'SUPPLIER_RETURN' => DocumentPdfScreen(
            type: 'SUPPLIER_RETURN',
            id: a.docId,
          ),
          'SUPPLIER_PAYMENT' => SupplierDetailsScreen(id: a.docId),
          'CUSTOMER' => CustomerDetailsScreen(id: a.docId),
          'SUPPLIER' => SupplierDetailsScreen(id: a.docId),
          'PRODUCT' => ProductFormScreen(id: a.docId),
          _ => null, // treasury entries and users have no details screen
        };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final screen = _screen();
    final removed = a.action == 'CANCEL' || a.action == 'DELETE';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: screen == null ? null : () => push(context, screen),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${a.actor.name} ${_actionLabels[a.action] ?? a.action} '
                '${auditEntityLabels[a.entity] ?? a.entity} ${a.title ?? ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: removed ? context.colors.dangerFg : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (a.party != null) a.party!,
                  if (a.amount != null) money(a.amount!),
                  dateTime(a.createdAt),
                ].dotted(),
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (a.reason != null) Text('السبب: ${a.reason}'),
              for (final c in a.changes)
                Text(
                  c.from == null && c.to == null
                      ? '${c.field}: اتغيرت'
                      : '${c.field}: ${c.from ?? '—'} ← ${c.to ?? '—'}',
                  style: const TextStyle(fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
