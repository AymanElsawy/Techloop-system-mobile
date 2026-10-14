import 'dart:typed_data';

import '../../core/api.dart';
import '../../core/format.dart';
import '../models/common.dart';
import '../models/report.dart';
import '../models/treasury.dart';

/// Treasury, printable documents, company settings and users.
class TreasuryRepository {
  TreasuryRepository(this._api);
  final Api _api;

  Future<TreasurySummary> summary() async =>
      TreasurySummary.fromJson(await _api.get('/treasury/summary') as Json);

  /// Managers pass a rep; reps always get their own.
  Future<List<Payment>> pending([String? repId]) async => toList(
    await _api.get('/treasury/pending', {'repId': repId}),
    Payment.fromJson,
  );
  Future<PageOf<Deposit>> deposits(int page, {int limit = pageSize}) async =>
      PageOf.fromJson(
        await _api.getPage('/treasury/deposits', {}, page: page, limit: limit),
        Deposit.fromJson,
      );
  Future<Deposit> deposit(String id) async =>
      Deposit.fromJson(await _api.get('/treasury/deposits/$id') as Json);
  Future<Deposit> createDeposit(
    String repId,
    List<Payment> payments,
    String? notes, [
    List<TreasuryEntry> expenses = const [],
  ]) async => Deposit.fromJson(
    await _api.post('/treasury/deposits', {
          'repId': repId,
          'invoiceIds': [
            for (final p in payments)
              if (p.isInvoice) p.id,
          ],
          'collectionIds': [
            for (final p in payments)
              if (!p.isInvoice) p.id,
          ],
          'expenseIds': [for (final e in expenses) e.id],
          'notes': notes,
        })
        as Json,
  );

  /// Managers: all (filters optional). A rep: their own expenses.
  Future<List<TreasuryEntry>> entries({
    String? repId,
    bool pending = false,
  }) async => toList(
    await _api.get('/treasury/entries', {
      'repId': repId,
      'pending': pending ? true : null,
    }),
    TreasuryEntry.fromJson,
  );

  /// Managers: every entry, newest first.
  Future<PageOf<TreasuryEntry>> entriesPage(
    int page, {
    int limit = pageSize,
  }) async => PageOf.fromJson(
    await _api.getPage('/treasury/entries', {}, page: page, limit: limit),
    TreasuryEntry.fromJson,
  );

  /// A rep's own cash box.
  Future<CashBox> cashBox() async =>
      CashBox.fromJson(await _api.get('/treasury/cash-box') as Json);

  /// A rep's expense from their cash box. Null when there's no connection: saved on the phone and sent later,
  /// and the cached cash box already counts it.
  Future<TreasuryEntry?> createRepExpense(
    num amount,
    String? category,
    String? notes,
  ) async {
    final json = await _api.postOrQueue(
      '/treasury/entries',
      {'amount': amount, 'category': category, 'notes': notes},
      label: 'مصروف ${money(amount)}${category == null ? '' : ' · $category'}',
      meta: {'kind': 'EXPENSE', 'amount': amount},
      patchCache: {
        '/treasury/cash-box': (b) => {
          ...b as Json,
          'total': round2(toNum(b['total']) - amount),
          'cash': round2(toNum(b['cash']) - amount),
          'expenses': round2(toNum(b['expenses']) + amount),
        },
      },
    );
    return json == null ? null : TreasuryEntry.fromJson(json as Json);
  }

  /// type: EXPENSE | WITHDRAWAL | BANK_DEPOSIT; paymentMethod = the bucket the money leaves.
  Future<TreasuryEntry> createEntry(Json data) async => TreasuryEntry.fromJson(
    await _api.post('/treasury/entries', data) as Json,
  );
  Future<TreasuryEntry> cancelEntry(String id, String reason) async =>
      TreasuryEntry.fromJson(
        await _api.patch('/treasury/entries/$id/cancel', {'reason': reason})
            as Json,
      );

  /// Received cheques in the treasury, not cashed or bounced yet.
  Future<List<Payment>> cheques() async =>
      toList(await _api.get('/treasury/cheques'), Payment.fromJson);

  /// status: CLEARED (to the bank) | BOUNCED (back on the customer's debt).
  Future<void> setChequeStatus(Payment p, String status) => _api.patch(
    '/treasury/cheques/${p.id}',
    {'kind': p.kind, 'status': status},
  );
}

/// Managers only.
class ReportRepository {
  ReportRepository(this._api);
  final Api _api;

