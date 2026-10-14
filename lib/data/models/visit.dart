import 'common.dart';
import 'customer.dart';

const visitStatusLabels = {
  'PLANNED': 'مخططة',
  'IN_PROGRESS': 'جارية',
  'COMPLETED': 'مكتملة',
  'CANCELLED': 'ملغاة',
};
const visitPurposeLabels = {
  'SALE': 'بيع',
  'COLLECTION': 'تحصيل',
  'FOLLOW_UP': 'متابعة',
};

class VisitCustomer {
  VisitCustomer.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '—',
      phone = toStr(j['phone']),
      governorate = j['governorate'] as String? ?? '',
      city = toStr(j['city']),
      address = toStr(j['address']),
      location = toGeo(j['location']),
      debit = toNum(j['debit']);

  final String id;
  final String name;
  final String? phone;
  final String governorate;
  final String? city;
  final String? address;
  final GeoPoint? location;

  /// Current debt, for context during the visit.
  final num debit;

  String get fullAddress => [
    city == null ? governorate : '$governorate - $city',
    ?address,
  ].join('، ');
}

class Visit {
  Visit.fromJson(Json j)
    : id = j['id'] as String,
      customer = VisitCustomer.fromJson(j['customer'] as Json),
      salesRep = Ref.fromJson(j['salesRep'] as Json),
      purpose = j['purpose'] as String? ?? 'FOLLOW_UP',
      scheduledAt = toDate(j['scheduledAt'])!,
      status = j['status'] as String,
      startedAt = toDate(j['startedAt']),
      hasLocation = j['latitude'] != null,
      completedAt = toDate(j['completedAt']),
      notes = toStr(j['notes']),
      productsDiscussed = List<String>.from(
        j['productsDiscussed'] as List? ?? const [],
      ),
      customerFeedback = toStr(j['customerFeedback']),
      nextVisitAt = toDate(j['nextVisitAt']),
      cancelReason = toStr(j['cancelReason']);

  final String id;
  final VisitCustomer customer;
  final Ref salesRep;
  final String purpose;
  final DateTime scheduledAt;
  final String status;
  final DateTime? startedAt;
  final bool hasLocation;
  final DateTime? completedAt;
  final String? notes;
  final List<String> productsDiscussed;
  final String? customerFeedback;
  final DateTime? nextVisitAt;
  final String? cancelReason;
}
