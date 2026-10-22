/// Products, warehouses, stock movements and suppliers.
library;

import 'common.dart';

/// Products expiring within this many days are flagged.
const expiryWarningDays = 90;

class Product {
  Product.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      code = toStr(j['code']),
      unit = toStr(j['unit']),
      price = toNum(j['price']),
      quantity = toNum(j['quantity']),
      avgCost = j['avgCost'] as num?,
      lastCost = j['lastCost'] as num?,
      lastSupplier = Ref.maybe(j['lastSupplier']),
      lastPurchaseAt = toDate(j['lastPurchaseAt']),
      supplier = Ref.maybe(j['supplier']),
      minQuantity = j['minQuantity'] as num?,
      manufacturer = toStr(j['manufacturer']),
      expiryDate = toDate(j['expiryDate']),
      notes = toStr(j['notes']),
      isActive = j['isActive'] as bool? ?? true;

  final String id;
  final String name;
  final String? code;
  final String? unit;

  /// سعر البيع: only the default price on a new invoice line.
  final num price;

  /// Total stock across all warehouses and rep custody.
  final num quantity;

  /// Purchase costs: managers only (absent for reps).
  final num? avgCost;

  /// سعر الشراء: set on the product form or by the last warehouse receipt.
  final num? lastCost;
  final Ref? lastSupplier;
  final DateTime? lastPurchaseAt;

  /// Main supplier from the product form (managers only).
  final Ref? supplier;
  final num? minQuantity;
  final String? manufacturer;
  final DateTime? expiryDate;
  final String? notes;
  final bool isActive;

  String get label => unit == null ? name : '$name (${unitLabels[unit]})';
  bool get isLowStock => minQuantity != null && quantity <= minQuantity!;

  /// 'expired', 'soon' (within [expiryWarningDays]) or null.
  String? expiryState([DateTime? now]) {
    if (expiryDate == null) return null;
    final days = expiryDate!.difference(now ?? DateTime.now()).inHours / 24;
    if (days < 0) return 'expired';
    return days <= expiryWarningDays ? 'soon' : null;
  }
}

const movementTypes = [
  'RECEIVE',
  'ISSUE',
  'RETURN',
  'SALE',
  'SALE_CANCEL',
  'SALE_RETURN',
  'SALE_RETURN_CANCEL',
  'ADJUST',
  'TRANSFER',
  'SUPPLIER_RETURN',
  'SUPPLIER_RETURN_CANCEL',
];
const movementTypeLabels = {
  'RECEIVE': 'وارد للمخزن',
  'ISSUE': 'صرف لمندوب',
  'RETURN': 'مرتجع من مندوب',
  'SALE': 'بيع (فاتورة)',
  'SALE_CANCEL': 'إلغاء فاتورة',
  'SALE_RETURN': 'مرتجع من عميل',
  'SALE_RETURN_CANCEL': 'إلغاء مرتجع عميل',
  'ADJUST': 'تسوية جرد',
  'TRANSFER': 'تحويل لمخزن',
  'SUPPLIER_RETURN': 'مرتجع للمورد',
  'SUPPLIER_RETURN_CANCEL': 'إلغاء مرتجع مورد',
};

class Warehouse {
  Warehouse.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      notes = toStr(j['notes']),
      isActive = j['isActive'] as bool? ?? true,
      totalQuantity = toNum(j['totalQuantity']),
      repsCount = j['repsCount'] as int? ?? 0;

  final String id;
  final String name;
  final String? notes;
  final bool isActive;

  /// List only: main stock (custody not included) and number of reps.
  final num totalQuantity;
  final int repsCount;
}

class StockRow {
  StockRow.fromJson(Json j)
    : productId = (j['product'] as Json)['id'] as String,
      name = (j['product'] as Json)['name'] as String,
      code = toStr((j['product'] as Json)['code']),
      unit = toStr((j['product'] as Json)['unit']),
      quantity = toNum(j['quantity']);

  final String productId;
  final String name;
  final String? code;
  final String? unit;
  final num quantity;

  String get label => unit == null ? name : '$name (${unitLabels[unit]})';
}

num totalQuantity(List<StockRow> rows) =>
    rows.fold<num>(0, (s, r) => s + r.quantity);
Map<String, num> quantityMap(List<StockRow> rows) => {
  for (final r in rows) r.productId: r.quantity,
};

class RepCustody {
  RepCustody.fromJson(Json j)
    : rep = Ref.fromJson(j['rep'] as Json),
      custody = toList(j['custody'], StockRow.fromJson);

  final Ref rep;
  final List<StockRow> custody;
}

class WarehouseDetails {
  WarehouseDetails.fromJson(Json j)
    : warehouse = Warehouse.fromJson(j['warehouse'] as Json),
      stock = toList(j['stock'], StockRow.fromJson),
      reps = toList(j['reps'], RepCustody.fromJson);

  WarehouseDetails.copy(WarehouseDetails d, this.warehouse)
    : stock = d.stock,
      reps = d.reps;

