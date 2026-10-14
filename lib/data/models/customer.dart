import 'common.dart';

const customerStatusLabels = {
  'PENDING': 'بانتظار الموافقة',
  'APPROVED': 'معتمد',
  'REJECTED': 'مرفوض',
};

const customerTypeLabels = {
  'CLINIC': 'عيادة بيطرية',
  'FARM': 'مزرعة',
  'PHARMACY': 'صيدلية بيطرية',
  'TRADER': 'تاجر',
  'OTHER': 'أخرى',
};

typedef MoneyEvent = ({DateTime date, num amount});
typedef GeoPoint = ({double latitude, double longitude});

MoneyEvent? _event(dynamic j) =>
    j == null ? null : (date: toDate(j['date'])!, amount: toNum(j['amount']));

GeoPoint? toGeo(dynamic j) => j == null
    ? null
    : (
        latitude: toNum(j['latitude']).toDouble(),
        longitude: toNum(j['longitude']).toDouble(),
      );

String mapsUrl(GeoPoint p) =>
    'https://www.google.com/maps?q=${p.latitude},${p.longitude}';

class Customer {
  Customer.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      type = j['type'] as String? ?? 'OTHER',
      phone = toStr(j['phone']),
      contactPerson = toStr(j['contactPerson']),
      governorate = j['governorate'] as String,
      city = toStr(j['city']),
      address = toStr(j['address']),
      location = toGeo(j['location']),
      notes = toStr(j['notes']),
      status = j['status'] as String,
      rejectionReason = toStr(j['rejectionReason']),
      createdBy = Ref.maybe(j['createdBy']),
      reviewedBy = Ref.maybe(j['reviewedBy']),
      reviewedAt = toDate(j['reviewedAt']),
      debit = toNum(j['debit']),
      credit = toNum(j['credit']),
      lastInvoice = _event(j['lastInvoice']),
      lastCollection = _event(j['lastCollection']),
      pendingPayments = toNum(j['pendingPayments']),
      creditLimit = j['creditLimit'] as num?,
      paymentTermDays = (j['paymentTermDays'] as num?)?.toInt(),
      discountPercent = j['discountPercent'] as num?,
      overdue = toNum(j['overdue']),
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final String name;
  final String type;
  final String? phone;
  final String? contactPerson;
  final String governorate;
  final String? city;
  final String? address;
  final GeoPoint? location;
  final String? notes;
  final String status;
  final String? rejectionReason;
  final Ref? createdBy;
  final Ref? reviewedBy;
  final DateTime? reviewedAt;

  /// مدين: what the customer owes.
  final num debit;

  /// دائن: what the company owes the customer.
  final num credit;
  final MoneyEvent? lastInvoice;
  final MoneyEvent? lastCollection;

  /// Collected by a rep, not handed to the treasury yet; not deducted from [debit] yet.
  final num pendingPayments;

  /// حد الائتمان: a rep can't sell past this debt; null = no limit.
  final num? creditLimit;

  /// مدة السداد: invoices are due this many days after the sale; null = no terms.
  final int? paymentTermDays;

  /// Default discount %, also the most a rep may give; null = none.
  final num? discountPercent;

  /// Details endpoint only (0 in lists): owed on invoices past their due date.
  final num overdue;
  final DateTime createdAt;

  String get place => city == null ? governorate : '$governorate - $city';

  /// Debt that can still be collected: rep-held money is already deducted (same as the backend).
  num get collectable => debit;

  /// What can still be sold on credit before the limit; null = no limit.
  num? get creditLeft =>
      creditLimit == null ? null : round2(creditLimit! - collectable);
}
