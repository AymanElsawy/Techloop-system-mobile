import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/models/common.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'movement_list.dart';

const _statusTones = {
  'PENDING': Tone.warning,
  'ISSUED': Tone.success,
  'REJECTED': Tone.danger,
  'CANCELLED': Tone.neutral,
};

/// طلبات العهدة (a tab of المخزن). A sales rep asks their warehouse for goods and follows their
/// requests; the warehouse rep (their warehouse) and managers (all) issue them or reject them.
class CustodyRequestsView extends StatefulWidget {
  const CustodyRequestsView({super.key});

  @override
  State<CustodyRequestsView> createState() => _CustodyRequestsViewState();
}

class _CustodyRequestsViewState extends State<CustodyRequestsView> {
  late final bool _rep = context.user.role == UserRole.salesRep;

  /// Handlers start on what needs their action; a rep on everything they asked for.
  late String? _status = _rep ? null : 'PENDING';
  final _ctl = AsyncController<List<CustodyRequest>>();

  Future<void> _open(Widget screen) async {
    final changed = await push<bool>(context, screen);
    if (changed == true) _ctl.reload();
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    try {
      await action();
      _ctl.reload();
    } catch (e) {
      if (mounted) toast(context, errorMessage(e, fallback));
    }
  }

  Future<void> _reject(CustodyRequest r) async {
    final reason = await askReason(
      context,
      title: 'رفض طلب العهدة ${r.number}',
      message: 'المندوب هيجيله إشعار بالسبب.',
    );
    if (reason == null || !mounted) return;
    final inv = context.app.inventory;
    await _run(() => inv.rejectCustodyRequest(r.id, reason), 'تعذر رفض الطلب.');
  }

