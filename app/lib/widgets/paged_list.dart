import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../shell/app_shell.dart';
import 'states.dart';

/// One page the server gave: its items, and where the next one starts (null on the last page).
class PagedResult<T> {
  const PagedResult(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;
}

typedef PageFetcher<T> = Future<PagedResult<T>> Function(String? cursor);

/// The state of a list that is read a page at a time (keyset pagination): the items so far, whether the first page or a
/// later one is loading, what failed, and whether there is more.
///
/// The rules it keeps:
/// - one request at a time: a call to [loadMore] while a page is loading is ignored;
/// - a failure of the first page empties the list and shows an error; a failure of a later page keeps what is shown
///   and puts the error at the end, and only [retry] asks again (scrolling does not hammer a server that failed);
/// - an answer that arrives after the list was started again ([loadFirst]) is thrown away;
/// - an item that is already in the list (same [idOf]) is not added twice, which can happen when something new is
///   posted between two pages.
class PagedController<T> extends ChangeNotifier {
  PagedController({required this.fetch, this.idOf, this.onAppended});

  final PageFetcher<T> fetch;

  /// A key for an item, to leave out one that is already there.
  final String Function(T item)? idOf;

  /// Called with the items a page added after the first one, so a queue of playing can grow with the list.
  final void Function(List<T> added)? onAppended;

  List<T> _items = [];
  String? _cursor;
  bool _hasMore = true;
  bool _firstLoaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => List.unmodifiable(_items);

  /// True from the start until the first page has arrived (or failed).
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get firstLoaded => _firstLoaded;
  bool get hasMore => _hasMore;

  /// Why the first page could not be had, or null.
  Object? get error => _error;

  /// Why a later page could not be had, or null.
  Object? get moreError => _moreError;

  bool get isEmpty => _firstLoaded && _items.isEmpty && _error == null;

  /// Starts again from the first page: for the first time, when the person logged in changed, or to refresh.
  Future<void> loadFirst() async {
    final generation = ++_generation;
    _items = [];
    _cursor = null;
    _hasMore = true;
    _firstLoaded = false;
    _loading = true;
    _loadingMore = false;
    _error = null;
    _moreError = null;
    _notify();
    try {
      final page = await fetch(null);
      if (_stale(generation)) return;
      _items = _unique(page.items, const []);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      _firstLoaded = true;
    } catch (error) {
      if (_stale(generation)) return;
      _error = error;
    } finally {
      if (!_stale(generation)) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Reads the next page, if there is one and nothing is loading.
  Future<void> loadMore() async {
    if (!_firstLoaded || !_hasMore || _loading || _loadingMore || _moreError != null) return;
    final generation = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await fetch(_cursor);
      if (_stale(generation)) return;
      final added = _unique(page.items, _items);
      _items = [..._items, ...added];
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      if (added.isNotEmpty) onAppended?.call(added);
    } catch (error) {
      if (_stale(generation)) return;
      _moreError = error;
    } finally {
      if (!_stale(generation)) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  /// Asks again for what failed: the first page, or the page after the last one shown.
  Future<void> retry() {
    if (!_firstLoaded) return loadFirst();
    _moreError = null;
    return loadMore();
  }

  /// Puts a newer version of an item (it was liked, renamed) in its place.
  void replace(bool Function(T item) test, T Function(T item) update) {
    var changed = false;
    _items = [
      for (final item in _items)
        if (test(item)) () {
          changed = true;
          return update(item);
        }() else item,
    ];
    if (changed) _notify();
  }

  void removeWhere(bool Function(T item) test) {
    final before = _items.length;
    _items = _items.where((item) => !test(item)).toList();
    if (_items.length != before) _notify();
  }

  List<T> _unique(List<T> incoming, List<T> existing) {
    final key = idOf;
    if (key == null) return List.of(incoming);
    final seen = {for (final item in existing) key(item)};
    return [
      for (final item in incoming)
        if (seen.add(key(item))) item,
    ];
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A scrolling list for a [PagedController]: skeletons while the first page loads, an error with a retry button, an
/// empty state, the items, and at the end a spinner or the error of the next page. It asks for the next page when the
/// user comes near the end, and also when the first page does not fill the screen (then there would be nothing to scroll).
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.empty,
    this.header,
    this.skeleton,
    this.skeletonCount = 3,
    this.itemGap = AppSpacing.lg,
    this.loadMoreDistance = 480,
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Shown when the list is empty (see [EmptyState]).
  final Widget empty;

  /// Above the items: the head of a profile, a title.
  final Widget? header;

  /// What one loading item looks like; null for a plain spinner.
  final Widget? skeleton;
  final int skeletonCount;
  final double itemGap;

  /// How close to the end (in pixels) the next page is asked for.
  final double loadMoreDistance;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    // A list that has not been laid out yet (a page behind another one, the first frame) has no extent to ask about.
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    if (_scroll.position.extentAfter < widget.loadMoreDistance) widget.controller.loadMore();
  }

  Widget _row(Widget child, {bool last = false}) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              PageContainer.sideMargin(context.screenSize),
              0,
              PageContainer.sideMargin(context.screenSize),
              last ? 0 : widget.itemGap,
            ),
            // Full width: a short child (a heading) would otherwise shrink and be centred by the Align.
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // A page that is too short to scroll must ask for the next one itself, once it is on the screen.
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

        final children = <Widget>[
          if (widget.header != null) _row(widget.header!),
          if (controller.error != null)
            _row(ErrorState.from(controller.error!, key: const Key('pagedError'), onRetry: controller.retry))
          else if (!controller.firstLoaded)
            for (var i = 0; i < widget.skeletonCount; i++)
              _row(widget.skeleton ?? const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: CircularProgressIndicator())))
          else if (controller.isEmpty)
            _row(widget.empty)
          else
            for (final (index, item) in controller.items.indexed) _row(widget.itemBuilder(context, item, index)),
          if (controller.loadingMore)
            _row(const Padding(
              key: Key('pagedLoadingMore'),
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
            ))
          else if (controller.moreError != null)
            _row(ErrorState.from(controller.moreError!, key: const Key('pagedMoreError'), onRetry: controller.retry, compact: true)),
          const SizedBox(height: AppSpacing.xl),
        ];

        return ListView(
          key: const Key('pagedList'),
          controller: _scroll,
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          children: children,
        );
      },
    );
  }
}
