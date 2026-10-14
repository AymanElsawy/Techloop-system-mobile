/// Invoices (فاتورة بيع), collections (فاتورة تحصيل) and sales returns (فاتورة مرتجع).
library;

import 'common.dart';

class DocCustomer {
  DocCustomer.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String? ?? '—',
      governorate = j['governorate'] as String? ?? '',
      city = toStr(j['city']),
      phone = toStr(j['phone']);

  final String id;
  final String name;
  final String governorate;
  final String? city;
  final String? phone;

  String get place => city == null ? governorate : '$governorate - $city';
}

class LineItem {
  LineItem.fromJson(Json j)
    : product = j['product'] as String,
      name = j['name'] as String? ?? '',
      unit = toStr(j['unit']),
      unitPrice = toNum(j['unitPrice']),
      discountPercent = toNum(j['discountPercent']),
      quantity = toNum(j['quantity']),
      total = toNum(j['total']);

  final String product;
  final String name;
  final String? unit;
  final num unitPrice;

  /// total = unitPrice × quantity − this % (invoices only; 0 on old ones and on returns).
  final num discountPercent;
  final num quantity;
  final num total;

  String get label => unit == null ? name : '$name (${unitLabels[unit]})';
}

/// Fields shared by invoices and collections (money that goes through the treasury).
mixin Payable {
  String get id;
  String? get paymentMethod;
  String? get chequeNumber;
  DateTime? get chequeDueDate;
  DepositInfo get deposit;
  List<Attachment> get attachments;
  bool get cancelled;
  String? get cancelReason;
  Ref? get cancelledBy;
  DateTime? get cancelledAt;
  String? get visitId;
}

class Invoice with Payable {
  Invoice.fromJson(Json j)
    : id = j['id'] as String,
      invoiceNumber = j['invoiceNumber'] as String,
      customer = DocCustomer.fromJson(j['customer'] as Json),
      createdBy = Ref.fromJson(j['createdBy'] as Json),
      visitId = (j['visit'] as Json?)?['id'] as String?,
      warehouse = Ref.maybe(j['warehouse']),
      deposit = DepositInfo.fromJson(j),
      items = toList(j['items'], LineItem.fromJson),
      total = toNum(j['total']),
      discount = toNum(j['discount']),
      dueDate = toDate(j['dueDate']),
      paidAmount = toNum(j['paidAmount']),
      remaining = toNum(j['remaining']),
      previousDebtPaid = toNum(j['previousDebtPaid']),
      paymentMethod = toStr(j['paymentMethod']),
      chequeNumber = toStr(j['chequeNumber']),
      chequeDueDate = toDate(j['chequeDueDate']),
      notes = toStr(j['notes']),
      cancelled = j['status'] == 'CANCELLED',
      cancelReason = toStr(j['cancelReason']),
      cancelledBy = Ref.maybe(j['cancelledBy']),
      cancelledAt = toDate(j['cancelledAt']),
      attachments = toList(j['attachments'], Attachment.fromJson),
      createdAt = toDate(j['createdAt'])!;

  @override
  final String id;
  final String invoiceNumber;
  final DocCustomer customer;
  final Ref createdBy;
  @override
  final String? visitId;
  final Ref? warehouse;
  @override
  final DepositInfo deposit;
  final List<LineItem> items;

  /// After discount.
  final num total;

  /// Sum of the line discounts (EGP).
  final num discount;

  /// From the customer's payment terms; null = no terms.
  final DateTime? dueDate;
  final num paidAmount;

  /// Left unpaid on this invoice.
  final num remaining;

  /// Paid above the invoice total; settles the customer's older debt.
  final num previousDebtPaid;
  @override
  final String? paymentMethod;
  @override
  final String? chequeNumber;
  @override
  final DateTime? chequeDueDate;
  final String? notes;
  @override
  final bool cancelled;
  @override
  final String? cancelReason;
  @override
  final Ref? cancelledBy;
  @override
  final DateTime? cancelledAt;
  @override
  final List<Attachment> attachments;
  final DateTime createdAt;
}

class Collection with Payable {
  Collection.fromJson(Json j)
    : id = j['id'] as String,
      receiptNumber = j['receiptNumber'] as String,
      customer = DocCustomer.fromJson(j['customer'] as Json),
      createdBy = Ref.fromJson(j['createdBy'] as Json),
      visitId = (j['visit'] as Json?)?['id'] as String?,
      amount = toNum(j['amount']),
      paymentMethod = j['paymentMethod'] as String,
      chequeNumber = toStr(j['chequeNumber']),
      chequeDueDate = toDate(j['chequeDueDate']),
      notes = toStr(j['notes']),
      cancelled = j['status'] == 'CANCELLED',
      deposit = DepositInfo.fromJson(j),
      cancelReason = toStr(j['cancelReason']),
      cancelledBy = Ref.maybe(j['cancelledBy']),
      cancelledAt = toDate(j['cancelledAt']),
      attachments = toList(j['attachments'], Attachment.fromJson),
      createdAt = toDate(j['createdAt'])!;

