import 'package:flutter_test/flutter_test.dart';
import 'package:techloop_mobile/data/models/customer.dart';
import 'package:techloop_mobile/data/models/inventory.dart';
import 'package:techloop_mobile/data/models/sales.dart';
import 'package:techloop_mobile/features/sales/invoice_form_view_model.dart';

Map<String, dynamic> _person = {'id': 'u', 'name': 'Rep'};
Map<String, dynamic> _customer = {'id': 'c', 'name': 'C', 'governorate': 'الجيزة'};

Invoice _invoice(String id, String date, num total, num paid, {bool cancelled = false, bool pending = false}) =>
    Invoice.fromJson({
      'id': id,
      'invoiceNumber': id,
      'customer': _customer,
      'createdBy': _person,
      'items': [],
      'total': total,
      'paidAmount': paid,
      'paymentMethod': paid > 0 ? 'CASH' : null,
      'status': cancelled ? 'CANCELLED' : 'ACTIVE',
      'depositStatus': pending ? 'PENDING' : null,
      'createdAt': date,
    });

Collection _collection(
  String id,
  String date,
  num amount, {
  bool cancelled = false,
  bool pending = false,
  String? chequeStatus,
}) =>
    Collection.fromJson({
      'id': id,
      'receiptNumber': id,
      'customer': _customer,
      'createdBy': _person,
      'amount': amount,
      'paymentMethod': 'CASH',
      'status': cancelled ? 'CANCELLED' : 'ACTIVE',
      'depositStatus': pending ? 'PENDING' : null,
      'chequeStatus': chequeStatus,
      'createdAt': date,
    });

SalesReturn _return(String id, String date, num total, {bool cancelled = false}) => SalesReturn.fromJson({
  'id': id,
  'number': 1,
  'invoice': {'id': 'I1', 'invoiceNumber': 'I1'},
  'customer': _customer,
  'createdBy': _person,
  'warehouse': {'id': 'w', 'name': 'W'},
  'items': [],
  'total': total,
  'status': cancelled ? 'CANCELLED' : 'ACTIVE',
  'createdAt': date,
});

