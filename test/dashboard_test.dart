import 'package:flutter_test/flutter_test.dart';
import 'package:techloop_mobile/data/models/treasury.dart';
import 'package:techloop_mobile/features/dashboard/dashboard.dart';

Map<String, dynamic> _base() => {
  'sales': {
    'today': {'total': 200, 'count': 1},
    'month': {'total': 5400.5, 'count': 4},
  },
  'collected': {'today': 0, 'month': 5200},
  'daily': [
    {'day': '2026-09-24', 'sales': 5000, 'collected': 1322},
  ],
  'visits': {
    'today': {'PLANNED': 2, 'IN_PROGRESS': 1, 'COMPLETED': 3, 'CANCELLED': 4},
    'monthCompleted': 9,
    'list': [],
  },
  'customers': {'total': 1, 'pendingApproval': 0, 'debt': 100, 'debtors': 1, 'pendingPayments': 0, 'topDebtors': []},
  'cheques': [],
  'recentInvoices': [],
};

void main() {
  test('parses a rep dashboard: no manager parts, cancelled visits not counted', () {
    final d = Dashboard.fromJson({
      ..._base(),
      'cashBox': {'total': 50, 'count': 2},
      'custody': {'items': 1, 'quantity': 3},
    });
    expect(d.salesMonth.total, 5400.5);
    expect(d.daily['2026-09-24']!.collected, 1322);
    expect(d.visitsTodayCount, 6);
    expect(d.visitsLeft, 3);
    expect(d.cashBox!.count, 2);
    expect(d.treasury, isNull);
    expect(d.reps, isNull);
  });

  test('parses manager parts', () {
    final d = Dashboard.fromJson({
      ..._base(),
      'treasury': {
        'total': 5200,
        'withReps': 0,
        'byMethod': [
          {'method': 'CASH', 'total': 1222, 'count': 1},
        ],
      },
      'stock': {'products': 2, 'value': 0, 'lowStock': []},
      'reps': [
        {'name': 'أحمد', 'sales': 200, 'collected': 0, 'visitsCompleted': 0, 'cashHeld': 0},
        {
          'name': 'Mika',
          'sales': 500,
          'collected': 100,
          'visitsCompleted': 1,
          'cashHeld': 0,
          'salesProgress': 50,
          'collectionProgress': null,
          'commission': 12.5,
        },
      ],
    });
    expect(d.treasury!.byMethod.single.method, 'CASH');
    expect(d.reps!.first.name, 'أحمد');
    expect(d.reps!.first.salesProgress, isNull); // older API without targets
    expect(d.reps!.last.salesProgress, 50);
    expect(d.reps!.last.commission, 12.5);
    expect(d.cashBox, isNull);
  });

  test('parses a target row: no target = null progress', () {
    final r = TargetRow.fromJson({
      'id': '1',
      'name': 'Mika',
      'isActive': true,
      'salesTarget': 10000,
      'collectionTarget': null,
      'salesCommissionRate': 2.5,
      'collectionCommissionRate': 0,
      'returns': 100,
      'netSales': 6584,
      'collected': 1333,
      'salesProgress': 66,
      'collectionProgress': null,
      'commission': 164.6,
    });
    expect(r.salesProgress, 66);
    expect(r.collectionTarget, isNull);
    expect(r.collectionProgress, isNull);
    expect(r.commission, 164.6);
  });

  test('parses a rep report: returns keep their invoice, bounced cheques are flagged', () {
    final d = RepTargetReport.fromJson({
      'rep': {'id': '1', 'name': 'Mika', 'sales': 200, 'returns': 100, 'netSales': 100, 'collected': 2500},
      'invoices': [
        {
          'id': 'i1',
          'invoiceNumber': '12333',
          'customer': {'name': 'Ayman'},
          'total': 200,
          'paidAmount': 0,
          'paymentMethod': null,
          'chequeStatus': null,
          'createdAt': '2026-09-27T09:50:31.995Z',
        },
      ],
      'returns': [
        {
          'id': 'r1',
          'number': 1,
          'invoice': {'invoiceNumber': '12333'},
          'customer': {'name': 'Ayman'},
          'total': 100,
          'createdAt': '2026-09-27T12:55:37.731Z',
        },
      ],
      'collections': [
        {
          'id': 'c1',
          'receiptNumber': '665576',
          'customer': {'name': 'Ayman'},
          'amount': 2500,
          'paymentMethod': 'CHEQUE',
          'chequeStatus': 'BOUNCED',
          'createdAt': '2026-09-28T15:08:25.398Z',
        },
      ],
      'visits': [
        {
          'id': 'v1',
          'customer': {'name': 'Ayman'},
          'purpose': 'SALE',
          'status': 'COMPLETED',
          'scheduledAt': '2026-09-27T09:00:00.000Z',
        },
      ],
      'expenses': [
        {'amount': 50, 'category': 'بنزين', 'notes': null, 'depositStatus': 'PENDING', 'createdAt': '2026-09-27T10:00:00.000Z'},
      ],
      'warehouse': {'id': 'w1', 'name': 'مخزن القاهرة'},
      'custody': [
        {'quantity': 2, 'product': {'name': 'دواء', 'unit': 'LITER', 'price': 100}},
      ],
      'cashBox': {'total': 2450, 'cash': 0, 'expenses': 50, 'count': 1},
      'governorates': ['القاهرة'],
    });
    expect(d.rep.sales, 200);
    expect(d.invoices.single.id, 'i1');
    expect(d.visits.single.status, 'COMPLETED');
    expect(d.expenses.single.pending, isTrue);
    expect(d.custody.single.value, 200);
    expect((d.warehouse, d.cashTotal), ('مخزن القاهرة', 2450));
    expect(d.invoices.single.paid, 0);
    expect(d.returns.single.detail, '12333');
    expect(d.collections.single.detail, contains('مرتد'));
  });

  test('target period: month / year query, never past the current month', () {
    final now = DateTime.now();
    final month = TargetPeriod(DateTime(2026, 8));
    expect(month.query, {'month': '2026-08'});
    expect(month.withYearly(true).query, {'year': '2026'});
    expect(month.shift(-8).key, '2025-12');
    final current = TargetPeriod.thisMonth();
    expect(current.isCurrent, isTrue);
    expect(current.shift(1).key, current.key);
    expect(TargetPeriod(DateTime(now.year - 1, 12), yearly: true).shift(1).month, DateTime(now.year, now.month));
  });
}
