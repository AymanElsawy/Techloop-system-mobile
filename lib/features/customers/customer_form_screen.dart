import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/location.dart';
import '../../data/models/common.dart';
import '../../data/models/customer.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';
import 'customer_details_screen.dart';

/// New customer, or edit when [id] is set. A rep editing a customer that is not their own pending one
/// may only change contact details (the backend enforces the same).
class CustomerFormScreen extends StatelessWidget {
  const CustomerFormScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? 'عميل جديد' : 'تعديل العميل')),
      body: id == null
          ? const _Form(customer: null)
          : AsyncView<Customer>(
              load: () => context.app.customers.get(id!),
              refreshable: false,
              errorText: 'حدث خطأ أثناء تحميل بيانات العميل.',
              builder: (context, c) => _Form(customer: c),
            ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.customer});

  final Customer? customer;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late final c = widget.customer;
  late final _name = TextEditingController(text: c?.name);
  late final _phone = TextEditingController(text: c?.phone);
  late final _contact = TextEditingController(text: c?.contactPerson);
  late final _city = TextEditingController(text: c?.city);
  late final _address = TextEditingController(text: c?.address);
  late final _notes = TextEditingController(text: c?.notes);
  late String _type = c?.type ?? 'CLINIC';
  late String? _governorate = c?.governorate;
  late GeoPoint? _location = c?.location;
  bool _locating = false;
  bool _locationError = false;
  bool _saving = false;
  String? _error;

  late final bool _manager = context.isManager;

  /// Reps editing someone else's (or an approved) customer: contact details only.
  late final bool _contactOnly =
      c != null && !_manager && !(c!.status == 'PENDING' && c!.createdBy?.id == context.user.id);

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = false;
    });
    final loc = await currentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _location = loc ?? _location;
      _locationError = loc == null;
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final contact = {
      'phone': _phone.text.trim(),
      'contactPerson': _contact.text.trim(),
      'city': _city.text.trim(),
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
      'location': _location == null ? null : {'latitude': _location!.latitude, 'longitude': _location!.longitude},
    };
    final all = {...contact, 'name': _name.text.trim(), 'type': _type, 'governorate': _governorate};
    final repo = context.app.customers;
    try {
      final saved = c == null ? await repo.create(all) : await repo.update(c!.id, _contactOnly ? contact : all);
      if (!mounted) return;
      if (c == null) {
        replace(context, CustomerDetailsScreen(id: saved.id));
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e is ApiException && e.status == 409
            ? 'يوجد عميل مسجل بنفس رقم الهاتف.'
            : errorMessage(e, 'تعذر حفظ العميل. حاول مرة أخرى.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = _manager ? governorates : context.user.governorates;
    return Form(
      key: _form,
      child: PageList(
        children: [
          if (!_manager && c == null)
            const Note('سيظهر العميل بانتظار موافقة الإدارة، ويمكنك جدولة زيارات له في هذه الأثناء.'),
          if (_contactOnly)
            const Note('يمكنك تعديل بيانات التواصل والعنوان فقط. الاسم والنوع والمحافظة تعدلها الإدارة.'),
          FormCard(
            children: [
              Input(
                label: 'اسم العميل *',
                controller: _name,
                enabled: !_contactOnly,
                validator: (v) => v.trim().length < 2 ? 'اسم العميل مطلوب (حرفان على الأقل).' : null,
              ),
              Select<String>(
                label: 'نوع العميل',
                value: _type,
                items: customerTypeLabels,
                onChanged: _contactOnly ? null : (v) => setState(() => _type = v!),
              ),
              Input(
                label: 'الهاتف',
                controller: _phone,
                keyboard: TextInputType.phone,
                ltr: true,
                validator: (v) =>
                    v.trim().isEmpty || RegExp(r'^\+?[0-9 ]{6,20}$').hasMatch(v.trim()) ? null : 'رقم الهاتف غير صحيح.',
              ),
              Input(label: 'الشخص المسؤول', controller: _contact),
            ],
          ),
          FormCard(
            title: 'العنوان',
            children: [
              Select<String>(
                label: 'المحافظة *',
                value: _governorate,
                hint: 'اختر المحافظة',
                // A customer outside the rep's region keeps its governorate in the list.
                items: {
                  for (final g in {...regions, ?c?.governorate}) g: g,
                },
                onChanged: _contactOnly ? null : (v) => setState(() => _governorate = v),
                validator: (v) => v == null ? 'المحافظة مطلوبة.' : null,
              ),
              Input(label: 'المدينة', controller: _city),
              Input(label: 'العنوان', controller: _address),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _locate,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _locating
                          ? 'جاري تحديد الموقع...'
                          : _location != null
                          ? 'تحديث الموقع'
                          : 'تحديد الموقع (GPS)',
                    ),
                  ),
                  if (_location != null) ...[
                    const StatusBadge('تم تحديد الموقع', tone: Tone.success),
                    TextButton(onPressed: () => setState(() => _location = null), child: const Text('إزالة')),
                  ],
                ],
              ),
              if (_locationError) const Note('تعذر تحديد الموقع. تأكد من السماح بالوصول للموقع.', tone: Tone.danger),
            ],
          ),
          FormCard(
            children: [Input(label: 'ملاحظات', controller: _notes, maxLines: 3)],
          ),
          SubmitButton(label: c == null ? 'إضافة العميل' : 'حفظ التعديلات', loading: _saving, onPressed: _submit),
          if (_error != null) Note(_error!, tone: Tone.danger),
        ],
      ),
    );
  }
}
