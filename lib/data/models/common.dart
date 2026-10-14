/// Shared API model pieces. Labels match the web app (frontend/src/app/features/**/models).
library;

typedef Json = Map<String, dynamic>;

num toNum(dynamic v) => v as num? ?? 0;
DateTime? toDate(dynamic v) => v == null ? null : DateTime.parse(v as String);
String? toStr(dynamic v) => v as String?;
List<T> toList<T>(dynamic v, T Function(Json) f) => [
  for (final e in v as List? ?? const []) f(e as Json),
];

double round2(num n) => (n * 100).round() / 100;

/// Rows per page in paged lists (backend max 100).
const pageSize = 20;

/// One page of a list plus the row count across every page ([sum]: documents only).
class PageOf<T> {
  PageOf(this.items, this.total, [this.sum]);
  PageOf.fromJson(Json body, T Function(Json) f)
    : items = toList(body['data'], f),
      total = (body['meta'] as Json?)?['total'] as int? ?? 0,
      sum = (body['meta'] as Json?)?['sum'] as num?;

  final List<T> items;
  final int total;
  final num? sum;
}

/// `{ id, name }` reference to a user, customer, warehouse...
class Ref {
  const Ref(this.id, this.name);
  Ref.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '—';
  static Ref? maybe(dynamic j) => j == null ? null : Ref.fromJson(j as Json);

  final String id;
  final String name;
}

const paymentMethods = ['CASH', 'VODAFONE_CASH', 'BANK_TRANSFER', 'CHEQUE'];
const paymentMethodLabels = {
  'CASH': 'تحصيل نقدي',
  'VODAFONE_CASH': 'فودافون كاش',
  'BANK_TRANSFER': 'تحويل بنكي',
  'CHEQUE': 'شيك',
};

/// Shown when nothing was paid up front.
const deferredLabel = 'آجل';

String methodLabel(String? method) =>
    method == null ? deferredLabel : paymentMethodLabels[method] ?? method;

const unitLabels = {'LITER': 'لتر', 'PACK': 'عبوة', 'CARTON': 'كرتونة'};

const attachmentKindLabels = {'RECEIPT': 'إيصال', 'CHEQUE': 'صورة الشيك'};

/// Backend limit for attachments.
const attachmentMaxBytes = 5 * 1024 * 1024;

class Attachment {
  Attachment.fromJson(Json j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      originalName = j['originalName'] as String? ?? '',
      mimeType = j['mimeType'] as String? ?? '',
      uploadedBy = Ref.maybe(j['uploadedBy']),
      uploadedAt = toDate(j['uploadedAt']);

  final String id;
  final String kind;
  final String originalName;
  final String mimeType;
  final Ref? uploadedBy;
  final DateTime? uploadedAt;
}

/// Where the money of an invoice / collection is: with the rep (PENDING) or in the treasury.
class DepositInfo {
  DepositInfo.fromJson(Json j)
    : pending = j['depositStatus'] == 'PENDING',
      depositId = (j['deposit'] as Json?)?['id'] as String?,
      depositNumber = (j['deposit'] as Json?)?['number'] as int?,
      chequeStatus = toStr(j['chequeStatus']);

  final bool pending;
  final String? depositId;
  final int? depositNumber;

  /// CLEARED (cashed, now in the bank) | BOUNCED (back on the customer's debt) | null.
  final String? chequeStatus;
  bool get bounced => chequeStatus == 'BOUNCED';
}

// Kept in sync with backend/src/modules/customers/customer.types.ts
const governorates = [
  'القاهرة',
  'الجيزة',
  'الإسكندرية',
  'القليوبية',
  'الشرقية',
  'الدقهلية',
  'الغربية',
  'المنوفية',
  'البحيرة',
  'كفر الشيخ',
  'دمياط',
  'بورسعيد',
  'الإسماعيلية',
  'السويس',
  'الفيوم',
  'بني سويف',
  'المنيا',
  'أسيوط',
  'سوهاج',
  'قنا',
  'الأقصر',
  'أسوان',
  'البحر الأحمر',
  'الوادي الجديد',
  'مطروح',
  'شمال سيناء',
  'جنوب سيناء',
];

/// "مخزن القاهرة" for a warehouse named "القاهرة", without doubling a name that already says "مخزن".
String warehouseLabel(String name) =>
    name.trim().startsWith('مخزن') ? name : 'مخزن $name';
