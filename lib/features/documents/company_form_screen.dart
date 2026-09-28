import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../data/models/treasury.dart';
import '../../widgets/async_view.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// Company details printed on every document. Managers only.
class CompanyFormScreen extends StatelessWidget {
  const CompanyFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الشركة على الفواتير')),
      body: AsyncView<Company>(
        load: context.app.documents.company,
        refreshable: false,
        builder: (context, c) => _Form(company: c),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.company});

  final Company company;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final c = widget.company;
  late final _name = TextEditingController(text: c.name);
  late final _phone = TextEditingController(text: c.phone);
  late final _address = TextEditingController(text: c.address);
  late final _tax = TextEditingController(text: c.taxNumber);
  late final _cr = TextEditingController(text: c.commercialRegister);
  late final _footer = TextEditingController(text: c.footer);
  bool _saving = false;
  (bool, String)? _message;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await context.app.documents.updateCompany({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'taxNumber': _tax.text.trim(),
        'commercialRegister': _cr.text.trim(),
        'footer': _footer.text.trim(),
      });
      setState(() => _message = (true, 'اتحفظت. هتظهر على كل الفواتير.'));
    } catch (e) {
      setState(() => _message = (false, errorMessage(e)));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PageList(
      children: [
        const Text('بتتطبع في رأس وذيل كل فاتورة وإيصال.'),
        FormCard(
          children: [
            Input(label: 'اسم الشركة *', controller: _name, onChanged: (_) => setState(() {})),
            Input(label: 'التليفون', controller: _phone, keyboard: TextInputType.phone, ltr: true),
            Input(label: 'العنوان', controller: _address),
            Input(label: 'الرقم الضريبي', controller: _tax, ltr: true),
            Input(label: 'السجل التجاري', controller: _cr, ltr: true),
            Input(
              label: 'ملاحظة أسفل الفاتورة',
              controller: _footer,
              maxLines: 2,
              hint: 'مثال: البضاعة المباعة لا ترد ولا تستبدل',
            ),
          ],
        ),
        if (_message != null) Note(_message!.$2, tone: _message!.$1 ? Tone.success : Tone.danger),
        SubmitButton(label: 'حفظ', loading: _saving, onPressed: _name.text.trim().length < 2 ? null : _save),
      ],
    );
  }
}
