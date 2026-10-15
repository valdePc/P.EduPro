import 'dart:async';

import 'package:edupro/models/team_school_catalog.dart';
import 'package:edupro/services/team_school_catalog_controller.dart';
import 'package:edupro/widgets/school_catalog_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> page({
  String id = 'A',
  String role = 'super_admin',
  String? cursor,
  int total = 280,
  int matching = 280,
  bool metrics = true,
  bool includeTotal = true,
}) => {
  'role': role,
  'schools': [
    {
      'id': id,
      'data': {'name': 'Colegio $id'},
    },
  ],
  'nextCursor': cursor,
  if (includeTotal) 'matchingTotal': matching,
  if (metrics)
    'metrics': {
      'total': total,
      'active': total,
      'suspended': 0,
      'draft': 0,
      if (role != 'billing_admin') 'located': total,
    },
};

void main() {
  test('invalid pages and metrics fail closed', () {
    for (final data in [
      {...page(), 'role': 'invented'},
      {...page(), 'nextCursor': '../A'},
      {
        ...page(),
        'schools': [
          {'id': 'EduProApp_Admin_X', 'data': {}},
        ],
      },
      {
        ...page(),
        'schools': List.generate(26, (i) => {'id': 'S$i', 'data': {}}),
      },
      {
        ...page(),
        'schools': [
          {'id': 'A', 'data': {}},
          {'id': 'A', 'data': {}},
        ],
      },
      {
        ...page(),
        'metrics': {'total': 1, 'active': 2, 'suspended': 0, 'draft': 0},
      },
    ]) {
      expect(() => SchoolCatalogPage.fromMap(data), throwsFormatException);
    }
  });

  testWidgets(
    'one shared page serves multiple sections without downloading following pages',
    (tester) async {
      var calls = 0;
      final queries = <Map<String, dynamic>>[];
      final catalog = TeamSchoolCatalogController(
        fetch: (query) async {
          calls++;
          queries.add(query);
          return page(cursor: 'A');
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      catalog.ensureFresh();
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      expect(queries.single['limit'], 25);
      expect(catalog.error, isNull);
      expect(catalog.loading, isFalse);
      expect(catalog.hasNext, isTrue);
      catalog.ensureFresh();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
    },
  );

  testWidgets(
    'next is explicit, repeated clicks are ignored, previous uses the cache',
    (tester) async {
      final queries = <Map<String, dynamic>>[];
      final next = Completer<Map<String, dynamic>>();
      final catalog = TeamSchoolCatalogController(
        fetch: (query) async {
          queries.add(query);
          return queries.length == 1 ? page(cursor: 'A') : next.future;
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pump();
      await tester.pump();
      unawaited(catalog.next());
      unawaited(catalog.next());
      expect(queries.length, 2);
      expect(queries.last['cursor'], 'A');
      expect(queries.last['includeMetrics'], false);
      next.complete(page(id: 'B', metrics: false, includeTotal: false));
      await tester.pump();
      await tester.pump();
      expect(catalog.records.single.id, 'B');
      expect(catalog.pageIndex, 1);
      await catalog.previous();
      expect(catalog.records.single.id, 'A');
      expect(catalog.pageIndex, 0);
      expect(catalog.error, isNull);
      expect(queries.length, 2);
    },
  );

  testWidgets(
    'search is debounced, reaches the server and keeps global totals',
    (tester) async {
      final queries = <Map<String, dynamic>>[];
      final catalog = TeamSchoolCatalogController(
        fetch: (query) async {
          queries.add(query);
          return queries.length == 1
              ? page(cursor: 'A')
              : page(id: 'S257', metrics: false, matching: 1);
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pump();
      await tester.pump();
      catalog.setSearch('ag');
      await tester.pump(const Duration(milliseconds: 100));
      catalog.setSearch('aguila');
      await tester.pump(const Duration(milliseconds: 349));
      expect(queries.length, 1);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(queries.last['search'], 'aguila');
      expect(queries.last.containsKey('cursor'), isFalse);
      expect(catalog.records.single.id, 'S257');
      expect(catalog.matchingTotal, 1);
      expect(catalog.metrics!.total, 280);
    },
  );

  testWidgets('obsolete searches cannot overwrite a newer province query', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    final catalog = TeamSchoolCatalogController(
      fetch:
          (query) async =>
              query['province'] == '' ? old.future : page(id: 'ProvinceResult'),
      currentUid: () => 'user',
      sessionUid: 'user',
    );
    addTearDown(catalog.dispose);
    catalog.ensureFresh();
    await tester.pump();
    catalog.setProvince('Azua');
    await tester.pump();
    await tester.pump();
    expect(catalog.records.single.id, 'ProvinceResult');
    old.complete(page(id: 'Obsolete'));
    await tester.pump();
    await tester.pump();
    expect(catalog.records.single.id, 'ProvinceResult');
  });

  testWidgets(
    'changing account clears cached pages and rejects late responses',
    (tester) async {
      String? uid = 'user';
      final request = Completer<Map<String, dynamic>>();
      final catalog = TeamSchoolCatalogController(
        fetch: (_) => request.future,
        currentUid: () => uid,
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pump();
      uid = 'another-account';
      request.complete(page());
      await tester.pump();
      await tester.pump();
      expect(catalog.records, isEmpty);
      expect(catalog.metrics, isNull);
      expect(catalog.error, isNotNull);
    },
  );

  testWidgets(
    'role downgrade drops the old projection and reloads the first page',
    (tester) async {
      var calls = 0;
      final catalog = TeamSchoolCatalogController(
        fetch: (query) async {
          calls++;
          return calls == 1
              ? page(cursor: 'A')
              : page(id: 'B', role: 'billing_admin', metrics: calls == 3);
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pump();
      await tester.pump();
      await catalog.next();
      expect(calls, 3);
      expect(catalog.pageIndex, 0);
      expect(catalog.role, 'billing_admin');
      expect(catalog.metrics!.located, isNull);
      expect(
        catalog.records.every((record) => record.role == 'billing_admin'),
        isTrue,
      );
    },
  );

  testWidgets(
    'timeout and network failure are recoverable without retaining old data',
    (tester) async {
      var calls = 0;
      final hanging = Completer<Map<String, dynamic>>();
      final catalog = TeamSchoolCatalogController(
        fetch: (_) async {
          calls++;
          if (calls == 1) return hanging.future;
          if (calls == 2) throw StateError('private diagnostic');
          return page();
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(catalog.error, isA<TimeoutException>());
      await catalog.retry();
      expect(catalog.records, isEmpty);
      expect(catalog.metrics, isNull);
      await catalog.retry();
      expect(catalog.error, isNull);
      expect(catalog.records.single.id, 'A');
      hanging.complete(page(id: 'Obsolete'));
      await tester.pump();
      expect(catalog.records.single.id, 'A');
    },
  );

  testWidgets('expired pages are refreshed instead of reusing the cache', (
    tester,
  ) async {
    var now = DateTime(2026);
    var calls = 0;
    final catalog = TeamSchoolCatalogController(
      fetch: (_) async {
        calls++;
        return page(id: 'Call$calls');
      },
      currentUid: () => 'user',
      sessionUid: 'user',
      now: () => now,
    );
    addTearDown(catalog.dispose);
    catalog.ensureFresh();
    await tester.pump();
    await tester.pump();
    now = now.add(const Duration(minutes: 3));
    catalog.ensureFresh();
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(catalog.records.single.id, 'Call2');
  });

  testWidgets('old pages are evicted after traversing more than five pages', (
    tester,
  ) async {
    var calls = 0;
    final catalog = TeamSchoolCatalogController(
      fetch: (query) async {
        calls++;
        final cursor = query['cursor'] as String?;
        final index = cursor == null ? 0 : int.parse(cursor.substring(1)) + 1;
        return page(
          id: 'S$index',
          cursor: index < 6 ? 'S$index' : null,
          metrics: query['includeMetrics'] == true,
          includeTotal: query['includeTotal'] == true,
        );
      },
      currentUid: () => 'user',
      sessionUid: 'user',
    );
    addTearDown(catalog.dispose);
    catalog.ensureFresh();
    await tester.pump();
    await tester.pump();
    for (var index = 0; index < 6; index++) {
      await catalog.next();
    }
    expect(calls, 7);
    for (var index = 0; index < 4; index++) {
      await catalog.previous();
    }
    expect(calls, 7);
    await catalog.previous();
    expect(calls, 8);
    expect(catalog.records.single.id, 'S1');
    expect(catalog.error, isNull);
  });

  testWidgets(
    'controls remain usable on a small screen while loading and retrying',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = true;
      final catalog = TeamSchoolCatalogController(
        fetch: (query) async {
          if (fail) throw StateError('private diagnostic');
          return page(role: 'billing_admin', matching: 1);
        },
        currentUid: () => 'user',
        sessionUid: 'user',
      );
      addTearDown(catalog.dispose);
      catalog.ensureFresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolCatalogView(
              controller: catalog,
              builder:
                  (_) => ListView(
                    children: [
                      for (final record in catalog.records) Text(record.id),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Provincia'), findsNothing);
      await tester.enterText(find.byType(TextField), 'san');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'san',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
