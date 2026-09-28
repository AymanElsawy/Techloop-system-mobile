import '../../core/api.dart';
import '../models/common.dart';
import '../models/treasury.dart';

/// Treasury, printable documents, company settings and users.
class TreasuryRepository {
  TreasuryRepository(this._api);
  final Api _api;

  Future<TreasurySummary> summary() async => TreasurySummary.fromJson(await _api.get('/treasury/summary') as Json);

  /// Managers pass a rep; reps always get their own.
  Future<List<Payment>> pending([String? repId]) async =>
      toList(await _api.get('/treasury/pending', {'repId': repId}), Payment.fromJson);
  Future<List<Deposit>> deposits() async => toList(await _api.get('/treasury/deposits'), Deposit.fromJson);
  Future<Deposit> deposit(String id) async => Deposit.fromJson(await _api.get('/treasury/deposits/$id') as Json);
  Future<Deposit> createDeposit(String repId, List<Payment> payments, String? notes) async => Deposit.fromJson(
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
          'notes': notes,
        })
        as Json,
  );
}

class DocumentRepository {
  DocumentRepository(this._api);
  final Api _api;

  /// from / to: YYYY-MM-DD.
  Future<List<DocumentRow>> list({String? type, String? from, String? to, String? search}) async => toList(
    await _api.get('/documents', {'type': type, 'from': from, 'to': to, 'search': search}),
    DocumentRow.fromJson,
  );
  Future<Company> company() async => Company.fromJson(await _api.get('/settings/company') as Json);
  Future<Company> updateCompany(Json data) async => Company.fromJson(await _api.put('/settings/company', data) as Json);
}

class UserRepository {
  UserRepository(this._api);
  final Api _api;

  Future<List<ManagedUser>> list() async => toList(await _api.get('/users'), ManagedUser.fromJson);
  Future<ManagedUser> create(Json data) async => ManagedUser.fromJson(await _api.post('/users', data) as Json);

  /// One of: governorates, warehouse, password.
  Future<ManagedUser> update(String id, Json data) async =>
      ManagedUser.fromJson(await _api.patch('/users/$id', data) as Json);
}
