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

Collection _collection(String id, String date, num amount, {bool cancelled = false, bool pending = false}) =>
    Collection.fromJson({
      'id': id,
      'receiptNumber': id,
      'customer': _customer,
      'createdBy': _person,
      'amount': amount,
      'paymentMethod': 'CASH',
      'status': cancelled ? 'CANCELLED' : 'ACTIVE',
      'depositStatus': pending ? 'PENDING' : null,
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

    test('payments still with the rep are not deducted until handed over', () {
      final lines = buildStatement(
        [_invoice('I1', '2026-09-01', 1000, 0)],
        [_collection('C1', '2026-09-03', 300, pending: true)],
      );
      expect([for (final l in lines) (l.number, l.pending, l.balance)], [('C1', true, 1000), ('I1', false, 1000)]);
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
        'debit': 500,
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

    test('paying above the total settles previous debt (minus money still with the rep)', () {
      final m = vm(manager: true)..warehouseId = 'w';
      m.lines.first
        ..productId = 'p2'
        ..quantity = 2; // 100
      // previous debt = 500 - 200 pending = 300, so up to 400 can be paid.
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
}
