/// Treasury (الخزنة), printable documents (الفواتير) and managed users.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';

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
      chequeStatus = toStr(j['chequeStatus']),
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
  final String? chequeStatus;
  final DateTime createdAt;

  String get key => '$kind:$id';
  bool get isInvoice => kind == 'INVOICE';
  String get title => '${isInvoice ? 'مقدم فاتورة' : 'فاتورة تحصيل'} $number';
}

typedef MethodTotal = ({String method, num total, int count});

num sumPayments(Iterable<num> amounts) =>
    round2(amounts.fold<num>(0, (s, a) => s + a));

/// Totals per payment method, in the order they first appear.
List<MethodTotal> totalsByMethod(List<Payment> payments) {
  final map = <String, ({num total, int count})>{};
  for (final p in payments) {
    final prev = map[p.paymentMethod] ?? (total: 0, count: 0);
    map[p.paymentMethod] = (
      total: round2(prev.total + p.amount),
      count: prev.count + 1,
    );
  }
  return [
    for (final e in map.entries)
      (method: e.key, total: e.value.total, count: e.value.count),
  ];
}

class TreasurySummary {
  TreasurySummary.fromJson(Json j)
    : total = toNum(j['total']),
      byMethod = [
        for (final m in j['byMethod'] as List)
          (
            method: m['method'] as String,
            total: toNum(m['total']),
            count: m['count'] as int? ?? 0,
          ),
      ],
      pendingByRep = [
        for (final r in j['pendingByRep'] as List)
          (
            rep: Ref.fromJson(r['rep'] as Json),
            total: toNum(r['total']),
            count: r['count'] as int? ?? 0,
          ),
      ];

  final num total;
  final List<MethodTotal> byMethod;
  final List<({Ref rep, num total, int count})> pendingByRep;
}

// ---------- money out of the treasury ----------

const entryTypes = ['EXPENSE', 'WITHDRAWAL', 'BANK_DEPOSIT'];
const entryTypeLabels = {
  'EXPENSE': 'مصروف',
  'WITHDRAWAL': 'سحب',
  'BANK_DEPOSIT': 'إيداع في البنك',
  'ADJUSTMENT': 'تسوية جرد', // signed (counted − balance), made by a count only
};

/// Real-money buckets (cheques aren't money until cashed).
const moneyBuckets = ['CASH', 'VODAFONE_CASH', 'BANK_TRANSFER'];

/// Suggestions for the expense category (free text).
const expenseCategories = [
  'بنزين ومواصلات',
  'إيجار',
  'مرتبات',
  'كهرباء ومياه',
  'صيانة',
  'ضيافة',
  'أخرى',
];

/// In the treasury, the bank-transfer bucket is the company's bank balance.
const bucketLabels = {
  'CASH': 'نقدي',
  'VODAFONE_CASH': 'فودافون كاش',
  'BANK_TRANSFER': 'البنك / تحويل',
  'CHEQUE': 'شيكات لم تُصرف',
};
String bucketLabel(String method) => bucketLabels[method] ?? method;

/// An expense, withdrawal or bank deposit taken out of the treasury by a manager.
class TreasuryEntry {
  TreasuryEntry.fromJson(Json j)
    : id = j['id'] as String,
      number = j['number'] as int,
      type = j['type'] as String,
      amount = toNum(j['amount']),
      paymentMethod = j['paymentMethod'] as String,
      category = toStr(j['category']),
      counted = j['counted'] == null ? null : toNum(j['counted']),
      notes = toStr(j['notes']),
      cancelled = j['status'] == 'CANCELLED',
      cancelReason = toStr(j['cancelReason']),
      createdBy = Ref.fromJson(j['createdBy'] as Json),
      rep = Ref.maybe(j['rep']),
      pending = j['depositStatus'] == 'PENDING',
      depositNumber = (j['deposit'] as Json?)?['number'] as int?,
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final int number;
  final String type;
  final num amount;
  final String paymentMethod;
  final String? category;

  /// ADJUSTMENT only: what was counted.
  final num? counted;
  final String? notes;
  final bool cancelled;
  final String? cancelReason;
  final Ref createdBy;

  /// Rep expense (مصروف مندوب): paid from the rep's cash box; [pending] until accepted in handover #[depositNumber].
  final Ref? rep;
  final bool pending;
  final int? depositNumber;
  final DateTime createdAt;
}

/// A rep's cash box: [total] = collected − pending expenses; [cash] = what they can still spend.
class CashBox {
  CashBox.fromJson(Json j)
    : total = toNum(j['total']),
      count = toNum(j['count']).toInt(),
      expenses = toNum(j['expenses']),
      cash = toNum(j['cash']);

