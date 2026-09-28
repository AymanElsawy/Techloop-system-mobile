import 'package:flutter_test/flutter_test.dart';
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
      ],
    });
    expect(d.treasury!.byMethod.single.method, 'CASH');
    expect(d.reps!.single.name, 'أحمد');
    expect(d.cashBox, isNull);
  });
}
