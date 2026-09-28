/// GET /dashboard (see md-files/shared/01-api-contract.md, section 13).
/// Manager-only parts are null for reps and the other way round.
class Dashboard {
  Dashboard.fromJson(Map<String, dynamic> j)
    : salesToday = _money(j['sales']['today']),
      salesMonth = _money(j['sales']['month']),
      collectedToday = _num(j['collected']['today']),
      collectedMonth = _num(j['collected']['month']),
      daily = {
        for (final d in j['daily'] as List)
          d['day'] as String: (sales: _num(d['sales']), collected: _num(d['collected'])),
      },
      visitsToday = Map<String, int>.from(j['visits']['today'] as Map),
      visitsMonthCompleted = j['visits']['monthCompleted'] as int,
      visits = [for (final v in j['visits']['list'] as List) Visit.fromJson(v as Map<String, dynamic>)],
      customersTotal = j['customers']['total'] as int,
      pendingApproval = j['customers']['pendingApproval'] as int,
      debt = _num(j['customers']['debt']),
      debtors = j['customers']['debtors'] as int,
      pendingPayments = _num(j['customers']['pendingPayments']),
      topDebtors = [
        for (final c in j['customers']['topDebtors'] as List)
          (name: c['name'] as String, governorate: c['governorate'] as String, debit: _num(c['debit'])),
      ],
      cheques = [
        for (final c in j['cheques'] as List)
          (
            customer: c['customer']?['name'] as String? ?? '—',
            chequeNumber: c['chequeNumber'] as String?,
            amount: _num(c['amount']),
            dueDate: DateTime.parse(c['dueDate'] as String),
            withRep: c['depositStatus'] == 'PENDING',
          ),
      ],
      recentInvoices = [
        for (final i in j['recentInvoices'] as List)
          (
            number: i['invoiceNumber'] as String,
            customer: i['customer']?['name'] as String? ?? '—',
            by: i['createdBy']?['name'] as String? ?? '—',
            total: _num(i['total']),
            remaining: _num(i['remaining']),
            cancelled: i['status'] == 'CANCELLED',
            createdAt: DateTime.parse(i['createdAt'] as String),
          ),
      ],
      cashBox = j['cashBox'] == null ? null : _money(j['cashBox']),
      custody = j['custody'] == null
          ? null
          : (items: j['custody']['items'] as int, quantity: _num(j['custody']['quantity'])),
      treasury = j['treasury'] == null
          ? null
          : (
              total: _num(j['treasury']['total']),
              withReps: _num(j['treasury']['withReps']),
              byMethod: [
                for (final m in j['treasury']['byMethod'] as List)
                  (method: m['method'] as String, total: _num(m['total'])),
              ],
            ),
      stock = j['stock'] == null
          ? null
          : (
              products: j['stock']['products'] as int,
              value: _num(j['stock']['value']),
              lowStock: [
                for (final p in j['stock']['lowStock'] as List)
                  (name: p['name'] as String, quantity: _num(p['quantity']), minQuantity: _num(p['minQuantity'])),
              ],
            ),
      reps = j['reps'] == null
          ? null
          : [
              for (final r in j['reps'] as List)
                (
                  name: r['name'] as String,
                  sales: _num(r['sales']),
                  collected: _num(r['collected']),
                  visitsCompleted: r['visitsCompleted'] as int,
                  cashHeld: _num(r['cashHeld']),
                ),
            ];

  final Money salesToday;
  final Money salesMonth;
  final num collectedToday;
  final num collectedMonth;
  final Map<String, ({num sales, num collected})> daily; // key: YYYY-MM-DD
  final Map<String, int> visitsToday; // by status
  final int visitsMonthCompleted;
  final List<Visit> visits;
  final int customersTotal;
  final int pendingApproval;
  final num debt;
  final int debtors;
  final num pendingPayments;
  final List<({String name, String governorate, num debit})> topDebtors;
  final List<({String customer, String? chequeNumber, num amount, DateTime dueDate, bool withRep})> cheques;
  final List<
    ({String number, String customer, String by, num total, num remaining, bool cancelled, DateTime createdAt})
  >
  recentInvoices;

  // Sales rep
  final Money? cashBox;
  final ({int items, num quantity})? custody;

  // Managers
  final ({num total, num withReps, List<({String method, num total})> byMethod})? treasury;
  final ({int products, num value, List<({String name, num quantity, num minQuantity})> lowStock})? stock;
  final List<({String name, num sales, num collected, int visitsCompleted, num cashHeld})>? reps;

  int get visitsTodayCount =>
      (visitsToday['PLANNED'] ?? 0) + (visitsToday['IN_PROGRESS'] ?? 0) + (visitsToday['COMPLETED'] ?? 0);
  int get visitsLeft => (visitsToday['PLANNED'] ?? 0) + (visitsToday['IN_PROGRESS'] ?? 0);
}

typedef Money = ({num total, int count});

class Visit {
  Visit.fromJson(Map<String, dynamic> j)
    : customer = j['customer']?['name'] as String? ?? '—',
      governorate = j['customer']?['governorate'] as String? ?? '',
      rep = j['salesRep']?['name'] as String? ?? '',
      status = j['status'] as String,
      scheduledAt = DateTime.parse(j['scheduledAt'] as String);

  final String customer;
  final String governorate;
  final String rep;
  final String status;
  final DateTime scheduledAt;
}

const visitStatusLabels = {'PLANNED': 'مخططة', 'IN_PROGRESS': 'جارية', 'COMPLETED': 'مكتملة', 'CANCELLED': 'ملغاة'};

const paymentMethodLabels = {
  'CASH': 'تحصيل نقدي',
  'VODAFONE_CASH': 'فودافون كاش',
  'BANK_TRANSFER': 'تحويل بنكي',
  'CHEQUE': 'شيك',
};

num _num(dynamic v) => v as num? ?? 0;
Money _money(dynamic j) => (total: _num(j['total']), count: j['count'] as int? ?? 0);
