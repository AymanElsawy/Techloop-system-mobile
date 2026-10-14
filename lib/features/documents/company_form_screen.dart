import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/session.dart';
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
            Input(
              label: 'اسم الشركة *',
              controller: _name,
              onChanged: (_) => setState(() {}),
            ),
            Input(
              label: 'التليفون',
              controller: _phone,
              keyboard: TextInputType.phone,
              ltr: true,
            ),
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
        if (_message != null)
          Note(_message!.$2, tone: _message!.$1 ? Tone.success : Tone.danger),
        SubmitButton(
          label: 'حفظ',
          loading: _saving,
          onPressed: _name.text.trim().length < 2 ? null : _save,
        ),
        if (context.user.role == UserRole.owner) const _Backups(),
      ],
    );
  }
}

/// Daily automatic backups (database + attachments). Owner only; downloading is on the web.
class _Backups extends StatefulWidget {
  const _Backups();

  @override
  State<_Backups> createState() => _BackupsState();
}

class _BackupsState extends State<_Backups> {
  final _ctl = AsyncController<List<Backup>>();
  bool _running = false;

  Future<void> _backupNow() async {
    setState(() => _running = true);
    try {
      await context.app.documents.createBackup();
      await _ctl.reload();
    } catch (e) {
      if (mounted)
        toast(
          context,
          errorMessage(
            e,
            'تعذر عمل النسخة. اتأكد إن mongodump متسطب على السيرفر.',
          ),
        );
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Backup>>(
      controller: _ctl,
      load: context.app.documents.backups,
      refreshable: false,
      builder: (context, list) => SectionCard(
        title: 'النسخ الاحتياطي',
        trailing: TextButton(
          onPressed: _running ? null : _backupNow,
          child: Text(_running ? 'جاري النسخ...' : 'نسخة الآن'),
        ),
        empty: 'لسه مفيش نسخ. بتتعمل نسخة كل يوم أوتوماتيك.',
        children: [
          for (final b in list)
            Tile(
              title: dateTime(b.createdAt),
              trailing: '${(b.size / 1048576).toStringAsFixed(1)} MB',
            ),
        ],
      ),
    );
  }
}