  /// groupBy: product | governorate | rep; from / to: YYYY-MM-DD.
  Future<SalesReport> sales(String groupBy, String from, String to) async =>
      SalesReport.fromJson(
        await _api.get('/reports/sales', {
              'groupBy': groupBy,
              'from': from,
              'to': to,
            })
            as Json,
      );
  Future<AgingReport> aging() async =>
      AgingReport.fromJson(await _api.get('/reports/aging') as Json);

  /// One row per product + supplier, cheapest average first. No dates = all purchases.
  Future<List<PurchaseRow>> purchases(String? from, String? to) async => toList(
    (await _api.get('/reports/purchases', {'from': from, 'to': to})
        as Json)['rows'],
    PurchaseRow.fromJson,
  );

  /// [kind]: customers | suppliers; from / to: YYYY-MM-DD.
  Future<List<PartyRow>> parties(String kind, String from, String to) async =>
      toList(
        (await _api.get('/reports/$kind', {'from': from, 'to': to})
            as Json)['rows'],
        (j) => PartyRow.fromJson(j, customers: kind == 'customers'),
      );

  /// One customer / supplier in detail.
  Future<PartyReport> party(
    String kind,
    String id,
    String from,
    String to,
  ) async => PartyReport.fromJson(
    await _api.get('/reports/$kind/$id', {'from': from, 'to': to}) as Json,
    customers: kind == 'customers',
  );

  /// The same report as a CSV file (opens in Excel).
  Future<Uint8List> csv(
    String report, [
    Map<String, String> query = const {},
  ]) async {
    final q = Uri(queryParameters: {...query, 'format': 'csv'}).query;
    return (await _api.download('/reports/$report?$q')).bytes;
  }
}

class DocumentRepository {
  DocumentRepository(this._api);
  final Api _api;

  /// from / to: YYYY-MM-DD.
  Future<PageOf<DocumentRow>> page(
    int page, {
    String? type,
    String? from,
    String? to,
    String? search,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/documents',
      {'type': type, 'from': from, 'to': to, 'search': search},
      page: page,
      limit: pageSize,
    ),
    DocumentRow.fromJson,
  );
  Future<Company> company() async =>
      Company.fromJson(await _api.get('/settings/company') as Json);
  Future<Company> updateCompany(Json data) async =>
      Company.fromJson(await _api.put('/settings/company', data) as Json);

  /// Owner only.
  Future<List<Backup>> backups() async =>
      toList(await _api.get('/settings/backups'), Backup.fromJson);
  Future<Backup> createBackup() async =>
      Backup.fromJson(await _api.post('/settings/backups') as Json);
}

class UserRepository {
  UserRepository(this._api);
  final Api _api;

  Future<List<ManagedUser>> list() async =>
      toList(await _api.get('/users'), ManagedUser.fromJson);
  Future<ManagedUser> create(Json data) async =>
      ManagedUser.fromJson(await _api.post('/users', data) as Json);

  /// search: name or username.
  Future<PageOf<ManagedUser>> page(int page, {String? search}) async =>
      PageOf.fromJson(
        await _api.getPage(
          '/users',
          {'search': search},
          page: page,
          limit: pageSize,
        ),
        ManagedUser.fromJson,
      );

  /// One page of reps; [PageOf.sum] = total commission of every matching rep.
  Future<PageOf<TargetRow>> targetsPage(
    TargetPeriod period,
    int page, {
    String? search,
  }) async {
    final body = await _api.getPage(
      '/users/targets',
      {...period.query, 'search': search},
      page: page,
      limit: pageSize,
    );
    final meta = body['meta'] as Json;
    return PageOf(
      toList((body['data'] as Json)['reps'], TargetRow.fromJson),
      meta['total'] as int,
      meta['sum'] as num?,
    );
  }

  Future<List<TargetRow>> targets(TargetPeriod period) async => toList(
    (await _api.get('/users/targets', period.query) as Json)['reps'],
    TargetRow.fromJson,
  );

  Future<RepTargetReport> repTargets(String id, TargetPeriod period) async =>
      RepTargetReport.fromJson(
        await _api.get('/users/targets/$id', period.query) as Json,
      );

  /// One of: governorates, warehouse, password, targets (salesTarget, collectionTarget, *CommissionRate).
  Future<ManagedUser> update(String id, Json data) async =>
      ManagedUser.fromJson(await _api.patch('/users/$id', data) as Json);
}

class NotificationRepository {
  NotificationRepository(this._api);
  final Api _api;

  Future<PageOf<AppNotification>> page(int page) async => PageOf.fromJson(
    await _api.getPage('/notifications', {}, page: page, limit: pageSize),
    AppNotification.fromJson,
  );
  Future<int> unreadCount() async =>
      ((await _api.get('/notifications/unread-count') as Json)['count'] as num)
          .toInt();
  Future<void> markAllRead() => _api.post('/notifications/read-all');
}