  Future<void> _cancel(CustodyRequest r) async {
    if (!await confirm(
          context,
          'إلغاء الطلب',
          'هتلغي طلب العهدة ${r.number}؟',
        ) ||
        !mounted) {
      return;
    }
    final inv = context.app.inventory;
    await _run(() => inv.cancelCustodyRequest(r.id), 'تعذر إلغاء الطلب.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _rep
          ? FloatingActionButton.extended(
              onPressed: () => _open(const CustodyRequestFormScreen()),
              icon: const Icon(Icons.add),
              label: const Text('طلب عهدة'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ChoiceBar<String?>(
              options: {null: 'الكل', ...custodyRequestStatusLabels},
              value: _status,
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          Expanded(
            child: AsyncView<List<CustodyRequest>>(
              key: ValueKey(_status),
              controller: _ctl,
              load: () =>
                  context.app.inventory.custodyRequests(status: _status),
              errorText: 'حدث خطأ أثناء تحميل الطلبات.',
              builder: (context, list) => PageList(
                bottomPadding: 96, // room for the button
                children: [
                  if (list.isEmpty)
                    EmptyCard(_rep ? 'مفيش طلبات لسه.' : 'مفيش طلبات هنا.'),
                  for (final r in list)
                    _RequestCard(
                      r: r,
                      rep: _rep,
                      onIssue: () =>
                          _open(IssueCustodyRequestScreen(request: r)),
                      onReject: () => _reject(r),
                      onCancel: () => _cancel(r),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.r,
    required this.rep,
    required this.onIssue,
    required this.onReject,
    required this.onCancel,
  });

  final CustodyRequest r;
  final bool rep;
  final VoidCallback onIssue;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SectionCard(
      title: 'طلب عهدة ${r.number}',
      trailing: StatusBadge(
        custodyRequestStatusLabels[r.status] ?? r.status,
        tone: _statusTones[r.status] ?? Tone.neutral,
      ),
      children: [
        _pad(
          Text(
            [
              if (!rep) r.rep.name,
              warehouseLabel(r.warehouse.name),
              dateTime(r.createdAt),
            ].dotted(),
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ),
        for (final i in r.items)
          Tile(title: i.name, trailing: number(i.quantity)),
        if (r.notes != null) _pad(Text('ملاحظات: ${r.notes}')),
        if (r.status == 'ISSUED' && r.movement != null)
          Tile(
            title: 'إذن صرف ${r.movement!.number}',
            subtitle: 'صرفه ${r.handledBy?.name ?? '—'}',
            onTap: () =>
                push(context, MovementDetailsScreen(id: r.movement!.id)),
          ),
        if (r.status == 'REJECTED')
          _pad(
            Text(
              'رفضه ${r.handledBy?.name ?? '—'}: ${r.reason ?? ''}',
              style: TextStyle(color: colors.dangerFg),
            ),
          ),
        if (r.pending)
          _pad(
            rep
                ? OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('إلغاء الطلب'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: onIssue,
                          child: const Text('صرف للمندوب'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onReject,
                          child: const Text('رفض'),
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  /// [SectionCard] rows carry their own padding (like [Tile]); plain rows get the same.
  static Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: child,
  );
}

class _Line {
  String? productId;
  final qty = TextEditingController(text: '1');
}

/// Sales rep: a new request, from the products in their warehouse (with what's available now).
class CustodyRequestFormScreen extends StatelessWidget {
  const CustodyRequestFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب عهدة')),
      body: AsyncView<MyStock>(
        refreshable: false,
        load: context.app.inventory.myStock,
        errorText: 'حدث خطأ أثناء تحميل المخزن.',
        builder: (context, s) => _RequestForm(stock: s),
      ),
    );
  }
}

class _RequestForm extends StatefulWidget {
  const _RequestForm({required this.stock});

  final MyStock stock;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _lines = [_Line()];
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  int _qty(_Line l) => int.tryParse(l.qty.text) ?? 0;
  bool get _canSubmit =>
      _lines.every((l) => l.productId != null && _qty(l) >= 1);

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.createCustodyRequest([
        for (final l in _lines) {'productId': l.productId, 'quantity': _qty(l)},
      ], _notes.text.trim().isEmpty ? null : _notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e, 'تعذر إرسال الطلب.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stock;
    final colors = context.colors;
    if (s.warehouse == null) {
      return const PageList(
        children: [Note('لم يتم ربطك بمخزن بعد. تواصل مع الإدارة.')],
      );
    }
    if (s.warehouseStock.isEmpty) {
      return PageList(
        children: [
          EmptyCard('${warehouseLabel(s.warehouse!.name)} فاضي دلوقتي.'),
        ],
      );
    }
    return PageList(
      children: [
        Text(
          'من ${warehouseLabel(s.warehouse!.name)}. مندوب المخزن هيصرف الطلب أو يعدّل الكميات.',
          style: TextStyle(color: colors.muted),
        ),
        FormCard(
          title: 'الأصناف',
          children: [
            for (final (i, l) in _lines.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Select<String>(
                      label: 'الصنف',
                      value: l.productId,
                      hint: 'اختر الصنف',
                      // Products already chosen in other lines are hidden.
                      items: {
                        for (final r in s.warehouseStock)
                          if (r.productId == l.productId ||
                              !_lines.any((x) => x.productId == r.productId))
                            r.productId:
                                '${r.label} — المتاح ${number(r.quantity)}',
                      },
                      onChanged: (v) => setState(() => l.productId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Input(
                      label: 'الكمية',
                      controller: l.qty,
                      keyboard: TextInputType.number,
                      ltr: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_lines.length > 1)
                    IconButton(
                      tooltip: 'حذف السطر ${i + 1}',
                      onPressed: () => setState(() => _lines.removeAt(i)),
                      icon: Icon(Icons.delete_outline, color: colors.danger),
                    ),
                ],
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ),
          ],
        ),
        FormCard(
          children: [
            Input(
              label: 'ملاحظات',
              controller: _notes,
              hint: 'مثلاً: لزيارات بكرة',
            ),
          ],
        ),
        SubmitButton(
          label: 'إرسال الطلب',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}

/// Warehouse rep / manager: issue a request to the rep's custody. The quantities start at what was
/// asked (capped at what's in the warehouse) and can be lowered; 0 drops the line.
class IssueCustodyRequestScreen extends StatelessWidget {
  const IssueCustodyRequestScreen({super.key, required this.request});

  final CustodyRequest request;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('صرف طلب العهدة ${request.number}')),
      body: AsyncView<WarehouseDetails>(
        refreshable: false,
        load: () => context.app.inventory.warehouse(request.warehouse.id),
        errorText: 'حدث خطأ أثناء تحميل المخزن.',
        builder: (context, d) => _IssueForm(request: request, details: d),
      ),
    );
  }
}

class _IssueForm extends StatefulWidget {
  const _IssueForm({required this.request, required this.details});

  final CustodyRequest request;
  final WarehouseDetails details;

  @override
  State<_IssueForm> createState() => _IssueFormState();
}

class _IssueFormState extends State<_IssueForm> {
  late final _available = {
    for (final s in widget.details.stock) s.productId: s.quantity,
  };
  late final _qty = {
    for (final i in widget.request.items)
      i.productId: TextEditingController(
        text:
            '${i.quantity < (_available[i.productId] ?? 0) ? i.quantity : (_available[i.productId] ?? 0)}',
      ),
  };
  bool _saving = false;
  String? _error;

  int _q(String productId) => int.tryParse(_qty[productId]!.text) ?? 0;
  List<Map<String, Object>> get _items => [
    for (final i in widget.request.items)
      if (_q(i.productId) > 0)
        {'productId': i.productId, 'quantity': _q(i.productId)},
  ];
  bool get _canSubmit =>
      _items.isNotEmpty &&
      widget.request.items.every(
        (i) => _q(i.productId) <= (_available[i.productId] ?? 0),
      );

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.issueCustodyRequest(
        widget.request.id,
        _items,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e, 'تعذر الصرف.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final colors = context.colors;
    return PageList(
      children: [
        Text(
          '${r.rep.name} · ${warehouseLabel(r.warehouse.name)}${r.notes == null ? '' : '\nملاحظات: ${r.notes}'}',
          style: TextStyle(color: colors.muted),
        ),
        FormCard(
          title: 'الكميات اللي هتتصرف',
          children: [
            for (final i in r.items) ...[
              Text(i.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Row(
                children: [
                  Expanded(
                    child: Input(
                      label: 'هيتصرف',
                      controller: _qty[i.productId]!,
                      keyboard: TextInputType.number,
                      ltr: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'المطلوب ${number(i.quantity)} · المتاح ${number(_available[i.productId] ?? 0)}',
                    style: TextStyle(
                      color: _q(i.productId) > (_available[i.productId] ?? 0)
                          ? colors.danger
                          : colors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            Text(
              'اكتب 0 عشان تشيل صنف من الصرف.',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
        SubmitButton(
          label: 'صرف للمندوب',
          loading: _saving,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
