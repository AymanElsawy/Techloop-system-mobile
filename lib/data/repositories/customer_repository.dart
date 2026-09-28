import '../../core/api.dart';
import '../models/common.dart';
import '../models/customer.dart';
import '../models/visit.dart';

class CustomerRepository {
  CustomerRepository(this._api);
  final Api _api;

  Future<List<Customer>> list({String? governorate, String? status, String? search}) async => toList(
    await _api.get('/customers', {'governorate': governorate, 'status': status, 'search': search}),
    Customer.fromJson,
  );

  Future<Customer> get(String id) async => Customer.fromJson(await _api.get('/customers/$id') as Json);

  /// Empty strings clear optional fields on the backend.
  Future<Customer> create(Json data) async => Customer.fromJson(await _api.post('/customers', data) as Json);
  Future<Customer> update(String id, Json data) async =>
      Customer.fromJson(await _api.patch('/customers/$id', data) as Json);
  Future<Customer> approve(String id) async =>
      Customer.fromJson(await _api.patch('/customers/$id/approve', {}) as Json);
  Future<Customer> reject(String id, String reason) async =>
      Customer.fromJson(await _api.patch('/customers/$id/reject', {'reason': reason}) as Json);
}

class VisitRepository {
  VisitRepository(this._api);
  final Api _api;

  Future<List<Visit>> list({DateTime? from, DateTime? to, String? status, String? customerId}) async => toList(
    await _api.get('/visits', {
      'from': from?.toUtc().toIso8601String(),
      'to': to?.toUtc().toIso8601String(),
      'status': status,
      'customerId': customerId,
    }),
    Visit.fromJson,
  );

  Future<Visit> get(String id) async => Visit.fromJson(await _api.get('/visits/$id') as Json);

  /// `salesRepId` is required for managers and ignored for reps.
  Future<Visit> create({
    required String customerId,
    String? salesRepId,
    required String purpose,
    required DateTime scheduledAt,
  }) async => Visit.fromJson(
    await _api.post('/visits', {
          'customerId': customerId,
          'salesRepId': ?salesRepId,
          'purpose': purpose,
          'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        })
        as Json,
  );

  Future<Visit> start(String id, GeoPoint? location) async => Visit.fromJson(
    await _api.post(
          '/visits/$id/start',
          location == null ? {} : {'latitude': location.latitude, 'longitude': location.longitude},
        )
        as Json,
  );

  Future<Visit> complete(String id, Json data) async =>
      Visit.fromJson(await _api.post('/visits/$id/complete', data) as Json);

  Future<Visit> cancel(String id, String? reason) async =>
      Visit.fromJson(await _api.post('/visits/$id/cancel', {'reason': reason}) as Json);
}
