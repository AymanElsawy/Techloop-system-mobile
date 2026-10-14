import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/offline.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/form.dart';
import '../../widgets/ui.dart';

/// Wraps every screen (MaterialApp.builder): a bar at the bottom while offline or while saved
/// requests wait to be sent. Tapping it opens the list of saved requests.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.session,
    required this.navigator,
    required this.child,
  });

  final Session session;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final store = session.store;
    if (store == null) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([store.offline, store.queue, session]),
      builder: (context, _) {
        final ops = session.user == null
            ? <PendingOp>[]
            : store.queueOf(session.user!.id);
        final failed = ops.where((o) => o.error != null).length;
        if (!store.offline.value && ops.isEmpty) return child;
        final tone = failed > 0 ? Tone.danger : Tone.warning;
        final (bg, fg) = tone.colors(context);
        final text = [
          if (store.offline.value) 'بدون إنترنت · بتشوف آخر بيانات اتحملت',
          if (ops.length > failed) '${ops.length - failed} مستني الإرسال',
          if (failed > 0) '$failed اترفض',
        ].join(' · ');
        return Column(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: child,
              ),
            ),
            Material(
              color: bg,
              child: InkWell(
                onTap: ops.isEmpty
                    ? null
                    : () => navigator.currentState?.push(
                        MaterialPageRoute<void>(
                          builder: (_) => PendingOpsScreen(session: session),
                        ),
                      ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          store.offline.value
                              ? Icons.cloud_off
                              : Icons.cloud_upload_outlined,
                          size: 18,
                          color: fg,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              color: fg,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (ops.isNotEmpty)
                          Icon(Icons.chevron_left, size: 18, color: fg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Requests saved while offline: sent automatically when the connection is back.
/// A rejected one shows why; the user retries it or deletes it.
class PendingOpsScreen extends StatelessWidget {
  const PendingOpsScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final store = session.store!;
    final api = session.api;
    return Scaffold(
      appBar: AppBar(title: const Text('مستني الإرسال')),
      body: ValueListenableBuilder(
        valueListenable: store.queue,
        builder: (context, _, _) {
          final ops = store.queueOf(session.user?.id);
          return PageList(
            children: [
              Text(
                'اتحفظت على الموبايل وقت ما النت كان فاصل، وبتتبعت لوحدها أول ما النت يرجع.',
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
              SectionCard(
                title: '${ops.length} عملية',
                empty: 'كل حاجة اتبعتت.',
                trailing: TextButton(
                  onPressed: api.syncQueue,
                  child: const Text('إرسال الآن'),
                ),
                children: [
                  for (final op in ops)
                    Tile(
                      title: op.label,
                      subtitle: [
                        dateTime(op.createdAt),
                        op.error ?? 'مستني النت',
                      ].dotted(),
                      badge: op.error == null
                          ? null
                          : const StatusBadge('اترفض', tone: Tone.danger),
                      onTap: () => _actions(context, op),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _actions(BuildContext context, PendingOp op) async {
    final store = session.store!;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(op.label),
              subtitle: op.error == null ? null : Text(op.error!),
            ),
            if (op.error != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('إعادة المحاولة'),
                onTap: () => Navigator.pop(context, 'retry'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.colors.danger),
              title: Text(
                'حذف',
                style: TextStyle(color: context.colors.danger),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'retry') {
      await store.setError(op.id, null);
      await session.api.syncQueue();
    } else if (action == 'delete' && context.mounted) {
      if (await confirm(
        context,
        'حذف العملية',
        'مش هتتبعت للسيرفر خالص. متأكد؟',
      ))
        await store.remove(op.id);
    }
  }
}
