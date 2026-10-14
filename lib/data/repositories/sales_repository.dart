import 'dart:typed_data';

import '../../core/api.dart';
import '../models/common.dart';
import '../models/sales.dart';

/// A picked file for an attachment (receipt / cheque image or PDF).
typedef UploadFile = ({Uint8List bytes, String name});

/// Invoices, collections and sales returns.
class SalesRepository {
  SalesRepository(this._api);
  final Api _api;

  Future<List<Invoice>> invoices({String? customerId, String? visitId}) async =>
      toList(
        await _api.get('/invoices', {
          'customerId': customerId,
          'visitId': visitId,
        }),
        Invoice.fromJson,
      );
  Future<Invoice> invoice(String id) async =>
      Invoice.fromJson(await _api.get('/invoices/$id') as Json);
  Future<Invoice> createInvoice(Json data) async =>
      Invoice.fromJson(await _api.post('/invoices', data) as Json);
  Future<Invoice> cancelInvoice(String id, String reason) async =>
      Invoice.fromJson(
        await _api.patch('/invoices/$id/cancel', {'reason': reason}) as Json,
      );

  Future<List<Collection>> collections({
    String? customerId,
    String? visitId,
  }) async => toList(
    await _api.get('/collections', {
      'customerId': customerId,
      'visitId': visitId,
    }),
    Collection.fromJson,
  );
  Future<Collection> collection(String id) async =>
      Collection.fromJson(await _api.get('/collections/$id') as Json);

  /// Null when there's no connection: saved on the phone and sent later (see [Api.postOrQueue]).
  /// Meanwhile the cached customer counts the amount as collected, so it can't be collected twice.
  Future<Collection?> createCollection(
    Json data, {
    required String customerName,
  }) async {
    final amount = data['amount'] as num;
    final json = await _api.postOrQueue(
      '/collections',
      data,
      label: 'تحصيل ${data['receiptNumber']} · $customerName',
      meta: {
        'kind': 'COLLECTION',
        'customer': customerName,
        'amount': amount,
        'paymentMethod': data['paymentMethod'],
      },
      patchCache: {
        '/customers/${data['customerId']}': (c) => (c as Json)
          ..['pendingPayments'] = round2(toNum(c['pendingPayments']) + amount)
          ..['debit'] = round2(toNum(c['debit']) - amount),
      },
    );
    return json == null ? null : Collection.fromJson(json as Json);
  }

  Future<Collection> cancelCollection(String id, String reason) async =>
      Collection.fromJson(
        await _api.patch('/collections/$id/cancel', {'reason': reason}) as Json,
      );

  Future<List<SalesReturn>> returns({
    String? customerId,
    String? invoiceId,
  }) async => toList(
    await _api.get('/returns', {
      'customerId': customerId,
      'invoiceId': invoiceId,
    }),
    SalesReturn.fromJson,
  );
  Future<SalesReturn> salesReturn(String id) async =>
      SalesReturn.fromJson(await _api.get('/returns/$id') as Json);
  Future<SalesReturn> createReturn(Json data) async =>
      SalesReturn.fromJson(await _api.post('/returns', data) as Json);
  Future<SalesReturn> cancelReturn(String id, String reason) async =>
      SalesReturn.fromJson(
        await _api.patch('/returns/$id/cancel', {'reason': reason}) as Json,
      );

  /// `base` is '/invoices/:id' or '/collections/:id'. Returns the updated document JSON.
  Future<Json> upload(String base, String kind, UploadFile file) async =>
      await _api.upload(
            '$base/attachments',
            {'kind': kind},
            file.bytes,
            file.name,
          )
          as Json;

  Future<({Uint8List bytes, String contentType})> download(
    String base,
    String attachmentId,
  ) => _api.download('$base/attachments/$attachmentId');
}