  @override
  final String id;
  final String receiptNumber;
  final DocCustomer customer;
  final Ref createdBy;
  @override
  final String? visitId;
  final num amount;
  @override
  final String paymentMethod;
  @override
  final String? chequeNumber;
  @override
  final DateTime? chequeDueDate;
  final String? notes;
  @override
  final bool cancelled;
  @override
  final DepositInfo deposit;
  @override
  final String? cancelReason;
  @override
  final Ref? cancelledBy;
  @override
  final DateTime? cancelledAt;
  @override
  final List<Attachment> attachments;
  final DateTime createdAt;
}

class SalesReturn {
  SalesReturn.fromJson(Json j)
    : id = j['id'] as String,
      number = j['number'] as int,
      invoiceId = (j['invoice'] as Json)['id'] as String,
      invoiceNumber = (j['invoice'] as Json)['invoiceNumber'] as String,
      customer = DocCustomer.fromJson(j['customer'] as Json),
      createdBy = Ref.fromJson(j['createdBy'] as Json),
      rep = Ref.maybe(j['rep']),
      warehouse = Ref.fromJson(j['warehouse'] as Json),
      items = toList(j['items'], LineItem.fromJson),
      total = toNum(j['total']),
      notes = toStr(j['notes']),
      cancelled = j['status'] == 'CANCELLED',
      cancelReason = toStr(j['cancelReason']),
      cancelledBy = Ref.maybe(j['cancelledBy']),
      cancelledAt = toDate(j['cancelledAt']),
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final int number;
  final String invoiceId;
  final String invoiceNumber;
  final DocCustomer customer;
  final Ref createdBy;

  /// Goods went to this rep's custody; null = the warehouse's main stock.
  final Ref? rep;
  final Ref warehouse;
  final List<LineItem> items;
  final num total;
  final String? notes;
  final bool cancelled;
  final String? cancelReason;
  final Ref? cancelledBy;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  String get destination =>
      rep != null ? 'عهدة ${rep!.name}' : warehouseLabel(warehouse.name);
}

/// productId -> quantity already returned (active returns only).
Map<String, num> returnedByProduct(List<SalesReturn> returns) {
  final map = <String, num>{};
  for (final r in returns.where((r) => !r.cancelled)) {
    for (final i in r.items) {
      map[i.product] = (map[i.product] ?? 0) + i.quantity;
    }
  }
  return map;
}

/// One line of a customer's account statement (كشف حساب).
class StatementLine {
  StatementLine({
    required this.kind,
    required this.id,
    required this.number,
    required this.date,
    required this.debit,
    required this.credit,
    required this.method,
    required this.createdBy,
    required this.cancelled,
    required this.pending,
    this.bounced = false,
  });

  final StatementKind kind;
  final String id;
  final String number;
  final DateTime date;

  /// Increases what the customer owes (invoice total).
  final num debit;

  /// Decreases it (up-front payment, collection, or returned goods).
  final num credit;
  final String method;
  final String createdBy;
  final bool cancelled;

  /// Payment still with the rep: shown, but not deducted until handed over.
  final bool pending;

  /// A bounced cheque: shown, never deducted.
  final bool bounced;

  /// Running balance after this line; null for cancelled lines.
  num? balance;
}

enum StatementKind {
  invoice('فاتورة بيع'),
  collection('فاتورة تحصيل'),
  salesReturn('فاتورة مرتجع');

  const StatementKind(this.label);
  final String label;
}

/// Same as the web `buildStatement`: running balance in date order, newest first.
/// Cancelled entries are listed but skipped; payments still with the rep are deducted right away,
/// and bounced cheques never reduce it.
List<StatementLine> buildStatement(
  List<Invoice> invoices,
  List<Collection> collections, [
  List<SalesReturn> returns = const [],
]) {
  final lines = [
    for (final i in invoices)
      StatementLine(
        kind: StatementKind.invoice,
        id: i.id,
        number: i.invoiceNumber,
        date: i.createdAt,
        debit: i.total,
        credit: i.paidAmount,
        method: methodLabel(i.paymentMethod),
        createdBy: i.createdBy.name,
        cancelled: i.cancelled,
        pending: i.deposit.pending,
        bounced: i.deposit.bounced,
      ),
    for (final c in collections)
      StatementLine(
        kind: StatementKind.collection,
        id: c.id,
        number: c.receiptNumber,
        date: c.createdAt,
        debit: 0,
        credit: c.amount,
        method: methodLabel(c.paymentMethod),
        createdBy: c.createdBy.name,
        cancelled: c.cancelled,
        pending: c.deposit.pending,
        bounced: c.deposit.bounced,
      ),
    for (final r in returns)
      StatementLine(
        kind: StatementKind.salesReturn,
        id: r.id,
        number: '${r.number}',
        date: r.createdAt,
        debit: 0,
        credit: r.total,
        method: 'مرتجع بضاعة',
        createdBy: r.createdBy.name,
        cancelled: r.cancelled,
        pending: false,
      ),
  ]..sort((a, b) => a.date.compareTo(b.date));

  num balance = 0;
  for (final line in lines.where((l) => !l.cancelled)) {
    balance = round2(balance + line.debit - (line.bounced ? 0 : line.credit));
    line.balance = balance;
  }
  return lines.reversed.toList();
}
