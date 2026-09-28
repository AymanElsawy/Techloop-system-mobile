import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/inventory.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import '../documents/document_pdf_screen.dart';
import '../sales/invoice_details_screen.dart';
import '../suppliers/supplier_details_screen.dart';

const _typeTones = {
  'RECEIVE': Tone.success,
  'ISSUE': Tone.warning,
  'RETURN': Tone.info,
  'SALE': Tone.danger,
  'SALE_CANCEL': Tone.neutral,
  'SALE_RETURN': Tone.info,
  'SALE_RETURN_CANCEL': Tone.neutral,
};

/// Stock log with filters. Reps only get their own custody movements (backend rule).
class MovementList extends StatefulWidget {
  const MovementList({super.key, this.warehouseId, this.repId});

  final String? warehouseId;
  final String? repId;

  @override
  State<MovementList> createState() => _MovementListState();
}

class _MovementListState extends State<MovementList> {
  late String? _warehouse = widget.warehouseId;
  late String? _rep = widget.repId;
  String? _type;
  Map<String, String> _warehouses = {};

  @override
  void initState() {
    super.initState();
    if (context.isManager) {
      context.app.inventory.warehouses().then((list) {
        if (mounted) setState(() => _warehouses = {for (final w in list) w.id: w.name});
      }, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.isManager;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              if (manager) ...[
                Expanded(
                  child: Select<String?>(
                    label: 'المخزن',
                    value: _warehouse,
                    items: {null: 'كل المخازن', ..._warehouses},
                    onChanged: (v) => setState(() => _warehouse = v),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Select<String?>(
                  label: 'نوع الحركة',
                  value: _type,
                  items: {null: 'كل الحركات', ...movementTypeLabels},
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
            ],
          ),
        ),
        if (manager && _rep != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InputChip(label: const Text('حركات مندوب واحد'), onDeleted: () => setState(() => _rep = null)),
          ),
        Expanded(
          child: AsyncView<List<Movement>>(
            key: ValueKey((_warehouse, _rep, _type)),
            load: () => context.app.inventory.movements(warehouseId: _warehouse, repId: _rep, type: _type),
            errorText: 'حدث خطأ أثناء تحميل الحركات.',
            builder: (context, list) => list.isEmpty
                ? const PageList(children: [EmptyCard('لا توجد حركات.')])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => MovementCard(movement: list[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class MovementCard extends StatelessWidget {
  const MovementCard({super.key, required this.movement});

  final Movement movement;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final colors = context.colors;
    final manager = context.isManager;
    final small = TextStyle(fontSize: 12, color: colors.muted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(movementTypeLabels[m.type] ?? m.type, tone: _typeTones[m.type] ?? Tone.neutral),
                const Spacer(),
                Text(dateTime(m.createdAt), style: small),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [m.warehouse?.name ?? '—', ?m.rep?.name].dotted(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final i in m.items)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${i.name}: '),
                    TextSpan(
                      text: number(i.quantity),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (manager && i.unitCost != null) TextSpan(text: ' × ${money(i.unitCost!)}', style: small),
                    if (i.fromCustody > 0 && i.fromCustody < i.quantity)
                      TextSpan(
                        text: ' (${number(i.fromCustody)} عهدة + ${number(i.quantity - i.fromCustody)} مخزن)',
                        style: small,
                      )
                    else if (i.fromCustody > 0)
                      TextSpan(text: ' (من العهدة)', style: small),
                  ],
                ),
              ),
            if (m.notes != null) Text(m.notes!, style: small),
            Text('سجّلها ${m.createdBy?.name ?? '—'}', style: small),
            Wrap(
              spacing: 4,
              children: [
                if (m.supplier != null)
                  TextButton(
                    onPressed: () => push(context, SupplierDetailsScreen(id: m.supplier!.id)),
                    child: Text('المورد: ${m.supplier!.name}'),
                  ),
                if (m.invoice != null)
                  TextButton(
                    onPressed: () => push(context, InvoiceDetailsScreen(id: m.invoice!.id)),
                    child: Text('فاتورة ${m.invoice!.number}'),
                  ),
                if (m.documentType != null)
                  TextButton.icon(
                    onPressed: () => push(context, DocumentPdfScreen(type: m.documentType!, id: m.id)),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('طباعة'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
