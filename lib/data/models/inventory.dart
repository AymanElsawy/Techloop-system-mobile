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
  final num price;

  /// Total stock across all warehouses and rep custody.
  final num quantity;

  /// Purchase costs: managers only (absent for reps).
  final num? avgCost;
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

const movementTypes = ['RECEIVE', 'ISSUE', 'RETURN', 'SALE', 'SALE_CANCEL', 'SALE_RETURN', 'SALE_RETURN_CANCEL'];
const movementTypeLabels = {
  'RECEIVE': 'وارد للمخزن',
  'ISSUE': 'صرف لمندوب',
  'RETURN': 'مرتجع من مندوب',
  'SALE': 'بيع (فاتورة)',
  'SALE_CANCEL': 'إلغاء فاتورة',
  'SALE_RETURN': 'مرتجع من عميل',
  'SALE_RETURN_CANCEL': 'إلغاء مرتجع عميل',
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

num totalQuantity(List<StockRow> rows) => rows.fold<num>(0, (s, r) => s + r.quantity);
Map<String, num> quantityMap(List<StockRow> rows) => {for (final r in rows) r.productId: r.quantity};

class RepCustody {
  RepCustody.fromJson(Json j) : rep = Ref.fromJson(j['rep'] as Json), custody = toList(j['custody'], StockRow.fromJson);

  final Ref rep;
  final List<StockRow> custody;
}

class WarehouseDetails {
  WarehouseDetails.fromJson(Json j)
    : warehouse = Warehouse.fromJson(j['warehouse'] as Json),
      stock = toList(j['stock'], StockRow.fromJson),
      reps = toList(j['reps'], RepCustody.fromJson);

  WarehouseDetails.copy(WarehouseDetails d, this.warehouse) : stock = d.stock, reps = d.reps;

  final Warehouse warehouse;
  final List<StockRow> stock;
  final List<RepCustody> reps;
}

/// A sales rep's own goods: custody + the main stock of their warehouse.
class MyStock {
  MyStock.fromJson(Json j)
    : warehouse = j['warehouse'] == null ? null : Warehouse.fromJson(j['warehouse'] as Json),
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
      rep = Ref.maybe(j['rep']),
      invoice = j['invoice'] == null
          ? null
          : (id: (j['invoice'] as Json)['id'] as String, number: (j['invoice'] as Json)['invoiceNumber'] as String),
      supplier = j['supplier'] == null ? null : Supplier.ref(j['supplier'] as Json),
      items = toList(j['items'], MovementItem.fromJson),
      notes = toStr(j['notes']),
      createdBy = Ref.maybe(j['createdBy']),
      createdAt = toDate(j['createdAt'])!;

  final String id;
  final String type;

  /// RECEIVE / ISSUE / RETURN only (printable documents).
  final int? number;
  final Ref? warehouse;
  final Ref? rep;
  final ({String id, String number})? invoice;
  final Supplier? supplier;
  final List<MovementItem> items;
  final String? notes;
  final Ref? createdBy;
  final DateTime createdAt;

  num get totalCost => round2(items.fold<num>(0, (s, i) => s + i.quantity * (i.unitCost ?? 0)));

  /// Document type of the movement's own print-out (sales print their invoice instead).
  String? get documentType => const {'RECEIVE': 'PURCHASE', 'ISSUE': 'ISSUE', 'RETURN': 'RETURN'}[type];
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
      lastPurchaseAt = toDate(j['lastPurchaseAt']);

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
}
