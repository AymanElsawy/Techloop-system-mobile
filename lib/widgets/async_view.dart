import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';

/// Lets a screen reload its data, or replace it with what an action returned.
class AsyncController<T> {
  _AsyncViewState<T>? _state;
  Future<void> reload() => _state?._refresh() ?? Future.value();
  void set(T value) => _state?._set(value);
}

/// Loading / error (+ retry) / data for one API call, with pull-to-refresh.
/// The builder must return a scrollable (usually [PageList]) when [refreshable] is true.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.controller,
    this.refreshable = true,
    this.errorText = 'حدث خطأ أثناء التحميل.',
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final AsyncController<T>? controller;
  final bool refreshable;
  final String errorText;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();
  T? _override;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(AsyncView<T> old) {
    super.didUpdateWidget(old);
    widget.controller?._state = this;
  }

  Future<void> _refresh() async {
    final next = widget.load();
    setState(() {
      _future = next;
      _override = null;
    });
    try {
      await next;
    } catch (_) {} // shown by the FutureBuilder
  }

  void _set(T value) => setState(() => _override = value);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        // Keep showing old data while a pull-to-refresh is running.
        final data = _override ?? snap.data;
        final Widget child;
        if (snap.hasError && snap.connectionState == ConnectionState.done) {
          child = ErrorState(
            message: snap.error is ApiException ? '${snap.error}' : widget.errorText,
            onRetry: _refresh,
          );
        } else if (data != null) {
          final body = widget.builder(context, data as T);
          child = widget.refreshable ? RefreshIndicator(onRefresh: _refresh, child: body) : body;
        } else {
          child = const Center(child: CircularProgressIndicator());
        }
        return AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: child);
      },
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: context.colors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}
