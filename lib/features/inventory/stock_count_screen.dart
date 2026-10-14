import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

typedef _Data = ({WarehouseDetails details, List<Product> products});

class _Line {
  _Line(this.productId, this.name, this.system)
    : counted = TextEditingController(text: '$system');
  final String productId;
  final String name;
  final num system;
  final TextEditingController counted;
  int get value => int.tryParse(counted.text) ?? 0;
  int get diff => value - system.toInt();
}

/// جرد (managers): every product in the warehouse with its system quantity; the manager types the counted one
/// and only the differences are saved, with a reason. Pops `true` when saved.
class StockCountScreen extends StatelessWidget {
  const StockCountScreen({super.key, required this.warehouseId});

  final String warehouseId;

  @override
  Widget build(BuildContext context) {
    final inv = context.app.inventory;
    return Scaffold(
      appBar: AppBar(title: const Text('جرد المخزن')),
      body: AsyncView<_Data>(
        refreshable: false,
        load: () async {
          final (d, p) = await (
            inv.warehouse(warehouseId),
            inv.products(active: true),
          ).wait;
          return (details: d, products: p);
        },
        builder: (context, d) => _Form(warehouseId: warehouseId, data: d),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.warehouseId, required this.data});

  final String warehouseId;
  final _Data data;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final _lines = [
    for (final s in widget.data.details.stock)
      _Line(s.productId, s.label, s.quantity),
  ];
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  List<_Line> get _changed => _lines.where((l) => l.diff != 0).toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.app.inventory.adjust(widget.warehouseId, [
        for (final l in _changed)
          {'productId': l.productId, 'counted': l.value},
      ], _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorMessage(
          e,
          'تعذر حفظ التسوية. الرصيد اتغير، ارجع وافتح الجرد تاني.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final listed = {for (final l in _lines) l.productId};
    final missing = {
      for (final p in widget.data.products)
        if (!listed.contains(p.id)) p.id: p.label,
    };
    return PageList(
      children: [
        Text(
          'اكتب الكمية الفعلية اللي اتعدّت في ${widget.data.details.warehouse.name}. الفرق (عجز أو زيادة) بيتسجل "تسوية جرد".',
          style: TextStyle(color: colors.muted),
        ),
        SectionCard(
          title: 'الأصناف',
          empty: 'المخزن فاضي. ضيف صنف لو لقيته فيه.',
          children: [
            for (final l in _lines)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'في السيستم ${number(l.system)}${l.diff == 0 ? '' : ' · الفرق ${l.diff > 0 ? '+' : ''}${l.diff}'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: l.diff < 0
                                  ? colors.danger
                                  : l.diff > 0
                                  ? colors.successFg
                                  : colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: l.counted,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'الفعلي',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (missing.isNotEmpty)
          Select<String>(
            label: 'صنف مش ظاهر (رصيده صفر)',
            value: null,
            items: missing,
            onChanged: (id) {
              final p = widget.data.products.firstWhere((p) => p.id == id);
              setState(() => _lines.add(_Line(p.id, p.label, 0)));
            },
          ),
        FormCard(
          children: [
            Input(
              label: 'السبب *',
              controller: _reason,
              hint: 'مثلًا: جرد آخر الشهر، كسر، تالف',
              onChanged: (_) => setState(() {}),
            ),
            Text(
              '${_changed.length} صنف فيه فرق.',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ],
        ),
        SubmitButton(
          label: 'حفظ التسوية',
          loading: _saving,
          onPressed: _changed.isEmpty || _reason.text.trim().length < 3
              ? null
              : _save,
        ),
        if (_error != null) Note(_error!, tone: Tone.danger),
      ],
    );
  }
}