  final num total;
  final int count;
  final num expenses;
  final num cash;
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
      payments = toList(j['payments'], Payment.fromJson),
      expenses = toList(j['expenses'], TreasuryEntry.fromJson);

  final String id;
  final int number;
  final Ref rep;
  final Ref receivedBy;
  final num total;
  final String? notes;
  final DateTime createdAt;

  /// Details only (empty in the list).
  final List<Payment> payments;

  /// Details only: the rep's expenses accepted here; [total] = payments − expenses.
  final List<TreasuryEntry> expenses;
}

// ---------- documents ----------

const documentTypes = [
  'SALE',
  'SALE_RETURN',
  'COLLECTION',
  'PURCHASE',
  'ISSUE',
  'RETURN',
  'DEPOSIT',
];
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

// ---------- notifications ----------

const supplierPayment = 'SUPPLIER_PAYMENT';
const visitNotification = 'VISIT';

/// Stock alerts: no actor, `docId` / `party` is the product.
const lowStockNotification = 'LOW_STOCK';
const expirySoonNotification = 'EXPIRY_SOON';

/// A rep spent from their cash box; `party` is the rep.
const repExpenseNotification = 'REP_EXPENSE';

/// To the rep: management took their cash box. No details, nothing to open.
const cashTakenNotification = 'CASH_TAKEN';

/// To a warehouse rep: stock added to / returned into their warehouse. No details, nothing to open.
const stockAddedNotification = 'STOCK_ADDED';
const stockReturnedNotification = 'STOCK_RETURNED';

/// A cheque is due within 2 days, no actor. From a customer: `docId` is the invoice / collection.
const chequeDueNotification = 'CHEQUE_DUE';

/// A cheque the company wrote is due within 2 days: `docId` / `party` is the supplier.
const supplierChequeDueNotification = 'SUPPLIER_CHEQUE_DUE';

/// To owners: the nightly balance check fixed `quantity` stored balances; details in سجل العمليات.
const balancesFixedNotification = 'BALANCES_FIXED';

/// طلب عهدة: a rep asked for goods (`party` = the rep); the rep is told when it's rejected.
const custodyRequestNotification = 'CUSTODY_REQUEST';
const custodyRejectedNotification = 'CUSTODY_REJECTED';
const notificationTypeLabels = {
  ...documentTypeLabels,
  supplierPayment: 'دفعة لمورد',
  visitNotification: 'زيارة جديدة',
  lowStockNotification: 'صنف وصل لحد الطلب',
  expirySoonNotification: 'صنف صلاحيته قربت تنتهي',
  repExpenseNotification: 'مصروف مندوب',
  cashTakenNotification: 'الإدارة استلمت الفلوس من خزنتك',
  stockAddedNotification: 'تمت إضافة أصناف لمخزنك',
  stockReturnedNotification: 'تم تسجيل مرتجع في مخزنك',
  chequeDueNotification: 'شيك ميعاد صرفه قرب',
  supplierChequeDueNotification: 'شيك لمورد ميعاد صرفه قرب',
  balancesFixedNotification: 'مراجعة الأرصدة',
  custodyRequestNotification: 'طلب عهدة',
  custodyRejectedNotification: 'اترفض طلب العهدة',
};

/// One change someone else made; the text is built here, the backend only sends data.
class AppNotification {
  AppNotification.fromJson(Json j)
    : id = j['id'] as String,
      type = j['type'] as String,
      cancelled = j['cancelled'] as bool? ?? false,
      docId = j['docId'] as String,
      number = toStr(j['number']),
      actor = Ref.maybe(j['actor']),
      party = Ref.maybe(j['party']),
      amount = j['amount'] as num?,
      quantity = j['quantity'] as num?,
      expiryDate = toDate(j['expiryDate']),
      dueDate = toDate(j['dueDate']),
      read = j['readAt'] != null,
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final String type;
  final bool cancelled;

  /// Opened on tap; the supplier for [supplierPayment].
  final String docId;
  final String? number;

  /// Null for stock alerts.
  final Ref? actor;

  /// Customer, rep, supplier, or product.
  final Ref? party;
  final num? amount;

  /// Stock alerts: total left.
  final num? quantity;
  final DateTime? expiryDate;

  /// Cheque alerts.
  final DateTime? dueDate;
  final bool read;
  final DateTime createdAt;

