import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// First login: the user replaces the default password before entering the app.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.session});

  final Session session;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(_password.text);
    } catch (e) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = e is ApiException && e.status == 400
              ? 'اختار كلمة مرور غير الافتراضية (8 أحرف على الأقل).'
              : errorMessage(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كلمة مرور جديدة'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: widget.session.logout,
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: PageList(
          children: [
            Note(
              'أهلاً ${widget.session.user!.name}، أول دخول ليك: اختار كلمة مرور جديدة بدل الافتراضية.',
            ),
            FormCard(
              children: [
                Input(
                  label: 'كلمة المرور الجديدة',
                  controller: _password,
                  obscure: true,
                  ltr: true,
                  validator: (v) =>
                      v.length < 8 ? 'كلمة المرور 8 أحرف على الأقل.' : null,
                ),
                Input(
                  label: 'تأكيد كلمة المرور',
                  controller: _confirm,
                  obscure: true,
                  ltr: true,
                  validator: (v) =>
                      v != _password.text ? 'كلمتين المرور مش زي بعض.' : null,
                ),
              ],
            ),
            SubmitButton(
              label: 'حفظ والدخول',
              loading: _saving,
              onPressed: _submit,
            ),
            if (_error != null) Note(_error!, tone: Tone.danger),
          ],
        ),
      ),
    );
  }
}
