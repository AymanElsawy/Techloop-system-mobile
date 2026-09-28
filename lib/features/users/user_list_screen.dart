import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/ui.dart';
import 'user_form_screen.dart';

typedef _Data = ({List<ManagedUser> users, List<Warehouse> warehouses});

/// المستخدمون (managers): region (governorates) and warehouse of each rep, set password.
class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _ctl = AsyncController<_Data>();

  Future<_Data> _load() async {
    final (u, w) = await (context.app.users.list(), context.app.inventory.warehouses()).wait;
    return (users: u, warehouses: w);
  }

  /// Runs an update and shows the result; the backend refuses a warehouse change while the rep holds custody.
  Future<void> _update(ManagedUser user, Json data, String done) async {
    try {
      await context.app.users.update(user.id, data);
      if (!mounted) return;
      toast(context, done);
      _ctl.reload();
    } catch (e) {
      if (!mounted) return;
      toast(
        context,
        e is ApiException && e.serverMessage.contains('custody')
            ? '${user.name} معه بضاعة في عهدته. سجّل المرتجع أولاً ثم غيّر المخزن.'
            : errorMessage(e, 'تعذر الحفظ.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await push<bool>(context, const UserFormScreen());
          if (created == true) _ctl.reload();
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('مستخدم جديد'),
      ),
      body: AsyncView<_Data>(
        controller: _ctl,
        load: _load,
        errorText: 'حدث خطأ أثناء تحميل المستخدمين.',
        builder: (context, d) => d.users.isEmpty
            ? const PageList(children: [EmptyCard('لا يوجد مستخدمون.')])
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: d.users.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _UserCard(user: d.users[i], warehouses: d.warehouses, onUpdate: _update),
              ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.warehouses, required this.onUpdate});

  final ManagedUser user;
  final List<Warehouse> warehouses;
  final Future<void> Function(ManagedUser, Json, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final colors = context.colors;
    final small = TextStyle(fontSize: 12.5, color: colors.muted);
    final warehouse = warehouses.where((w) => w.id == u.warehouse).firstOrNull;
    // Only an owner may change an owner's password (the backend checks too).
    final canSetPassword = u.role != 'OWNER' || context.user.role == UserRole.owner;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(u.email, style: small, textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                StatusBadge(u.isActive ? 'نشط' : 'موقوف', tone: u.isActive ? Tone.success : Tone.danger),
                PopupMenuButton<String>(
                  tooltip: 'إجراءات ${u.name}',
                  onSelected: (v) async {
                    if (v == 'region') {
                      final picked = await showGovernoratePicker(
                        context,
                        title: 'محافظات ${u.name}',
                        selected: u.governorates,
                      );
                      if (picked != null) onUpdate(u, {'governorates': picked}, 'تم تحديث محافظات ${u.name}.');
                    } else if (v == 'warehouse') {
                      final picked = await _pickWarehouse(context);
                      if (picked != null) {
                        onUpdate(u, {'warehouse': picked.isEmpty ? null : picked}, 'تم تحديث مخزن ${u.name}.');
                      }
                    } else {
                      final pw = await _askPassword(context, u.name);
                      if (pw != null) onUpdate(u, {'password': pw}, 'تم تعيين كلمة مرور جديدة لـ ${u.name}.');
                    }
                  },
                  itemBuilder: (_) => [
                    if (u.isRep) const PopupMenuItem(value: 'region', child: Text('المحافظات')),
                    if (u.isRep) const PopupMenuItem(value: 'warehouse', child: Text('المخزن')),
                    if (canSetPassword) const PopupMenuItem(value: 'password', child: Text('تعيين كلمة مرور')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(roleLabels[u.role] ?? u.role, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (u.isRep) ...[
              Text(
                u.governorates.isEmpty ? 'المنطقة: غير محددة' : 'المنطقة: ${u.governorates.join('، ')}',
                style: TextStyle(fontSize: 12.5, color: u.governorates.isEmpty ? colors.warningFg : colors.muted),
              ),
              Text(
                'المخزن: ${warehouse?.name ?? 'بدون مخزن'}',
                style: TextStyle(fontSize: 12.5, color: warehouse == null ? colors.warningFg : colors.muted),
              ),
            ] else
              Text('كل المحافظات', style: small),
            Text('آخر دخول: ${u.lastLoginAt == null ? '—' : dateTime(u.lastLoginAt!)}', style: small),
          ],
        ),
      ),
    );
  }

  /// '' = no warehouse.
  Future<String?> _pickWarehouse(BuildContext context) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          RadioGroup<String>(
            groupValue: user.warehouse ?? '',
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              children: [
                const RadioListTile(value: '', title: Text('بدون مخزن')),
                for (final w in warehouses.where((w) => w.isActive)) RadioListTile(value: w.id, title: Text(w.name)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<String?> _askPassword(BuildContext context, String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('كلمة مرور جديدة لـ $name'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'كلمة المرور', helperText: '8 أحرف على الأقل'),
            onChanged: (_) => setState(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: controller.text.length >= 8 ? () => Navigator.pop(context, controller.text) : null,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox list of the 27 governorates + select all. Returns the new selection, or null.
Future<List<String>?> showGovernoratePicker(
  BuildContext context, {
  required String title,
  required List<String> selected,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => GovernoratePicker(title: title, initial: selected),
);

class GovernoratePicker extends StatefulWidget {
  const GovernoratePicker({super.key, required this.title, required this.initial});

  final String title;
  final List<String> initial;

  @override
  State<GovernoratePicker> createState() => _GovernoratePickerState();
}

class _GovernoratePickerState extends State<GovernoratePicker> {
  late final _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final all = _selected.length == governorates.length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            ListTile(
              title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${_selected.length} محافظة'),
              trailing: TextButton(
                onPressed: () => setState(() => all ? _selected.clear() : _selected.addAll(governorates)),
                child: Text(all ? 'إلغاء الكل' : 'تحديد الكل'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final g in governorates)
                    CheckboxListTile(
                      value: _selected.contains(g),
                      title: Text(g),
                      onChanged: (v) => setState(() => v! ? _selected.add(g) : _selected.remove(g)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // Keep the official order.
                  onPressed: () => Navigator.pop(context, [
                    for (final g in governorates)
                      if (_selected.contains(g)) g,
                  ]),
                  child: const Text('حفظ المحافظات'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
