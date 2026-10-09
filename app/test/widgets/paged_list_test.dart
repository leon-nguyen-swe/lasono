import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/data/repository_exception.dart';
import 'package:lasono_app/widgets/paged_list.dart';

import '../support/test_harness.dart';

/// A server that has [total] numbered items and gives them [size] at a time, with a cursor like the real one.
class _Server {
  _Server(this.total, {this.size = 3});

  final int total;
  final int size;
  final cursors = <String?>[];
  Completer<void>? gate;
  Object? failure;

  Future<PagedResult<int>> page(String? cursor) async {
    cursors.add(cursor);
    await gate?.future;
    final failing = failure;
    if (failing != null) throw failing;
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + size).clamp(0, total);
    return PagedResult([for (var i = start; i < end; i++) i], end < total ? '$end' : null);
  }
}

PagedController<int> _controller(_Server server, {void Function(List<int>)? onAppended}) =>
    PagedController<int>(fetch: server.page, idOf: (n) => '$n', onAppended: onAppended);

void main() {
  group('PagedController', () {
    test('starts empty and not loaded', () {
      final c = _controller(_Server(5));
      expect(c.items, isEmpty);
      expect((c.loading, c.firstLoaded, c.error, c.hasMore), (false, false, null, true));
      expect(c.isEmpty, isFalse, reason: 'it is not known to be empty until the first page has come');
    });

    test('loadFirst reads the first page, and says there is more when there is a cursor', () async {
      final server = _Server(8);
      final c = _controller(server);

      final done = c.loadFirst();
      expect(c.loading, isTrue);
      await done;

      expect(c.items, [0, 1, 2]);
      expect((c.loading, c.firstLoaded, c.hasMore), (false, true, true));
      expect(server.cursors, [null]);
    });

    test('loadMore goes on from the cursor of the last page until the cursor is gone', () async {
      final server = _Server(7);
      final c = _controller(server);
      await c.loadFirst();

      await c.loadMore();
      await c.loadMore();

      expect(c.items, [0, 1, 2, 3, 4, 5, 6]);
      expect(c.hasMore, isFalse);
      expect(server.cursors, [null, '3', '6']);

      await c.loadMore();
      expect(server.cursors.length, 3, reason: 'nothing is asked for after the last page');
    });

    test('a list with nothing in it is empty, not an error', () async {
      final c = _controller(_Server(0));
      await c.loadFirst();
      expect(c.isEmpty, isTrue);
      expect(c.hasMore, isFalse);
    });

    test('only one request at a time: asking for more while a page is coming does nothing', () async {
      final server = _Server(9)..gate = Completer<void>();
      final c = _controller(server);
      final first = c.loadFirst();
      server.gate!.complete();
      await first;
      server.gate = Completer<void>();

      final one = c.loadMore();
      final two = c.loadMore();
      final three = c.loadMore();
      expect(c.loadingMore, isTrue);
      server.gate!.complete();
      await Future.wait([one, two, three]);

      expect(server.cursors, [null, '3']);
      expect(c.items, [0, 1, 2, 3, 4, 5]);
    });

    test('a failure of the first page is an error with nothing shown, and retry asks for the first page again', () async {
      final server = _Server(5)..failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      final c = _controller(server);

      await c.loadFirst();
      expect(c.error, isNotNull);
      expect(c.items, isEmpty);
      expect(c.firstLoaded, isFalse);

      server.failure = null;
      await c.retry();
      expect(c.error, isNull);
      expect(c.items, [0, 1, 2]);
    });

    test('a failure of a later page keeps what is shown, and only retry asks again', () async {
      final server = _Server(9);
      final c = _controller(server);
      await c.loadFirst();

      server.failure = const RepositoryException('x', kind: RepositoryErrorKind.server);
      await c.loadMore();
      expect(c.moreError, isNotNull);
      expect(c.items, [0, 1, 2]);

      await c.loadMore();
      await c.loadMore();
      expect(server.cursors, [null, '3'], reason: 'scrolling does not hammer a server that failed');

      server.failure = null;
      await c.retry();
      expect(c.moreError, isNull);
      expect(c.items, [0, 1, 2, 3, 4, 5]);
    });

    test('an answer that comes after the list was started again is thrown away', () async {
      final server = _Server(9)..gate = Completer<void>();
      final c = _controller(server);
      final old = c.loadFirst();

      server.gate!.complete();
      server.gate = null;
      await c.loadFirst();
      await old;

      expect(c.items, [0, 1, 2]);
      expect(c.loading, isFalse);
    });

    test('loadFirst empties the list while it loads, and also clears an error', () async {
      final server = _Server(9);
      final c = _controller(server);
      await c.loadFirst();
      server.failure = const RepositoryException('x');
      await c.loadMore();

      server.failure = null;
      final again = c.loadFirst();
      expect(c.items, isEmpty);
      expect(c.moreError, isNull);
      await again;
      expect(c.items, [0, 1, 2]);
    });

    test('an item already in the list is not added twice when something new shifts the pages', () async {
      var shifted = false;
      final c = PagedController<int>(
        fetch: (cursor) async => cursor == null ? const PagedResult([1, 2, 3], 'next') : (shifted = true) ? const PagedResult([3, 4, 5], null) : const PagedResult([], null),
        idOf: (n) => '$n',
      );
      await c.loadFirst();
      await c.loadMore();

      expect(shifted, isTrue);
      expect(c.items, [1, 2, 3, 4, 5]);
    });

    test('tells who wants to know about the items a later page added, not the first page', () async {
      final added = <List<int>>[];
      final c = _controller(_Server(7), onAppended: added.add);
      await c.loadFirst();
      expect(added, isEmpty);

      await c.loadMore();
      await c.loadMore();

      expect(added, [
        [3, 4, 5],
        [6],
      ]);
    });

    test('replace changes the items that match, and tells the listeners only when something changed', () async {
      final c = _controller(_Server(5));
      await c.loadFirst();
      var told = 0;
      c.addListener(() => told++);

      c.replace((n) => n == 1, (n) => 100);
      expect(c.items, [0, 100, 2]);
      expect(told, 1);

      c.replace((n) => n == 99, (n) => 0);
      expect(told, 1);
    });

    test('removeWhere drops the items that match', () async {
      final c = _controller(_Server(5));
      await c.loadFirst();
      c.removeWhere((n) => n.isOdd);
      expect(c.items, [0, 2]);
    });

    test('after dispose a late answer changes nothing and does not throw', () async {
      final server = _Server(5)..gate = Completer<void>();
      final c = _controller(server);
      final pending = c.loadFirst();
      c.dispose();
      server.gate!.complete();
      await pending;
    });
  });

  group('PagedListView', () {
    Widget view(PagedController<int> controller, {double width = 800}) => themed(
          SizedBox(
            width: width,
            child: PagedListView<int>(
              controller: controller,
              skeleton: const SizedBox(key: Key('skeletonRow'), height: 60),
              empty: const Text('chưa có gì', key: Key('emptyView')),
              itemBuilder: (context, n, index) => SizedBox(key: Key('item-$n'), height: 100, child: Text('mục $n')),
            ),
          ),
        );

    testWidgets('shows skeletons while the first page loads, then the items', (tester) async {
      TestEnv.window(tester, width: 800, height: 900);
      final server = _Server(2)..gate = Completer<void>();
      final controller = _controller(server);
      await tester.pumpWidget(view(controller));
      unawaited(controller.loadFirst());
      await tester.pump();
      expect(find.byKey(const Key('skeletonRow')), findsNWidgets(3));

      server.gate!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('skeletonRow')), findsNothing);
      expect(find.text('mục 0'), findsOneWidget);
      expect(find.text('mục 1'), findsOneWidget);
    });

    testWidgets('shows the empty view for a list with nothing in it', (tester) async {
      TestEnv.window(tester, width: 800, height: 900);
      final controller = _controller(_Server(0));
      await tester.pumpWidget(view(controller));
      await controller.loadFirst();
      await tester.pump();
      expect(find.byKey(const Key('emptyView')), findsOneWidget);
    });

    testWidgets('shows an error with a button that asks again', (tester) async {
      TestEnv.window(tester, width: 800, height: 900);
      final server = _Server(2)..failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      final controller = _controller(server);
      await tester.pumpWidget(view(controller));
      await controller.loadFirst();
      await tester.pump();
      expect(find.byKey(const Key('pagedError')), findsOneWidget);
      expect(find.textContaining('kết nối'), findsOneWidget);

      server.failure = null;
      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pump();
      await tester.pump();
      expect(find.text('mục 0'), findsOneWidget);
    });

    testWidgets('asks for the next page when the user scrolls near the end, and not before', (tester) async {
      TestEnv.window(tester, width: 800, height: 600);
      final server = _Server(30, size: 10);
      final controller = _controller(server);
      await tester.pumpWidget(view(controller));
      await controller.loadFirst();
      await tester.pump();
      expect(server.cursors, [null], reason: 'the first page fills the window: nothing more is asked for yet');

      await tester.drag(find.byKey(const Key('pagedList')), const Offset(0, -700));
      await tester.pump();
      await tester.pump();

      expect(server.cursors, [null, '10']);
    });

    testWidgets('asks for the next page by itself when the first page is too short to scroll', (tester) async {
      TestEnv.window(tester, width: 800, height: 900);
      final server = _Server(30, size: 2);
      final controller = _controller(server);
      await tester.pumpWidget(view(controller));

      await controller.loadFirst();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(server.cursors.length, greaterThan(2), reason: 'two items do not fill the window, so more were asked for');
      expect(controller.items.length, greaterThan(2));
    });

    testWidgets('shows a spinner at the end while a later page loads, and its error with a retry when it fails', (tester) async {
      TestEnv.window(tester, width: 800, height: 400);
      final server = _Server(30, size: 10);
      final controller = _controller(server);
      await tester.pumpWidget(view(controller));
      await controller.loadFirst();
      await tester.pump();

      server.gate = Completer<void>();
      await tester.drag(find.byKey(const Key('pagedList')), const Offset(0, -900));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('pagedLoadingMore')), findsOneWidget);

      server.failure = const RepositoryException('x', kind: RepositoryErrorKind.network);
      server.gate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byKey(const Key('pagedList')), const Offset(0, -2000));
      await tester.pump();
      expect(find.byKey(const Key('pagedMoreError')), findsOneWidget);

      server.failure = null;
      server.gate = null;
      await tester.tap(find.byKey(const Key('retryButton')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('pagedMoreError')), findsNothing);
      expect(controller.items.length, 20);
    });

    testWidgets('puts a header above the items, and keeps the rows in the middle of a wide window', (tester) async {
      TestEnv.window(tester, width: 1600, height: 900);
      final controller = _controller(_Server(2));
      await tester.pumpWidget(themed(
        PagedListView<int>(
          controller: controller,
          header: const Text('đầu trang', key: Key('header')),
          empty: const SizedBox(),
          itemBuilder: (context, n, index) => SizedBox(key: Key('item-$n'), height: 80, width: double.infinity),
        ),
      ));
      await controller.loadFirst();
      await tester.pump();

      expect(tester.getTopLeft(find.byKey(const Key('header'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('item-0'))).dy));
      expect(tester.getCenter(find.byKey(const Key('item-0'))).dx, 800);
      expect(tester.getSize(find.byKey(const Key('item-0'))).width, lessThanOrEqualTo(1200));
    });

    testWidgets('a short header starts at the same left edge as the rows, not in the middle', (tester) async {
      TestEnv.window(tester, width: 1600, height: 900);
      final controller = _controller(_Server(2));
      await tester.pumpWidget(themed(
        PagedListView<int>(
          controller: controller,
          header: const Text('đầu trang', key: Key('header')),
          empty: const SizedBox(),
          itemBuilder: (context, n, index) => SizedBox(key: Key('item-$n'), height: 80, width: double.infinity),
        ),
      ));
      await controller.loadFirst();
      await tester.pump();

      expect(tester.getTopLeft(find.byKey(const Key('header'))).dx, tester.getTopLeft(find.byKey(const Key('item-0'))).dx);
    });
  });
}
