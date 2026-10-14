import '../../core/api.dart';
import '../models/common.dart';
import '../models/customer.dart';
import '../models/visit.dart';

class CustomerRepository {
  CustomerRepository(this._api);
  final Api _api;

  Future<List<Customer>> list({
    String? governorate,
    String? status,
    String? search,
  }) async => toList(
    await _api.get('/customers', {
      'governorate': governorate,
      'status': status,
      'search': search,
    }),
    Customer.fromJson,
  );

  Future<PageOf<Customer>> page(
    int page, {
    int limit = pageSize,
    String? governorate,
    String? status,
    String? search,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/customers',
      {'governorate': governorate, 'status': status, 'search': search},
      page: page,
      limit: limit,
    ),
    Customer.fromJson,
  );

  Future<Customer> get(String id) async =>
      Customer.fromJson(await _api.get('/customers/$id') as Json);

  /// Empty strings clear optional fields on the backend.
  Future<Customer> create(Json data) async =>
      Customer.fromJson(await _api.post('/customers', data) as Json);
  Future<Customer> update(String id, Json data) async =>
      Customer.fromJson(await _api.patch('/customers/$id', data) as Json);
  Future<Customer> approve(String id) async =>
      Customer.fromJson(await _api.patch('/customers/$id/approve', {}) as Json);
  Future<Customer> reject(String id, String reason) async => Customer.fromJson(
    await _api.patch('/customers/$id/reject', {'reason': reason}) as Json,
  );

  /// Fixed public balance link (رابط المديونية).
  Future<String> shareLink(String id) async =>
      '$apiUrl/public/s/${(await _api.post('/customers/$id/share-link') as Json)['token']}';
}

class VisitRepository {
  VisitRepository(this._api);
  final Api _api;

  Future<PageOf<Visit>> page(
    int page, {
    DateTime? from,
    DateTime? to,
    String? status,
    String? customerId,
  }) async => PageOf.fromJson(
    await _api.getPage(
      '/visits',
      {
        'from': from?.toUtc().toIso8601String(),
        'to': to?.toUtc().toIso8601String(),
        'status': status,
        'customerId': customerId,
      },
      page: page,
      limit: pageSize,
    ),
    Visit.fromJson,
  );

  Future<Visit> get(String id) async =>
      Visit.fromJson(await _api.get('/visits/$id') as Json);

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

  /// Start / complete work offline too: saved on the phone (null result) and sent later,
  /// and the cached visit shows the new status meanwhile.
  Future<Visit?> start(
    String id,
    GeoPoint? location, {
    required String customerName,
  }) => _offlineStep(
    id,
    'start',
    {
      if (location != null) ...{
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
    },
    'بدء زيارة · $customerName',
    {'status': 'IN_PROGRESS', 'startedAt': _now()},
  );

  Future<Visit?> complete(
    String id,
    Json data, {
    required String customerName,
  }) => _offlineStep(id, 'complete', data, 'إنهاء زيارة · $customerName', {
    ...data,
    'status': 'COMPLETED',
    'completedAt': _now(),
  });

  static String _now() => DateTime.now().toUtc().toIso8601String();

  Future<Visit?> _offlineStep(
    String id,
    String step,
    Json body,
    String label,
    Json cached,
  ) async {
    final json = await _api.postOrQueue(
      '/visits/$id/$step',
      body,
      label: label,
      meta: {'kind': 'VISIT', 'visitId': id},
      patchCache: {
        '/visits/$id': (v) => {...v as Json, ...cached},
      },
    );
    return json == null ? null : Visit.fromJson(json as Json);
  }

  Future<Visit> cancel(String id, String? reason) async => Visit.fromJson(
    await _api.post('/visits/$id/cancel', {'reason': reason}) as Json,
  );
}
