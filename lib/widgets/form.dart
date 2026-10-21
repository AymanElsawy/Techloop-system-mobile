/// Form helpers: padded form card, fields, pickers, dialogs.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models/common.dart';
import '../data/repositories/sales_repository.dart';
import 'ui.dart';

/// Card holding form fields with even gaps.
class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Text field with an inside placeholder. `ltr` for numbers, phones, codes.
class Input extends StatelessWidget {
  const Input({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.validator,
    this.keyboard,
    this.ltr = false,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final String? Function(String value)? validator;
  final TextInputType? keyboard;
  final bool ltr;
  final int maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final bool obscure;

  /// Decimal amount keyboard (money).
  static const decimal = TextInputType.numberWithOptions(decimal: true);

  @override
  Widget build(BuildContext context) {
    final digitsOnly = keyboard == TextInputType.number;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboard,
      maxLines: maxLines,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr ? TextAlign.right : TextAlign.start,
      inputFormatters: [
        if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
        if (keyboard == decimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        hintText: hint ?? label,
        helperText: helper,
        helperMaxLines: 3,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator == null ? null : (v) => validator!(v ?? ''),
      onChanged: onChanged,
    );
  }
}

/// Dropdown with an inside placeholder; `null` value shows it.
class Select<T> extends StatelessWidget {
  const Select({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.validator,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? Function(T? value)? validator;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey(value), // reflect programmatic changes
      initialValue: items.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(),
      hint: Text(hint ?? label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }
}

/// Read-only field that opens the date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.withTime = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool withTime;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final day = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 10),
        );
        if (day == null || !context.mounted) return;
        if (!withTime) return onChanged(day);
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value ?? now),
        );
        if (t == null) return;
        onChanged(DateTime(day.year, day.month, day.day, t.hour, t.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 20)
              : IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => onChanged(null),
                ),
        ),
        isEmpty: value == null,
        child: value == null
            ? null
            : Text(withTime ? dateTime(value!) : shortDate(value!)),
      ),
    );
  }
}

/// One chip for a from / to filter (instead of two date fields): "الفترة", or the picked range with ✕.
class PeriodChip extends StatelessWidget {
  const PeriodChip({super.key, required this.value, required this.onChanged});

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = value;
    Future<void> pick() async {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: r,
        firstDate: DateTime(now.year - 5),
        // Filters look back, so the picker opens on this month with older months above.
        lastDate: DateTime(now.year, now.month, now.day),
      );
      if (picked != null) onChanged(picked);
    }

    return InputChip(
      avatar: const Icon(Icons.date_range_outlined, size: 18),
      label: Text(
        r == null
            ? 'الفترة'
            // Isolates keep "from – to" in order inside RTL text.
            : '\u2068${shortDate(r.start)}\u2069 – \u2068${shortDate(r.end)}\u2069',
      ),
      selected: r != null,
      showCheckmark: false,
      onPressed: pick,
      onDeleted: r == null ? null : () => onChanged(null),
      deleteButtonTooltipMessage: 'مسح',
    );
  }
}

/// Full-width primary button with a spinner while [loading].
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(label),
      ),
    );
  }
}

/// Reason dialog (cancel / reject). Returns the trimmed text, or null when dismissed.
/// [minLength] 0 makes the reason optional.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  String? message,
  int minLength = 3,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final valid = controller.text.trim().length >= minLength;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Text(
                  message,
                  style: TextStyle(color: context.colors.muted, fontSize: 13.5),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: minLength == 0 ? 'السبب (اختياري)' : 'السبب',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, controller.text.trim())
                  : null,
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ) ??
    false;

/// Camera / gallery / file (image or PDF), max 5 MB. Photos are compressed by the picker.
Future<UploadFile?> pickAttachment(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('تصوير'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('من المعرض'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('ملف PDF'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  UploadFile? file;
  try {
    if (source == 'file') {
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (f != null) file = (bytes: await f.xFile.readAsBytes(), name: f.name);
    } else {
      final x = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 2000,
      );
      if (x != null) file = (bytes: await x.readAsBytes(), name: x.name);
    }
  } catch (_) {
    if (context.mounted)
      toast(context, 'تعذر فتح الكاميرا أو الملفات. تأكد من السماح بالوصول.');
    return null;
  }
  if (file != null && file.bytes.length > attachmentMaxBytes) {
    if (context.mounted) toast(context, 'حجم الملف أكبر من 5 ميجابايت.');
    return null;
  }
  return file;
}

/// Positive number from a text field, or null.
num? parseAmount(String text) => num.tryParse(text.trim());

String? requiredText(String v, [String message = 'مطلوب.']) =>
    v.trim().isEmpty ? message : null;