  String get title {
    if (type == expirySoonNotification &&
        expiryDate != null &&
        expiryDate!.isBefore(DateTime.now())) {
      return 'صنف صلاحيته انتهت';
    }
    if (type == balancesFixedNotification) {
      return 'مراجعة الأرصدة: اتصلّح رصيد ${quantity ?? 0} حساب';
    }
    return '${cancelled ? 'إلغاء ' : ''}${notificationTypeLabels[type] ?? type}${number != null ? ' $number' : ''}';
  }
}

/// Company details printed on every document.
class Company {
  Company.fromJson(Json j)
    : name = j['name'] as String? ?? '',
      phone = toStr(j['phone']),
      address = toStr(j['address']),
      taxNumber = toStr(j['taxNumber']),
      commercialRegister = toStr(j['commercialRegister']),
      footer = toStr(j['footer']),
      logo = toStr(j['logo']);

  final String name;
  final String? phone;
  final String? address;
  final String? taxNumber;
  final String? commercialRegister;
  final String? footer;

  /// data URL (PNG/JPEG), printed in the header.
  final String? logo;

  /// The logo's bytes for the PDF, or null.
  Uint8List? get logoBytes =>
      logo == null ? null : UriData.parse(logo!).contentAsBytes();
}

/// A daily backup archive (database + attachments). Owner only.
class Backup {
  Backup.fromJson(Json j)
    : name = j['name'] as String,
      size = toNum(j['size']),
      createdAt = toDate(j['createdAt'])!;

  final String name;
  final num size;
  final DateTime createdAt;
}

// ---------- users ----------

const roleLabels = {
  'OWNER': 'صاحب الشركة',
  'ADMIN': 'مدير النظام',
  'SALES_REP': 'مندوب',
  'WAREHOUSE_REP': 'مندوب مخزن',
};

class ManagedUser {
  ManagedUser.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      username = j['username'] as String,
      role = j['role'] as String,
      governorates = List<String>.from(j['governorates'] as List? ?? const []),
      isActive = j['isActive'] as bool? ?? true,
      warehouse = toStr(j['warehouse']),
      lastLoginAt = toDate(j['lastLoginAt']);

  final String id;
  final String name;
  final String username;
  final String role;
  final List<String> governorates;
  final bool isActive;

  /// Sales rep's warehouse id.
  final String? warehouse;
  final DateTime? lastLoginAt;

  bool get isRep => role == 'SALES_REP';
  bool get isWarehouseRep => role == 'WAREHOUSE_REP';
  bool get hasWarehouse => isRep || isWarehouseRep;
}

/// A month or a year for the targets report (?month=YYYY-MM / ?year=YYYY).
class TargetPeriod {
  const TargetPeriod(this.month, {this.yearly = false});
  TargetPeriod.thisMonth()
    : this(DateTime(DateTime.now().year, DateTime.now().month));

  /// First day of the month; a yearly period only uses its year.
  final DateTime month;
  final bool yearly;

  Map<String, String> get query => yearly
      ? {'year': '${month.year}'}
      : {'month': '${month.year}-${'${month.month}'.padLeft(2, '0')}'};
  String get key => query.values.single;
  String get label => yearly
      ? 'سنة ${DateFormat('y', 'ar_EG').format(month)}'
      : 'شهر ${DateFormat('MMMM y', 'ar_EG').format(month)}';

  bool get isCurrent {
    final now = DateTime.now();
    return month.year == now.year && (yearly || month.month == now.month);
  }

  /// Moves [n] months (or years); never past the current month.
  TargetPeriod shift(int n) {
    final next = yearly
        ? DateTime(month.year + n, month.month)
        : DateTime(month.year, month.month + n);
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    return TargetPeriod(next.isAfter(now) ? now : next, yearly: yearly);
  }

  TargetPeriod withYearly(bool value) => TargetPeriod(month, yearly: value);
}

/// GET /users/targets: a rep's month (or year) against that period's targets. Progress is % of target, null = no target.
class TargetRow {
  TargetRow.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      isActive = j['isActive'] as bool? ?? true,
      salesTarget = j['salesTarget'] as num?,
      collectionTarget = j['collectionTarget'] as num?,
      yearlySalesTarget = j['yearlySalesTarget'] as num?,
      yearlyCollectionTarget = j['yearlyCollectionTarget'] as num?,
      salesGoal = j['salesGoal'] as num?,
      collectionGoal = j['collectionGoal'] as num?,
      salesCommissionRate = j['salesCommissionRate'] as num? ?? 0,
      collectionCommissionRate = j['collectionCommissionRate'] as num? ?? 0,
      sales = j['sales'] as num? ?? 0,
      returns = j['returns'] as num? ?? 0,
      netSales = j['netSales'] as num? ?? 0,
      collected = j['collected'] as num? ?? 0,
      salesProgress = (j['salesProgress'] as num?)?.toInt(),
      collectionProgress = (j['collectionProgress'] as num?)?.toInt(),
      salesCommission = j['salesCommission'] as num? ?? 0,
      collectionCommission = j['collectionCommission'] as num? ?? 0,
      commission = j['commission'] as num? ?? 0;

