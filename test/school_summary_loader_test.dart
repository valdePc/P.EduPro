import 'dart:async';

import 'package:edupro/widgets/school_summary_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cache expires, bounds memory and separates account, role and school',
    () async {
      var now = DateTime.utc(2026, 10, 9);
      final cache = SchoolSummaryCache(maximumEntries: 2, now: () => now);
      var calls = 0;
      Future<Map<String, dynamic>> load() async => {'number': ++calls};
      final first = cache.get('owner:super:A', load);
      expect(identical(cache.get('owner:super:A', load), first), isTrue);
      await first;
      await cache.get('owner:super:B', load);
      await cache.get('staff:operations:A', load);
      expect(calls, 3);
      await cache.get('owner:super:A', load); // bounded cache evicted A
      expect(calls, 4);
      now = now.add(const Duration(minutes: 3));
      await cache.get('owner:super:A', load);
      expect(calls, 5);
      cache.clear();
      await cache.get('owner:super:A', load);
      expect(calls, 6);
    },
  );

  testWidgets(
    'search and parent rebuilds reuse the future; refresh reloads once',
    (tester) async {
      final cache = SchoolSummaryCache();
      var calls = 0;
      var searches = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: Column(
                  children: [
                    Text('Search $searches'),
                    Expanded(
                      child: SchoolSummaryLoader(
                        cacheKey: 'owner:super:A',
                        cache: cache,
                        load: () async => {'totalStudents': ++calls},
                        builder:
                            (_, snapshot) => Text(
                              'Students: ${snapshot.data?['totalStudents'] ?? 'loading'}',
                            ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        rebuild(() => searches++);
        await tester.pumpAndSettle();
      }
      expect(calls, 1);
      expect(find.text('Students: 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('school-summary-refresh')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Students: 2'), findsOneWidget);
    },
  );

  testWidgets(
    'failure is explained and retried explicitly without a request loop',
    (tester) async {
      final cache = SchoolSummaryCache();
      var calls = 0;
      Future<Map<String, dynamic>> load() async {
        if (++calls == 1) throw StateError('synthetic');
        return {'totalStudents': 7};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolSummaryLoader(
              cacheKey: 'owner:super:A',
              cache: cache,
              load: load,
              builder:
                  (_, snapshot) => Text(
                    '${snapshot.data?['totalStudents'] ?? 'No disponible'}',
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('7'), findsOneWidget);
      expect(find.textContaining('No se pudieron cargar'), findsNothing);
    },
  );

  testWidgets(
    'a slow previous school never appears in the newly selected school',
    (tester) async {
      final cache = SchoolSummaryCache();
      final old = Completer<Map<String, dynamic>>();
      var id = 'A';
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: SchoolSummaryLoader(
                  cacheKey: 'owner:super:$id',
                  cache: cache,
                  load:
                      () =>
                          id == 'A' ? old.future : Future.value({'name': 'B'}),
                  builder:
                      (_, snapshot) =>
                          Text('${snapshot.data?['name'] ?? 'loading'}'),
                ),
              );
            },
          ),
        ),
      );
      rebuild(() => id = 'B');
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      old.complete({'name': 'A'});
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    },
  );

  testWidgets('incomplete derived coverage is explained and works on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchoolSummaryLoader(
            cacheKey: 'owner:super:A',
            cache: SchoolSummaryCache(),
            load:
                () async => {
                  'metricsPending': ['teachers'],
                  'activeTeachers': null,
                },
            builder: (_, __) => const Text('Pendiente de cálculo'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('se están calculando'), findsOneWidget);
    expect(find.text('Pendiente de cálculo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