void main() {
  group('buildStatement (same cases as the web spec)', () {
    test('running balance in date order, newest first, skipping cancelled lines', () {
      final lines = buildStatement(
        [
          _invoice('I1', '2026-09-01', 5000, 0),
          _invoice('I2', '2026-09-10', 1000, 100),
          _invoice('IX', '2026-09-05', 999, 0, cancelled: true),
        ],
        [_collection('C1', '2026-09-03', 2000), _collection('CX', '2026-09-04', 50, cancelled: true)],
      );
      expect(
        [for (final l in lines) (l.number, l.balance)],
        [('I2', 3900), ('IX', null), ('CX', null), ('C1', 3000), ('I1', 5000)],
      );
    });

    test('payments still with the rep are deducted right away', () {
      final lines = buildStatement(
        [_invoice('I1', '2026-09-01', 1000, 0)],
        [_collection('C1', '2026-09-03', 300, pending: true)],
      );
      expect([for (final l in lines) (l.number, l.pending, l.balance)], [('C1', true, 700), ('I1', false, 1000)]);
    });

    test('a bounced cheque is never deducted', () {
      final lines = buildStatement(
        [_invoice('I1', '2026-09-01', 1000, 0)],
        [_collection('C1', '2026-09-03', 300, chequeStatus: 'BOUNCED')],
      );
      expect([for (final l in lines) (l.number, l.bounced, l.balance)], [('C1', true, 1000), ('I1', false, 1000)]);
    });

    test('active sales returns reduce the balance; cancelled ones do not', () {
      final lines = buildStatement(
        [_invoice('I1', '2026-09-01', 1000, 0)],
        [],
        [_return('R1', '2026-09-02', 300), _return('RX', '2026-09-03', 999, cancelled: true)],
      );
      expect(
        [for (final l in lines) (l.kind, l.balance)],
        [(StatementKind.salesReturn, null), (StatementKind.salesReturn, 700), (StatementKind.invoice, 1000)],
      );
    });
  });

  group('InvoiceFormViewModel', () {
    InvoiceFormViewModel vm({required bool manager}) => InvoiceFormViewModel(customerId: 'c', isManager: manager)
      ..customer = Customer.fromJson({
        ..._customer,
        'status': 'APPROVED',
        'debit': 300, // already net of the 200 still with the rep
        'pendingPayments': 200,
        'createdAt': '2026-09-01',
      })
      ..products = [
        Product.fromJson({'id': 'p1', 'name': 'محلول', 'price': 100}),
        Product.fromJson({'id': 'p2', 'name': 'تسمين', 'price': 50}),
      ];

    test('a rep sells from custody first, then the warehouse, and cannot exceed both', () {
      final m = vm(manager: false)
        ..custody = {'p1': 3}
        ..warehouseStock = {'p1': 5}
        ..warehouseName = 'W'
        ..stockLoaded = true;
      m.lines.first
        ..productId = 'p1'
        ..quantity = 4;
      final l = m.calc(m.lines.first);
      expect((l.total, l.fromCustody, l.fromWarehouse, l.overStock), (400, 3, 1, false));

      m.lines.first.quantity = 9;
      expect(m.calc(m.lines.first).overStock, isTrue);
      expect(m.canSubmit, isFalse);
    });

    test('a rep may sell at any price; empty price = the sale price', () {
      final m = vm(manager: false)..warehouseName = 'W';
      m.lines.first
        ..productId = 'p1'
        ..quantity = 2;
      expect(m.calc(m.lines.first).total, 200);
      m.lines.first.unitPrice = 130;
      expect((m.calc(m.lines.first).price, m.total), (130, 260));
      final body = m.body(invoiceNumber: '1', chequeNumber: '', notes: '');
      expect((body['items'] as List).first['unitPrice'], 130);
    });

    test('customer discount applies by default; a rep cannot exceed it; overdue blocks credit sales for a rep', () {
      Customer withTerms({num overdue = 0}) => Customer.fromJson({
        ..._customer,
        'status': 'APPROVED',
        'debit': 0,
        'pendingPayments': 0,
        'discountPercent': 10,
        'paymentTermDays': 30,
        'overdue': overdue,
        'createdAt': '2026-09-01',
      });
      final m = vm(manager: false)
        ..customer = withTerms()
        ..warehouseName = 'W';
      m.lines.first
        ..productId = 'p1'
        ..quantity = 2; // 200 − 10%
      expect((m.calc(m.lines.first).total, m.discountTotal, m.total), (180, 20, 180));
      expect(m.dueDate!.difference(DateTime.now()).inDays, closeTo(30, 1));

      m.lines.first.discountPercent = 15;
      expect(m.paymentError, contains('الخصم'));
      m.lines.first.discountPercent = 5;
      expect((m.total, m.paymentError), (190, null));

      m.customer = withTerms(overdue: 100);
      expect(m.paymentError, contains('متأخرات'));
      m.paid = 190; // fully paid: allowed
      m.method = 'CASH';
      expect(m.paymentError, isNull);
      expect(vm(manager: true).maxDiscount, 100);
    });

    test('paying above the total settles previous debt (rep-held money already deducted)', () {
      final m = vm(manager: true)..warehouseId = 'w';
      m.lines.first
        ..productId = 'p2'
        ..quantity = 2; // 100
      // previous debt = 300 (debit is already net of pending), so up to 400 can be paid.
      expect((m.total, m.previousDebt, m.maxPaid), (100, 300, 400));

      m.paid = 250;
      expect(m.paymentError, 'اختر طريقة السداد.');
      m.method = 'CASH';
      expect((m.paymentError, m.previousDebtPaid, m.remaining, m.debtAfter), (null, 150, 0, 150));
      expect(m.canSubmit, isTrue);

      m.paid = 401;
      expect(m.paymentError, isNotNull);
    });

    test('a product is offered only once across lines', () {
      final m = vm(manager: true);
      m.lines.first.productId = 'p1';
      m.addLine();
      expect(m.available(1).map((p) => p.id), ['p2']);
    });
  });

  test('PurchaseHistory: per supplier and overall weighted average', () {
    Movement receive(String id, String date, String supplier, List<Map<String, dynamic>> items) =>
        Movement.fromJson({
          'id': id,
          'type': 'RECEIVE',
          'number': 1,
          'warehouse': {'id': 'w', 'name': 'W'},
          'supplier': {'id': supplier, 'name': supplier},
          'items': items,
          'createdAt': date,
        });
    final h = PurchaseHistory([
      receive('m3', '2026-10-01', 'A', [{'product': 'p', 'quantity': 10, 'unitCost': 12}]),
      receive('m2', '2026-09-15', 'B', [
        {'product': 'x', 'quantity': 5, 'unitCost': 1},
        {'product': 'p', 'quantity': 20, 'unitCost': 9},
      ]),
      receive('m1', '2026-09-01', 'A', [{'product': 'p', 'quantity': 10, 'unitCost': 10}]),
    ], 'p');
    expect(h.lines.length, 3);
    expect((h.quantity, h.total, h.avgCost, h.minCost, h.maxCost), (40, 400, 10, 9, 12));
    final a = h.suppliers.first;
    expect((a.supplier!.id, a.count, a.quantity, a.total, a.avgCost, a.lastCost), ('A', 2, 20, 220, 11, 12));
    expect(h.suppliers.last.avgCost, 9);
    expect(PurchaseHistory([], 'p').avgCost, isNull);
  });
}
