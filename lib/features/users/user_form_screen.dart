import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/inventory.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'user_list_screen.dart';

/// New user (managers). OWNER is seed-only; reps get a region and a warehouse.
class UserFormScreen extends StatelessWidget {
  const UserFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مستخدم جديد')),
      body: AsyncView<List<Warehouse>>(
        load: context.app.inventory.warehouses,
        refreshable: false,
        builder: (context, w) =>
            _Form(warehouses: w.where((x) => x.isActive).toList()),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  String _role = 'SALES_REP';
  List<String> _governorates = [];
  String? _warehouse;
  bool _saving = false;
  String? _error;

  bool get _rep => _role == 'SALES_REP';
  bool get _hasWarehouse => _role == 'SALES_REP' || _role == 'WAREHOUSE_REP';

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.users.create({
        'name': _name.text.trim(),
        'username': _username.text.trim().toLowerCase(),
        'role': _role,
        'governorates': _rep ? _governorates : <String>[],
        'warehouse': _hasWarehouse ? _warehouse : null,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.status == 409
            ? 'اسم الدخول مستخدم بالفعل، زوّد عليه حرف أو رقم.'
            : errorMessage(e, 'تعذر إنشاء المستخدم. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Form(
      key: _form,
      child: PageList(
        children: [
          FormCard(
            children: [
              Input(
                label: 'الاسم',
                controller: _name,
                validator: (v) => v.trim().length < 2
                    ? 'الاسم مطلوب (حرفان على الأقل).'
                    : null,
              ),
              Input(
                label: 'اسم الدخول',
                controller: _username,
                hint: 'ayman',
                helper:
                    'كلمة المرور الافتراضية 123456A، والمستخدم هيغيرها أول ما يدخل.',
                keyboard: TextInputType.visiblePassword,
                ltr: true,
                validator: (v) => v.trim().isEmpty
                    ? 'اسم الدخول مطلوب.'
                    : RegExp(r'^[A-Za-z0-9._-]{3,30}$').hasMatch(v.trim())
                    ? null
                    : 'من 3 لـ 30 حرف إنجليزي أو رقم أو . _ - من غير مسافات.',
              ),
              Text(
                'الدور',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
              SegmentedButton<String>(
                segments: [
                  for (final r in ['SALES_REP', 'WAREHOUSE_REP', 'ADMIN'])
                    ButtonSegment(value: r, label: Text(roleLabels[r]!)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
            ],
          ),
          if (_hasWarehouse)
            FormCard(
              title: _rep ? 'المنطقة والمخزن' : 'المخزن',
              children: [
                if (_rep) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showGovernoratePicker(
                        context,
                        title: 'محافظات المندوب',
                        selected: _governorates,
                      );
                      if (picked != null)
                        setState(() => _governorates = picked);
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      _governorates.isEmpty
                          ? 'اختيار المحافظات'
                          : _governorates.join('، '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_governorates.isEmpty)
                    Text(
                      'المندوب بدون محافظات لن يرى أي عميل.',
                      style: TextStyle(color: colors.warningFg, fontSize: 12),
                    ),
                ],
                Select<String?>(
                  label: 'المخزن التابع له',
                  value: _warehouse,
                  items: {
                    null: 'بدون مخزن',
                    for (final w in widget.warehouses) w.id: w.name,
                  },
                  onChanged: (v) => setState(() => _warehouse = v),
                ),
                if (_warehouse == null)
                  Text(
                    _rep
                        ? 'المندوب بدون مخزن لن يستطيع البيع.'
                        : 'مندوب المخزن بدون مخزن لن يقدر يصرف أو يستلم مرتجع.',
                    style: TextStyle(color: colors.warningFg, fontSize: 12),
                  ),
              ],
            ),
          SubmitButton(
            label: 'إنشاء المستخدم',
            loading: _saving,
            onPressed: _submit,
          ),
          if (_error != null) Note(_error!, tone: Tone.danger),
        ],
      ),
    );
  }
}