  final Warehouse warehouse;
  final List<StockRow> stock;
  final List<RepCustody> reps;
}

/// A sales rep's own goods: custody + the main stock of their warehouse.
class MyStock {
  MyStock.fromJson(Json j)
    : warehouse = j['warehouse'] == null
          ? null
          : Warehouse.fromJson(j['warehouse'] as Json),
      custody = toList(j['custody'], StockRow.fromJson),
      warehouseStock = toList(j['warehouseStock'], StockRow.fromJson);

  final Warehouse? warehouse;
  final List<StockRow> custody;
  final List<StockRow> warehouseStock;
}

class MovementItem {
  MovementItem.fromJson(Json j)
    : product = j['product'] as String,
      name = j['name'] as String? ?? '',
      quantity = toNum(j['quantity']),
      fromCustody = toNum(j['fromCustody']),
      unitCost = j['unitCost'] as num?;

  final String product;
  final String name;
  final num quantity;
  final num fromCustody;

  /// Purchase price: RECEIVE only.
  final num? unitCost;
}

class Movement {
  Movement.fromJson(Json j)
    : id = j['id'] as String,
      type = j['type'] as String,
      number = j['number'] as int?,
      warehouse = Ref.maybe(j['warehouse']),
      toWarehouse = Ref.maybe(j['toWarehouse']),
      rep = Ref.maybe(j['rep']),
      invoice = j['invoice'] == null
          ? null
          : (
              id: (j['invoice'] as Json)['id'] as String,
              number: (j['invoice'] as Json)['invoiceNumber'] as String,
            ),
      supplier = j['supplier'] == null
          ? null
          : Supplier.ref(j['supplier'] as Json),
      items = toList(j['items'], MovementItem.fromJson),
      notes = toStr(j['notes']),
      createdBy = Ref.maybe(j['createdBy']),
      createdAt = toDate(j['createdAt'])!,
      cancelledAt = toDate(j['cancelledAt']),
      cancelReason = toStr(j['cancelReason']),
      paidAmount = j['paidAmount'] as num?,
      _totalCost = j['totalCost'] as num?;

  final String id;
  final String type;

  /// RECEIVE / ISSUE / RETURN / SUPPLIER_RETURN only (printable documents).
  final int? number;
  final Ref? warehouse;

  /// TRANSFER only: the receiving warehouse. (ADJUST items have signed quantities.)
  final Ref? toWarehouse;
  final Ref? rep;
  final ({String id, String number})? invoice;
  final Supplier? supplier;
  final List<MovementItem> items;
  final String? notes;
  final Ref? createdBy;
  final DateTime createdAt;

  /// SUPPLIER_RETURN only: set once cancelled.
  final DateTime? cancelledAt;
  final String? cancelReason;

  /// RECEIVE only: what was actually paid; null means fully paid or a pre-debt record.
  /// (SUPPLIER_RETURN: null, so [remaining] is 0 and [totalCost] is what came off the debt.)
  final num? paidAmount;
  final num? _totalCost;

  num get totalCost =>
      _totalCost ??
      round2(items.fold<num>(0, (s, i) => s + i.quantity * (i.unitCost ?? 0)));
  num get paid => paidAmount ?? totalCost;
  num get remaining => round2(totalCost - paid);

  /// Document type of the movement's own print-out (sales print their invoice instead).
  String? get documentType => const {
    'RECEIVE': 'PURCHASE',
    'ISSUE': 'ISSUE',
    'RETURN': 'RETURN',
    'SUPPLIER_RETURN': 'SUPPLIER_RETURN',
  }[type];
}

class Supplier {
  Supplier.fromJson(Json j)
    : id = j['id'] as String,
      name = j['name'] as String,
      phone = toStr(j['phone']),
      company = toStr(j['company']),
      address = toStr(j['address']),
      notes = toStr(j['notes']),
      isActive = j['isActive'] as bool? ?? true,
      receipts = j['receipts'] as int? ?? 0,
      totalPurchases = toNum(j['totalPurchases']),
      lastPurchaseAt = toDate(j['lastPurchaseAt']),
      debt = toNum(j['debt']);

  /// The populated supplier on a movement (name + maybe contact details).
  Supplier.ref(Json j) : this.fromJson(j);

  final String id;
  final String name;
  final String? phone;
  final String? company;
  final String? address;
  final String? notes;
  final bool isActive;

  /// Number of warehouse receipts from this supplier and Σ quantity × purchase price.
  final int receipts;
  final num totalPurchases;
  final DateTime? lastPurchaseAt;

  /// What the company still owes this supplier.
  final num debt;
}

