import 'package:flutter/foundation.dart';

import '../../core/format.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../data/models/inventory.dart';
import '../../data/models/sales.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/sales_repository.dart';

class InvoiceLine {
  InvoiceLine([this.productId, this.quantity = 1]);
  String? productId;
  int quantity;

  /// null = the product's sale price; the seller may type any price.
  num? unitPrice;

  /// null = the customer's discount.
  num? discountPercent;
}

typedef LineCalc = ({
  Product? product,
  num price,
  num discount,
  num gross,
  num total,
  num custody,
  num warehouse,
  num fromCustody,
  num fromWarehouse,
  bool overStock,
});

/// State and rules of the new-invoice form (same as the web invoice form).
/// A rep sells from their custody first, then their warehouse; a manager picks the warehouse.
class InvoiceFormViewModel extends ChangeNotifier {
  InvoiceFormViewModel({
    required this.customerId,
    required this.isManager,
    this.visitId,
    CustomerRepository? customers,
    InventoryRepository? inventory,
    SalesRepository? sales,
  }) : _customers = customers,
       _inventory = inventory,
       _sales = sales;

  final String customerId;
  final String? visitId;
  final bool isManager;
  final CustomerRepository? _customers;
  final InventoryRepository? _inventory;
  final SalesRepository? _sales;

  // Loaded data
  bool loading = true;
  Object? loadError;
  Customer? customer;
  List<Product> products = [];
  List<Warehouse> warehouses = [];
  bool stockLoaded = false;
  String? warehouseName;
  Map<String, num> custody = {};
  Map<String, num> warehouseStock = {};

