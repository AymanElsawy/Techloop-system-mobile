import 'common.dart';

const reportGroupLabels = {
  'product': 'الصنف',
  'governorate': 'المحافظة',
  'rep': 'المندوب',
};

class SalesRow {
  SalesRow.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      quantity = toNum(j['quantity']),
      invoices = toNum(j['invoices']),
      sales = toNum(j['sales']),
      returns = toNum(j['returns']),
      net = toNum(j['net']),
      cost = toNum(j['cost']),
      profit = toNum(j['profit']),
      costMissing = j['costMissing'] as bool? ?? false;

  final String id;
  final String name;
  final num quantity;
  final num invoices;
  final num sales;
  final num returns;
  final num net;
  final num cost;
  final num profit;

  /// Some lines had no purchase price (cost counted as 0).
  final bool costMissing;
}

/// Profit as a share of net sales; null when there are no sales.
num? margin(num net, num profit) => net > 0 ? profit / net : null;

class SalesReport {
  SalesReport.fromJson(Json j)
    : groupBy = j['groupBy'] as String,
      rows = toList(j['rows'], SalesRow.fromJson),
      totals = SalesRow.fromJson({
        ...j['totals'] as Json,
        'id': '',
        'name': 'الإجمالي',
      });

  final String groupBy;
  final List<SalesRow> rows;
  final SalesRow totals;
}

class AgingRow {
  AgingRow.fromJson(Json j)
    : customer = Ref.fromJson(j['customer'] as Json),
      governorate = (j['customer'] as Json)['governorate'] as String? ?? '',
      debt = toNum(j['debt']),
      pending = toNum(j['pending']),
      buckets = [for (final b in j['buckets'] as List) toNum(b)],
      oldestDays = toNum(j['oldestDays']).toInt();

  final Ref customer;
  final String governorate;
  final num debt;
  final num pending;
  final List<num> buckets; // لم يستحق, 0-30, 31-60, 61-90, 90+ (days past due)
  final int oldestDays;
}

class AgingReport {
  AgingReport.fromJson(Json j)
    : buckets = List<String>.from(j['buckets'] as List),
      rows = toList(j['rows'], AgingRow.fromJson),
      totalDebt = toNum((j['totals'] as Json)['debt']),
      totalBuckets = [
        for (final b in (j['totals'] as Json)['buckets'] as List) toNum(b),
      ];

  final List<String> buckets;
  final List<AgingRow> rows;
  final num totalDebt;
  final List<num> totalBuckets;
}

/// What one supplier sold one product for.
class PurchaseRow {
  PurchaseRow.fromJson(Json j)
    : product = Ref.fromJson(j['product'] as Json),
      supplier = Ref.fromJson(j['supplier'] as Json),
      receipts = toNum(j['receipts']).toInt(),
      quantity = toNum(j['quantity']),
      total = toNum(j['total']),
      avgCost = toNum(j['avgCost']),
      minCost = toNum(j['minCost']),
      maxCost = toNum(j['maxCost']),
      lastCost = toNum(j['lastCost']),
      lastAt = toDate(j['lastAt'])!,
      currentAvgCost = j['currentAvgCost'] as num?;

  final Ref product;
  final Ref supplier;
  final int receipts;
  final num quantity;
  final num total;
  final num avgCost;
  final num minCost;
  final num maxCost;
  final num lastCost;
  final DateTime lastAt;
  final num? currentAvgCost;
}

// ---------- العملاء / الموردين ----------

/// `customers` or `suppliers`: the report path on the API.
const partyReportLabels = {'customers': 'العملاء', 'suppliers': 'الموردين'};

/// A customer (or supplier) in the period. Customers: [count] = invoices, [amount] = net sales,
/// [paid] = collected, [balance] = what they owe today. Suppliers: [count] = receipts,
/// [amount] = purchases, [paid] = what we paid, [balance] = what we owe today.
class PartyRow {
  PartyRow.fromJson(Json j, {required bool customers})
    : party = Ref.fromJson(j[customers ? 'customer' : 'supplier'] as Json),
      hint = toStr(
        (j[customers ? 'customer' : 'supplier'] as Json)[customers
            ? 'governorate'
            : 'phone'],
      ),
      count = toNum(j[customers ? 'invoices' : 'receipts']).toInt(),
      amount = toNum(j[customers ? 'net' : 'purchases']),
      returns = toNum(j['returns']),
      profit = j['profit'] as num?,
      paid = toNum(j[customers ? 'collected' : 'paid']),
      balance = toNum(j[customers ? 'balance' : 'debt']);

  final Ref party;

  /// Governorate (customer) or phone (supplier).
  final String? hint;
  final int count;
  final num amount;
  final num returns;

  /// Customers only.
  final num? profit;
  final num paid;
  final num balance;
}

/// One document in a customer / supplier report, oldest first.
class ReportLine {
  ReportLine.fromJson(Json j)
    : kind = j['kind'] as String,
      id = j['id'] as String,
      number = j['number'] as String,
      date = toDate(j['date'])!,
      debit = toNum(j['debit']),
      credit = toNum(j['credit']),
      method = toStr(j['method']),
      bounced = j['bounced'] as bool? ?? false,
      pending = j['pending'] as bool? ?? false,
      balance = toNum(j['balance']);

  /// invoice | return | collection | receipt | payment
  final String kind;
  final String id;
  final String number;
  final DateTime date;

  /// Customer: the sale. Supplier: the purchase.
  final num debit;

  /// Customer: paid, collected or returned. Supplier: what we paid.
  final num credit;

  /// Null on an invoice = deferred.
  final String? method;
  final bool bounced;

  /// Paid, but the money is still with the rep (already deducted from the balance).
  final bool pending;

  /// Running balance after this line, like كشف الحساب.
  final num balance;
}

const reportLineLabels = {
  'invoice': 'فاتورة بيع',
  'return': 'مرتجع',
  'collection': 'تحصيل',
  'receipt': 'وارد',
  'payment': 'دفعة',
};

/// One customer / supplier in detail: totals ([PartyRow] fields over the period, [PartyRow.balance]
/// today), what was bought per product, and every document.
class PartyReport {
  PartyReport.fromJson(Json j, {required bool customers})
    : summary = PartyRow.fromJson({
        ...j['totals'] as Json,
        customers ? 'customer' : 'supplier':
            j[customers ? 'customer' : 'supplier'],
        customers ? 'balance' : 'debt':
            (j[customers ? 'customer' : 'supplier'] as Json)[customers
                ? 'balance'
                : 'debt'],
      }, customers: customers),
      products = [
        for (final p in j['products'] as List? ?? const [])
          customers
              ? (
                  name: (p as Json)['name'] as String,
                  quantity: toNum(p['quantity']),
                  amount: toNum(p['net']),
                  extra: toNum(p['profit']),
                )
              : (
                  name: ((p as Json)['product'] as Json)['name'] as String,
                  quantity: toNum(p['quantity']),
                  amount: toNum(p['total']),
                  extra: toNum(p['avgCost']),
                ),
      ],
      lines = toList(j['lines'], ReportLine.fromJson),
      opening = toNum(j['opening']),
      closing = toNum(j['closing']),
      phone = toStr((j[customers ? 'customer' : 'supplier'] as Json)['phone']);

  final PartyRow summary;

  /// Balance before / after the period (customer: owes us; supplier: we owe).
  final num opening;
  final num closing;
  final String? phone;

  /// Customers: net sales, [extra] = profit. Suppliers: total cost, [extra] = average price.
  final List<({String name, num quantity, num amount, num extra})> products;
  final List<ReportLine> lines;
}
