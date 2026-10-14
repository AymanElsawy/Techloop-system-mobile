import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'customer_details_screen.dart';
import 'customer_form_screen.dart';

/// العملاء: search, governorate filter, status filter (managers) and the pending-approval shortcut.
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _search = TextEditingController();
  final _list = PagedController();
  Timer? _debounce;
  String _query = '';
  String? _governorate;
  String? _status;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPending() async {
    if (!context.isManager) return;
    try {
      final page = await context.app.customers.page(
        1,
        limit: 1,
        status: 'PENDING',
      );
      if (mounted) setState(() => _pending = page.total);
    } catch (_) {} // the shortcut is optional
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _query = v.trim()),
    );
  }

  bool get _hasFilters =>
      _query.isNotEmpty || _governorate != null || _status != null;

  Future<void> _open(Widget screen) async {
    await push(context, screen);
    _list.reload();
    _loadPending();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.user;
    final manager = user.isManager;
    // Reps filter within their own region only.
    final regions = manager ? governorates : user.governorates;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const CustomerFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('عميل جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!manager && regions.isEmpty) ...[
                  const Note(
                    'لم يتم تحديد منطقة (محافظات) لك بعد، لذلك لا يظهر أي عميل. تواصل مع الإدارة.',
                  ),
                  const SizedBox(height: 10),
                ] else if (!manager) ...[
                  Text(
                    'منطقتك: ${regions.join('، ')}',
                    style: TextStyle(color: context.colors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _onSearch,
                        decoration: const InputDecoration(
                          hintText: 'بحث بالاسم أو الهاتف',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      child: Select<String?>(
                        label: 'المحافظة',
                        value: _governorate,
                        items: {null: 'الكل', for (final g in regions) g: g},
                        onChanged: (v) => setState(() => _governorate = v),
                      ),
                    ),
                  ],
                ),
                if (manager) ...[
                  const SizedBox(height: 8),
                  ChoiceBar<String?>(
                    options: {
                      null: 'كل الحالات',
                      'PENDING':
                          'بانتظار الموافقة${_pending > 0 ? ' ($_pending)' : ''}',
                      'APPROVED': 'معتمد',
                      'REJECTED': 'مرفوض',
                    },
                    value: _status,
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: PagedListView<Customer>(
              key: ValueKey((_query, _governorate, _status)),
              controller: _list,
              load: (page) => context.app.customers.page(
                page,
                governorate: _governorate,
                status: _status,
                search: _query,
              ),
              errorText: 'حدث خطأ أثناء تحميل العملاء.',
              emptyText: _hasFilters
                  ? 'لا يوجد عملاء مطابقون للبحث.'
                  : 'لا يوجد عملاء بعد.',
              itemBuilder: (context, c) => _CustomerCard(
                customer: c,
                onTap: () => _open(CustomerDetailsScreen(id: c.id)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Tile(
        title: c.name,
        subtitle: [c.place, if (c.phone != null) c.phone!].dotted(),
        badge: c.status == 'APPROVED'
            ? null
            : StatusBadge(
                customerStatusLabels[c.status]!,
                tone: statusTones[c.status]!,
              ),
        trailing: money(c.debit),
        trailingColor: c.debit > 0 ? context.colors.danger : null,
        trailingHint: c.credit > 0 ? 'دائن ${money(c.credit)}' : 'مدين',
        onTap: onTap,
      ),
    );
  }
}
