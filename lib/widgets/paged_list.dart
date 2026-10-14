import 'package:flutter/material.dart';

import '../core/api.dart';
import '../data/models/common.dart';
import 'async_view.dart';
import 'ui.dart';

/// Lets a screen reload a [PagedListView] (e.g. back from a details screen).
class PagedController {
  _PagedListViewState? _state;
  Future<void> reload() => _state?._refresh() ?? Future.value();
}

/// Infinite scroll: loads [pageSize] rows, and the next page when the end of the list shows.
/// Pull-to-refresh and [PagedController.reload] reload the pages already shown, so the scroll position stays.
/// Give it a new key when the filters change.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.emptyText,
    this.controller,
    this.header,
    this.errorText = 'حدث خطأ أثناء التحميل.',
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 96),
  });

  final Future<PageOf<T>> Function(int page) load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final PagedController? controller;

  /// First row, built from the last loaded page (totals).
  final Widget Function(BuildContext context, PageOf<T> last)? header;
  final String errorText;
  final EdgeInsets padding;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _items = <T>[];
  PageOf<T>? _last;
  int _pages = 0;
  bool _loading = false;
  Object? _error;

  bool get _done => _last != null && _items.length >= _last!.total;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _loadMore();
  }

  @override
  void didUpdateWidget(PagedListView<T> old) {
    super.didUpdateWidget(old);
    widget.controller?._state = this;
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(_pages + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _last = page;
        _pages++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ponytail: a page still loading at the same time is dropped by the [_loading] guard, fine for one user scrolling.
  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final pages = await Future.wait([
        for (var p = 1; p <= (_pages < 1 ? 1 : _pages); p++) widget.load(p),
      ]);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(pages.expand((p) => p.items));
        _last = pages.last;
        _pages = pages.length;
        _error = null;
      });
    } catch (e) {
      // Keep the rows already shown; an empty list shows the error instead.
      if (mounted && _items.isEmpty) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  String get _errorMessage =>
      _error is ApiException ? '$_error' : widget.errorText;

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_error != null) {
        return ErrorState(message: _errorMessage, onRetry: _loadMore);
      }
      if (_last == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: PageList(
          children: [
            if (widget.header case final header?) header(context, _last!),
            EmptyCard(widget.emptyText),
          ],
        ),
      );
    }
    final header = widget.header;
    final offset = header == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: offset + _items.length + (_done ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i < offset) return header!(context, _last!);
          i -= offset;
          if (i < _items.length) return widget.itemBuilder(context, _items[i]);
          // Footer: the end of the list is on screen, load the next page.
          if (_error != null) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh),
                label: Text('$_errorMessage إعادة المحاولة'),
              ),
            );
          }
          if (!_loading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadMore();
            });
          }
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

/// A whole screen of [PagedListView] ("عرض الكل" from a section that shows only the latest rows).
class PagedScreen<T> extends StatelessWidget {
  const PagedScreen({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    required this.emptyText,
    this.controller,
  });

  final String title;
  final Future<PageOf<T>> Function(int page) load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final PagedController? controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PagedListView<T>(
      controller: controller,
      load: load,
      itemBuilder: itemBuilder,
      emptyText: emptyText,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
    ),
  );
}