class SupplierPayment {
  SupplierPayment.fromJson(Json j)
    : id = j['id'] as String,
      number = j['number'] as int,
      amount = toNum(j['amount']),
      paymentMethod = j['paymentMethod'] as String,
      chequeNumber = toStr(j['chequeNumber']),
      chequeDueDate = toDate(j['chequeDueDate']),
      notes = toStr(j['notes']),
      status = j['status'] as String,
      cancelReason = toStr(j['cancelReason']),
      createdBy = Ref.maybe(j['createdBy']),
      cancelledBy = Ref.maybe(j['cancelledBy']),
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final int number;
  final num amount;
  final String paymentMethod;
  final String? chequeNumber;
  final DateTime? chequeDueDate;
  final String? notes;
  final String status;
  final String? cancelReason;
  final Ref? createdBy;
  final Ref? cancelledBy;
  final DateTime createdAt;

  bool get isCancelled => status == 'CANCELLED';
}

/// One purchase of a product, from a RECEIVE movement.
typedef PurchaseLine = ({
  Movement movement,
  num quantity,
  num unitCost,
  num total,
});

/// One supplier's purchases of a product.
typedef SupplierPurchases = ({
  Supplier? supplier,
  int count,
  num quantity,
  num total,
  num avgCost,
  num lastCost,
  DateTime lastDate,
});

/// A product's purchase history (RECEIVE movements, newest first): per supplier and overall. Same as the web.
class PurchaseHistory {
  PurchaseHistory(List<Movement> movements, String productId)
    : lines = [
        for (final m in movements)
          for (final i in m.items)
            if (i.product == productId && i.unitCost != null)
              (
                movement: m,
                quantity: i.quantity,
                unitCost: i.unitCost!,
                total: i.quantity * i.unitCost!,
              ),
      ];

  final List<PurchaseLine> lines;

  num get quantity => lines.fold<num>(0, (s, l) => s + l.quantity);
  num get total => lines.fold<num>(0, (s, l) => s + l.total);
  num? get avgCost => quantity == 0 ? null : total / quantity;
  num? get minCost => lines.isEmpty
      ? null
      : lines.map((l) => l.unitCost).reduce((a, b) => a < b ? a : b);
  num? get maxCost => lines.isEmpty
      ? null
      : lines.map((l) => l.unitCost).reduce((a, b) => a > b ? a : b);

  List<SupplierPurchases> get suppliers {
    final groups = <String, List<PurchaseLine>>{};
    for (final l in lines) {
      (groups[l.movement.supplier?.id ?? ''] ??= []).add(l);
    }
    return [
      for (final g in groups.values)
        (
          supplier: g.first.movement.supplier,
          count: g.length,
          quantity: g.fold<num>(0, (s, l) => s + l.quantity),
          total: g.fold<num>(0, (s, l) => s + l.total),
          avgCost:
              g.fold<num>(0, (s, l) => s + l.total) /
              g.fold<num>(0, (s, l) => s + l.quantity),
          // Lines are newest first, so the first is the supplier's last purchase.
          lastCost: g.first.unitCost,
          lastDate: g.first.movement.createdAt,
        ),
    ];
  }
}

// ---------- طلبات العهدة ----------

const custodyRequestStatusLabels = {
  'PENDING': 'مستني الصرف',
  'ISSUED': 'اتصرف',
  'REJECTED': 'مرفوض',
  'CANCELLED': 'ملغي',
};

/// طلب عهدة: a sales rep asks their warehouse for goods.
class CustodyRequest {
  CustodyRequest.fromJson(Json j)
    : id = j['id'] as String,
      number = toNum(j['number']).toInt(),
      rep = Ref.fromJson(j['rep'] as Json),
      warehouse = Ref.fromJson(j['warehouse'] as Json),
      items = [
        for (final i in j['items'] as List? ?? const [])
          (
            productId: (i as Json)['product'] as String,
            name: i['name'] as String,
            quantity: toNum(i['quantity']),
          ),
      ],
      notes = toStr(j['notes']),
      status = j['status'] as String,
      movement = j['movement'] == null
          ? null
          : (
              id: (j['movement'] as Json)['id'] as String,
              number: toNum((j['movement'] as Json)['number']).toInt(),
            ),
      reason = toStr(j['reason']),
      handledBy = Ref.maybe(j['handledBy']),
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final int number;
  final Ref rep;
  final Ref warehouse;

  /// What was requested (the issued quantities are on [movement]).
  final List<({String productId, String name, num quantity})> items;
  final String? notes;

  /// PENDING | ISSUED | REJECTED | CANCELLED
  final String status;

  /// The ISSUE movement once issued.
  final ({String id, int number})? movement;

  /// Why it was rejected.
  final String? reason;
  final Ref? handledBy;
  final DateTime createdAt;

  bool get pending => status == 'PENDING';
}

/// مرتجع للمورد: a product bought from the supplier, what's left of it to return, and its price
/// (the last price bought from them).
class Returnable {
  Returnable.fromJson(Json j)
    : productId = j['productId'] as String,
      name = j['name'] as String? ?? '',
      unitCost = toNum(j['unitCost']),
      quantity = toNum(j['quantity']),
      warehouseIds = [...(j['warehouseIds'] as List? ?? []).cast<String>()];

  final String productId;
  final String name;
  final num unitCost;
  final num quantity;

  /// Warehouses it was received into from this supplier.
  final List<String> warehouseIds;
}
