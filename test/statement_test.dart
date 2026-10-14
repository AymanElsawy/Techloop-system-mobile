import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:techloop_mobile/data/models/common.dart';
import 'package:techloop_mobile/data/models/report.dart';
import 'package:techloop_mobile/features/reports/party_report_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar_EG'));

  test('statementDoc: opening row, a row per line, totals and closing', () {
    final r = PartyReport.fromJson({
      'customer': {
        'id': 'c',
        'name': 'عيادة',
        'governorate': 'الجيزة',
        'phone': '010',
        'balance': 150,
      },
      'opening': 100,
      'closing': 150,
      'totals': {
        'invoices': 1,
        'net': 200,
        'returns': 0,
        'profit': 50,
        'collected': 150,
      },
      'products': [],
      'lines': [
        {
          'kind': 'invoice',
          'id': '1',
          'number': 'A-1',
          'date': '2026-09-01T10:00:00Z',
          'debit': 200,
          'credit': 0,
          'method': null,
          'bounced': false,
          'pending': false,
          'balance': 300,
        },
        {
          'kind': 'collection',
          'id': '2',
          'number': 'R-1',
          'date': '2026-09-02T10:00:00Z',
          'debit': 0,
          'credit': 150,
          'method': 'CHEQUE',
          'bounced': false,
          'pending': true,
          'balance': 150,
        },
      ],
    }, customers: true);
    final doc = statementDoc(
      r,
      const Ref('c', 'عيادة'),
      DateTime(2026, 9),
      DateTime(2026, 9, 30),
    );

    expect(doc.rows.length, 3); // opening + 2 lines
    expect(doc.rows.first[1], 'رصيد أول المدة');
    expect(doc.rows[1][5], 'آجل');
    expect(
      doc.rows[2][5],
      'شيك',
    ); // rep-held money is just paid for the customer
    expect(doc.partyLines, ['عيادة', 'الجيزة', '010']);
    expect(doc.totals.last.$1, contains('مستحق على العميل'));
    expect(
      doc.totals.map((t) => t.$1).join(),
      isNot(contains('ربح')),
    ); // no profit on the customer's copy
  });

  test(
    'statementDoc for a supplier: supplier labels, owed to the supplier',
    () {
      final r = PartyReport.fromJson({
        'supplier': {'id': 's', 'name': 'مورد', 'phone': '011', 'debt': 500},
        'opening': 0,
        'closing': 500,
        'totals': {'receipts': 1, 'purchases': 800, 'paid': 300},
        'products': [],
        'lines': [
          {
            'kind': 'receipt',
            'id': '1',
            'number': '7',
            'date': '2026-09-01T10:00:00Z',
            'debit': 800,
            'credit': 300,
            'method': null,
            'bounced': false,
            'pending': false,
            'balance': 500,
          },
        ],
      }, customers: false);
      final doc = statementDoc(
        r,
        const Ref('s', 'مورد'),
        DateTime(2026, 9),
        DateTime(2026, 9, 30),
        customers: false,
      );

      expect(doc.partyLabel, 'المورد');
      expect(doc.partyLines, ['مورد', '011']);
      expect(doc.rows[1][1], 'توريد 7');
      expect(doc.rows[1][5], ''); // a receipt isn't "deferred"
      expect(doc.totals.last.$1, contains('مستحق للمورد'));
      expect(doc.signatures.$1, 'توقيع المورد');
    },
  );
}