  final String id;
  final String name;
  final bool isActive;

  /// Monthly targets.
  final num? salesTarget;
  final num? collectionTarget;
  final num? yearlySalesTarget;
  final num? yearlyCollectionTarget;

  /// The requested period's targets (monthly or yearly); progress is against these.
  final num? salesGoal;
  final num? collectionGoal;
  final num salesCommissionRate;
  final num collectionCommissionRate;
  final num sales;
  final num returns;
  final num netSales;
  final num collected;
  final int? salesProgress;
  final int? collectionProgress;
  final num salesCommission;
  final num collectionCommission;
  final num commission;

  bool get hasMonthly => (salesTarget ?? 0) > 0 || (collectionTarget ?? 0) > 0;
  bool get hasYearly =>
      (yearlySalesTarget ?? 0) > 0 || (yearlyCollectionTarget ?? 0) > 0;
}

typedef TargetDoc = ({
  String number,
  DateTime date,
  String customer,
  num amount,
  num? paid,
  String detail,
});

/// GET /users/targets/:id: one rep's month and the documents behind it (for the printed report).
class RepTargetReport {
  RepTargetReport.fromJson(Json j)
    : rep = TargetRow.fromJson(j['rep'] as Json),
      invoices = [
        for (final i in j['invoices'] as List)
          (
            number: i['invoiceNumber'] as String,
            date: toDate(i['createdAt'])!,
            customer: i['customer']['name'] as String,
            amount: i['total'] as num,
            paid: i['paidAmount'] as num,
            detail:
                '${methodLabel(i['paymentMethod'] as String?)}${_bounced(i)}',
          ),
      ],
      returns = [
        for (final r in j['returns'] as List)
          (
            number: '${r['number']}',
            date: toDate(r['createdAt'])!,
            customer: r['customer']['name'] as String,
            amount: r['total'] as num,
            paid: null,
            detail: r['invoice']['invoiceNumber'] as String,
          ),
      ],
      collections = [
        for (final c in j['collections'] as List)
          (
            number: c['receiptNumber'] as String,
            date: toDate(c['createdAt'])!,
            customer: c['customer']['name'] as String,
            amount: c['amount'] as num,
            paid: null,
            detail:
                '${methodLabel(c['paymentMethod'] as String?)}${_bounced(c)}',
          ),
      ];

  final TargetRow rep;

  /// detail = payment method; for returns, the invoice number. paid: invoices only.
  final List<TargetDoc> invoices;
  final List<TargetDoc> returns;
  final List<TargetDoc> collections;

  static String _bounced(dynamic d) =>
      d['chequeStatus'] == 'BOUNCED' ? ' (شيك مرتد - غير محسوب)' : '';
}

/// حركة الخزنة: one movement of real money; [amount] is + in / − out.
class LedgerRow {
  LedgerRow.fromJson(Json j)
    : date = toDate(j['date'])!,
      title = j['title'] as String,
      party = toStr(j['party']),
      method = j['method'] as String,
      amount = toNum(j['amount']),
      balance = toNum(j['balance']),
      refType = (j['ref'] as Json?)?['type'] as String?,
      refId = (j['ref'] as Json?)?['id'] as String?;

  final DateTime date;
  final String title;
  final String? party;
  final String method;
  final num amount;
  final num balance;

  /// DEPOSIT | INVOICE | COLLECTION | SUPPLIER | MOVEMENT, or null.
  final String? refType;
  final String? refId;
}

/// One ledger page plus the period's totals (from `meta`).
class LedgerPage extends PageOf<LedgerRow> {
  LedgerPage.fromJson(Json body)
    : opening = toNum((body['meta'] as Json?)?['opening']),
      inflow = toNum((body['meta'] as Json?)?['inflow']),
      outflow = toNum((body['meta'] as Json?)?['outflow']),
      closing = toNum((body['meta'] as Json?)?['closing']),
      super.fromJson(body, LedgerRow.fromJson);

  final num opening;
  final num inflow;
  final num outflow;
  final num closing;
}
