import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/treasury.dart';
import '../../data/models/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/ui.dart';
import '../audit_log/audit_log_screen.dart';
import '../documents/document_list_screen.dart';
import '../documents/document_pdf_screen.dart';
import '../treasury/handover_screen.dart';
import '../treasury/treasury_screen.dart';
import '../inventory/custody_requests.dart';
import '../inventory/movement_list.dart';
import '../inventory/product_form_screen.dart';
import '../suppliers/supplier_details_screen.dart';
import '../visits/visit_details_screen.dart';

/// Badge on the الإشعارات tab; the shell polls it, opening the tab zeroes it.
final unreadNotifications = ValueNotifier<int>(0);

/// الإشعارات: latest changes by others. Loading the list marks them all read on the server,
/// while the list itself keeps showing which ones were new.
class NotificationListScreen extends StatelessWidget {
  const NotificationListScreen({super.key});

  Future<PageOf<AppNotification>> _load(BuildContext context, int page) async {
    final repo = context.app.notifications;
    final result = await repo.page(page);
    if (result.items.any((n) => !n.read)) {
      repo.markAllRead().then(
        (_) => unreadNotifications.value = 0,
        onError: (_) {},
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return PagedListView<AppNotification>(
      load: (page) => _load(context, page),
      errorText: 'حدث خطأ أثناء تحميل الإشعارات.',
      emptyText: 'مفيش إشعارات لسه.',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemBuilder: (context, n) => _NotificationCard(n: n),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.n});

  final AppNotification n;

  Widget? _screen() => switch (n.type) {
    cashTakenNotification ||
    stockAddedNotification ||
    stockReturnedNotification => null,
    supplierPayment ||
    supplierChequeDueNotification => SupplierDetailsScreen(id: n.docId),
    custodyRequestNotification || custodyRejectedNotification => Scaffold(
      appBar: AppBar(title: const Text('طلبات العهدة')),
      body: const CustodyRequestsView(),
    ),
    balancesFixedNotification => Scaffold(
      appBar: AppBar(title: const Text('سجل العمليات')),
      body: const AuditLogScreen(),
    ),
    chequeDueNotification => Scaffold(
      appBar: AppBar(title: const Text('الخزنة')),
      body: const TreasuryScreen(),
    ),
    visitNotification => VisitDetailsScreen(id: n.docId),
    lowStockNotification ||
    expirySoonNotification => ProductFormScreen(id: n.docId),
    repExpenseNotification when n.party != null => HandoverScreen(
      repId: n.party!.id,
    ),
    'ISSUE' || 'RETURN' => MovementDetailsScreen(id: n.docId),
    _ =>
      documentDetailsScreen(n.type, n.docId) ??
          DocumentPdfScreen(type: n.type, id: n.docId),
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Tile(
        leading: Icon(
          Icons.circle,
          size: 10,
          color: n.read ? Colors.transparent : context.colors.dangerFg,
          semanticLabel: n.read ? null : 'جديد',
        ),
        title: n.title,
        subtitle: [
          if (n.party != null) n.party!.name,
          if (n.quantity != null && n.type != balancesFixedNotification)
            'الباقي ${number(n.quantity!)}',
          if (n.expiryDate != null) 'الصلاحية ${shortDate(n.expiryDate!)}',
          if (n.dueDate != null) 'الاستحقاق ${shortDate(n.dueDate!)}',
          if (n.actor != null) 'بواسطة ${n.actor!.name}',
          dateTime(n.createdAt),
        ].dotted(),
        badge: n.cancelled
            ? const StatusBadge('إلغاء', tone: Tone.danger)
            : null,
        trailing: n.amount != null ? money(n.amount!) : null,
        onTap: _screen() == null ? null : () => push(context, _screen()!),
      ),
    );
  }
}
