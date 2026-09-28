/// Treasury (الخزنة), printable documents (الفواتير) and managed users.
library;

import 'common.dart';

/// One money entry in a rep's cash box or a handover.
class Payment {
  Payment.fromJson(Json j)
    : kind = j['kind'] as String,
      id = j['id'] as String,
      number = j['number'] as String,
      customer = Ref.fromJson(j['customer'] as Json),
      governorate = (j['customer'] as Json)['governorate'] as String? ?? '',
      rep = Ref.fromJson(j['rep'] as Json),
      amount = toNum(j['amount']),
      paymentMethod = j['paymentMethod'] as String,
      chequeNumber = toStr(j['chequeNumber']),
      chequeDueDate = toDate(j['chequeDueDate']),
      createdAt = toDate(j['createdAt'])!;

  final String kind; // INVOICE | COLLECTION
  final String id;
  final String number;
  final Ref customer;
  final String governorate;
  final Ref rep;
  final num amount;
  final String paymentMethod;
  final String? chequeNumber;
  final DateTime? chequeDueDate;
  final DateTime createdAt;

  String get key => '$kind:$id';
  bool get isInvoice => kind == 'INVOICE';
  String get title => '${isInvoice ? 'مقدم فاتورة' : 'فاتورة تحصيل'} $number';
}

typedef MethodTotal = ({String method, num total, int count});

num sumPayments(Iterable<num> amounts) => round2(amounts.fold<num>(0, (s, a) => s + a));

/// Totals per payment method, in the order they first appear.
List<MethodTotal> totalsByMethod(List<Payment> payments) {
  final map = <String, ({num total, int count})>{};
  for (final p in payments) {
    final prev = map[p.paymentMethod] ?? (total: 0, count: 0);
    map[p.paymentMethod] = (total: round2(prev.total + p.amount), count: prev.count + 1);
  }
  return [for (final e in map.entries) (method: e.key, total: e.value.total, count: e.value.count)];
}

class TreasurySummary {
  TreasurySummary.fromJson(Json j)
    : total = toNum(j['total']),
      byMethod = [
        for (final m in j['byMethod'] as List)
          (method: m['method'] as String, total: toNum(m['total']), count: m['count'] as int? ?? 0),
      ],
      pendingByRep = [
        for (final r in j['pendingByRep'] as List)
          (rep: Ref.fromJson(r['rep'] as Json), total: toNum(r['total']), count: r['count'] as int? ?? 0),
      ];

  final num total;
  final List<MethodTotal> byMethod;
  final List<({Ref rep, num total, int count})> pendingByRep;
}

class Deposit {
  Deposit.fromJson(Json j)
    : id = j['id'] as String,
      number = j['number'] as int,
      rep = Ref.fromJson(j['rep'] as Json),
      receivedBy = Ref.fromJson(j['receivedBy'] as Json),
      total = toNum(j['total']),
      notes = toStr(j['notes']),
      createdAt = toDate(j['createdAt'])!,
      payments = toList(j['payments'], Payment.fromJson);

  final String id;
  final int number;
  final Ref rep;
  final Ref receivedBy;
  final num total;
  final String? notes;
  final DateTime createdAt;

  /// Details only (empty in the list).
  final List<Payment> payments;
}

// ---------- documents ----------

const documentTypes = ['SALE', 'SALE_RETURN', 'COLLECTION', 'PURCHASE', 'ISSUE', 'RETURN', 'DEPOSIT'];
const documentTypeLabels = {
  'SALE': 'فاتورة بيع',
  'SALE_RETURN': 'فاتورة مرتجع',
  'COLLECTION': 'إيصال تحصيل',
  'PURCHASE': 'فاتورة شراء (مورد)',
  'ISSUE': 'إذن صرف عهدة',
  'RETURN': 'إذن مرتجع عهدة',
  'DEPOSIT': 'إيصال توريد للخزنة',
};
const documentPartyLabels = {
  'SALE': 'العميل',
  'SALE_RETURN': 'العميل',
  'COLLECTION': 'العميل',
  'PURCHASE': 'المورد',
  'ISSUE': 'المندوب',
  'RETURN': 'المندوب',
  'DEPOSIT': 'المندوب',
};

class DocumentRow {
  DocumentRow.fromJson(Json j)
    : type = j['type'] as String,
      id = j['id'] as String,
      number = '${j['number']}',
      date = toDate(j['date'])!,
      party = Ref.maybe(j['party']),
      by = Ref.maybe(j['by']),
      amount = j['amount'] as num?,
      quantity = j['quantity'] as num?,
      cancelled = j['status'] == 'CANCELLED';

  final String type;
  final String id;
  final String number;
  final DateTime date;
  final Ref? party;
  final Ref? by;

  /// Money; null for custody moves (then [quantity] is set).
  final num? amount;
  final num? quantity;
  final bool cancelled;
}

/// Company details printed on every document.
class Company {
  Company.fromJson(Json j)
    : name = j['name'] as String? ?? '',
      phone = toStr(j['phone']),
      address = toStr(j['address']),
      taxNumber = toStr(j['taxNumber']),
      commercialRegister = toStr(j['commercialRegister']),
      footer = toStr(j['footer']);

  final String name;
  final String? phone;
  final String? address;
  final String? taxNumber;
  final String? commercialRegister;
  final String? footer;
}

// ---------- users ----------

const roleLabels = {'OWNER': 'صاحب الشركة', 'ADMIN': 'مدير النظام', 'SALES_REP': 'مندوب'};

class ManagedUser {
  ManagedUser.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      email = j['email'] as String,
      role = j['role'] as String,
      governorates = List<String>.from(j['governorates'] as List? ?? const []),
      isActive = j['isActive'] as bool? ?? true,
      warehouse = toStr(j['warehouse']),
      lastLoginAt = toDate(j['lastLoginAt']);

  final String id;
  final String name;
  final String email;
  final String role;
  final List<String> governorates;
  final bool isActive;

  /// Sales rep's warehouse id.
  final String? warehouse;
  final DateTime? lastLoginAt;

  bool get isRep => role == 'SALES_REP';
}