  // Form
  String? warehouseId;
  final lines = [InvoiceLine()];
  num paid = 0;
  String? method;
  DateTime? chequeDue;
  bool saving = false;

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final (c, p, w) = await (
        _customers!.get(customerId),
        _inventory!.products(active: true),
        isManager ? _inventory.warehouses() : Future.value(<Warehouse>[]),
      ).wait;
      customer = c;
      products = p;
      warehouses = w.where((x) => x.isActive).toList();
      if (!isManager) {
        final s = await _inventory.myStock();
        _setStock(
          s.warehouse?.name,
          quantityMap(s.custody),
          quantityMap(s.warehouseStock),
        );
      }
    } catch (e) {
      loadError = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> selectWarehouse(String id) async {
    warehouseId = id;
    stockLoaded = false;
    notifyListeners();
    try {
      final d = await _inventory!.warehouse(id);
      if (warehouseId == id)
        _setStock(d.warehouse.name, {}, quantityMap(d.stock));
    } catch (_) {
      stockLoaded = false; // the backend still checks stock on save
    }
    notifyListeners();
  }

  void _setStock(
    String? name,
    Map<String, num> custodyMap,
    Map<String, num> stockMap,
  ) {
    warehouseName = name;
    custody = custodyMap;
    warehouseStock = stockMap;
    stockLoaded = true;
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  void addLine() => update(() => lines.add(InvoiceLine()));
  void removeLine(int i) => update(() => lines.removeAt(i));

  /// Products already chosen in other lines are hidden to avoid duplicate lines.
  List<Product> available(int lineIndex) => [
    for (final p in products)
      if (!lines.indexed.any(
        (e) => e.$1 != lineIndex && e.$2.productId == p.id,
      ))
        p,
  ];

  Product? product(String? id) =>
      id == null ? null : products.where((p) => p.id == id).firstOrNull;

  LineCalc calc(InvoiceLine line) {
    final p = product(line.productId);
    final cu = p == null ? 0 : custody[p.id] ?? 0;
    final wh = p == null ? 0 : warehouseStock[p.id] ?? 0;
    final q = line.quantity;
    final d = line.discountPercent ?? customerDiscount;
    final price = line.unitPrice ?? p?.price ?? 0;
    return (
      product: p,
      price: price,
      discount: d,
      gross: p == null ? 0 : round2(price * q),
      total: p == null ? 0 : round2(price * q * (1 - d / 100)),
      custody: cu,
      warehouse: wh,
      fromCustody: q < cu ? q : cu,
      fromWarehouse: q - cu > 0 ? q - cu : 0,
      overStock: p != null && stockLoaded && q > cu + wh,
    );
  }

  bool get hasOverStock => lines.any((l) => calc(l).overStock);

  /// The customer's default discount; a rep can't give more (the backend checks too).
  num get customerDiscount => customer?.discountPercent ?? 0;
  num get maxDiscount => isManager ? 100 : customerDiscount;
  bool get canDiscount => isManager || customerDiscount > 0;
  num get discountTotal =>
      round2(lines.fold<num>(0, (s, l) => s + calc(l).gross - calc(l).total));

  /// From the customer's payment terms; null = no terms.
  DateTime? get dueDate {
    final days = customer?.paymentTermDays;
    return days == null ? null : DateTime.now().add(Duration(days: days));
  }

  num get overdue => customer?.overdue ?? 0;
  num get total => round2(lines.fold<num>(0, (s, l) => s + calc(l).total));

  /// Debt before this invoice minus money collected but not handed over; payments above the total settle it.
  num get previousDebt => customer?.collectable ?? 0;
  num get maxPaid => round2(total + previousDebt);
  num get remaining => total - paid > 0 ? round2(total - paid) : 0;
  num get previousDebtPaid => paid - total > 0 ? round2(paid - total) : 0;
  num get debtAfter => round2(previousDebt + total - paid);
  bool get isCheque => paid > 0 && method == 'CHEQUE';

  /// Rep not attached to any warehouse: selling is blocked by the backend.
  bool get noWarehouse => !isManager && stockLoaded && warehouseName == null;

  String? get paymentError {
    if (paid > maxPaid) {
      return previousDebt > 0
          ? 'المبلغ المدفوع أكبر من إجمالي الفاتورة + المديونية السابقة.'
          : 'المبلغ المدفوع أكبر من إجمالي الفاتورة.';
    }
    if (paid > 0 && method == null) return 'اختر طريقة السداد.';
    if (lines.any((l) => calc(l).discount > maxDiscount))
      return 'الخصم أكبر من المسموح ($maxDiscount%).';
    if (overdue > 0 && !isManager && debtAfter > previousDebt) {
      return 'العميل عليه متأخرات (${money(overdue)}). اتحصّلها الأول، أو خلي الفاتورة مدفوعة بالكامل.';
    }
    if (overLimit != null && !isManager) {
      return 'المديونية بعد الفاتورة أكبر من حد الائتمان (${money(overLimit!)}). زوّد المدفوع أو قلّل الكمية.';
    }
    return null;
  }

  /// The credit limit when this invoice goes over it: blocks a rep (same rule as the backend), warns a manager.
  num? get overLimit {
    final limit = customer?.creditLimit;
    return limit != null && debtAfter > limit && debtAfter > previousDebt
        ? limit
        : null;
  }

  bool get linesValid =>
      lines.every((l) => l.productId != null && l.quantity >= 1);

  bool get canSubmit =>
      linesValid &&
      paymentError == null &&
      !hasOverStock &&
      !noWarehouse &&
      (!isManager || warehouseId != null) &&
      !saving;

  Json body({
    required String invoiceNumber,
    required String chequeNumber,
    required String notes,
  }) => {
    'invoiceNumber': invoiceNumber.trim(),
    'customerId': customerId,
    'visitId': visitId,
    'warehouseId': isManager ? warehouseId : null,
    'items': [
      for (final l in lines)
        {
          'productId': l.productId,
          'quantity': l.quantity,
          'unitPrice': ?l.unitPrice,
          'discountPercent': ?l.discountPercent,
        },
    ],
    'paidAmount': round2(paid),
    'paymentMethod': paid > 0 ? method : null,
    'chequeNumber': isCheque && chequeNumber.trim().isNotEmpty
        ? chequeNumber.trim()
        : null,
    'chequeDueDate': isCheque && chequeDue != null
        ? '${chequeDue!.year}-${'${chequeDue!.month}'.padLeft(2, '0')}-${'${chequeDue!.day}'.padLeft(2, '0')}'
        : null,
    'notes': notes.trim().isEmpty ? null : notes.trim(),
  };

  Future<Invoice> submit(Json body) async {
    update(() => saving = true);
    try {
      return await _sales!.createInvoice(body);
    } finally {
      update(() => saving = false);
    }
  }
}
