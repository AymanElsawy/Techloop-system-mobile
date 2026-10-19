import 'package:flutter_test/flutter_test.dart';
import 'package:techloop_mobile/data/models/treasury.dart';

void main() {
  test('ledger page reads rows and the period totals from meta', () {
    final page = LedgerPage.fromJson({
      'data': [
        {
          'date': '2026-10-07T13:25:00.000Z',
          'title': 'استلام #58',
          'party': 'أحمد سمير',
          'method': 'CASH',
          'amount': 20216.35,
          'balance': 427690.19,
          'ref': {'type': 'DEPOSIT', 'id': 'd1'},
        },
        {
          'date': '2026-10-03T00:21:00.000Z',
          'title': 'تسوية جرد #4',
          'party': null,
          'method': 'CASH',
          'amount': -50,
          'balance': 750,
          'ref': null,
        },
      ],
      'meta': {
        'page': 1,
        'limit': 20,
        'total': 2,
        'opening': 100,
        'inflow': 20216.35,
        'outflow': 50,
        'closing': 20266.35,
      },
    });
    expect(page.total, 2);
    expect(page.items.first.refType, 'DEPOSIT');
    expect(page.items.last.amount, -50);
    expect(page.items.last.refId, isNull);
    expect(page.opening, 100);
    expect(page.closing, 20266.35);
  });

  test('a count entry keeps what was counted', () {
    final e = TreasuryEntry.fromJson({
      'id': 'e1',
      'number': 4,
      'type': 'ADJUSTMENT',
      'amount': -50,
      'counted': 750,
      'paymentMethod': 'CASH',
      'status': 'ACTIVE',
      'createdBy': {'id': 'u1', 'name': 'owner'},
      'createdAt': '2026-10-19T08:00:00.000Z',
    });
    expect(entryTypeLabels[e.type], 'تسوية جرد');
    expect(e.counted, 750);
  });
}
