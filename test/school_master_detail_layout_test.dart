import 'dart:math';

import 'package:edupro/widgets/school_master_detail_layout.dart';
import 'package:edupro/widgets/school_summary_loader.dart';
import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Workspace extends StatefulWidget {
  const _Workspace({super.key});
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final search = TextEditingController();
  final cache = SchoolSummaryCache();
  String? selected = 'A';
  bool removed = false;
  int calls = 0;
  void removeSelectedSchool() => setState(() => removed = true);
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SchoolMasterDetailLayout(
    selectedSchoolId: removed ? null : selected,
    headerBuilder:
        (context, width) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: min(340, width),
              child: TextField(
                controller: search,
                decoration: const InputDecoration(labelText: 'Buscar colegio'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                const Text('Total de escuelas: 2'),
                TextButton(
                  onPressed: () {},
                  child: const Text('Nueva escuela'),
                ),
                const Text('Activas: 2'),
                const Text('Suspendidas: 0'),
              ],
            ),
            const Text('Mostrando 2 de 2 escuelas'),
          ],
        ),
    listBuilder:
        (context, openDetail) =>
            removed
                ? const Center(child: Text('Sin resultados'))
                : ListView(
                  children: [
                    for (final id in ['A', 'B'])
                      ListTile(
                        key: ValueKey('select-$id'),
                        title: Text('Colegio $id'),
                        selected: selected == id,
                        onTap: () {
                          setState(() => selected = id);
                          openDetail();
                        },
                      ),
                  ],
                ),
    detailBuilder:
        (context) => SchoolSummaryLoader(
          cacheKey: selected!,
          cache: cache,
          load: () async {
            calls++;
            return {};
          },
          builder:
              (context, snapshot) => ListView(
                children: [
                  Text('Ficha $selected'),
                  const SchoolDetailRow(
                    label: 'Correo administrativo principal',
                    value: 'administracion.colegio.san.rafael@example.test',
                  ),
                  const SchoolDetailRow(
                    label: 'Dirección completa',
                    value: 'Calle Domingo Ponge, Boca Chica, Santo Domingo',
                  ),
                ],
              ),
        ),
  );
}

void main() {
  testWidgets('mobile list and detail fit narrow screens and enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [
      const Size(320, 640),
      const Size(360, 640),
      const Size(600, 280),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final state = GlobalKey<_WorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Colegios'),
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: SizedBox(height: 48),
                ),
              ),
              body: _Workspace(key: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ficha A'), findsNothing);
      expect(
        state.currentState!.calls,
        0,
        reason: 'Do not fetch a hidden mobile detail',
      );
      await tester.enterText(find.byType(TextField), 'San Rafael');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('select-B')),
        60,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-B')));
      await tester.pumpAndSettle();
      expect(find.text('Ficha B'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('school-workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('San Rafael'), findsOneWidget);
      expect(state.currentState!.selected, 'B');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'layout uses the remaining width after a sidebar and survives resizing',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1440, 760));
      final state = GlobalKey<_WorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 240),
                Expanded(child: _Workspace(key: state)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Colegio A'), findsOneWidget);
      expect(find.text('Ficha A'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('select-B')));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(1000, 760));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('school-workspace-back')),
        findsOneWidget,
      );
      expect(find.text('Ficha B'), findsOneWidget);
      expect(find.text('Colegio A'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('school-workspace-back')));
      await tester.pumpAndSettle();
      expect(find.text('Colegio A'), findsOneWidget);
      expect(find.text('Ficha B'), findsNothing);
      await tester.binding.setSurfaceSize(const Size(1440, 760));
      await tester.pumpAndSettle();
      expect(find.text('Ficha B'), findsOneWidget);
      expect(
        state.currentState!.calls,
        2,
        reason: 'Resizing reuses cached summaries',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing the selected school returns to the list without stale detail',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 640));
      final state = GlobalKey<_WorkspaceState>();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _Workspace(key: state))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-A')));
      await tester.pumpAndSettle();
      state.currentState!.removeSelectedSchool();
      await tester.pumpAndSettle();
      expect(find.text('Sin resultados'), findsOneWidget);
      expect(find.text('Ficha A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system back closes the compact detail before leaving the section',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 640));
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Inicio')),
          routes: {'/colegios': (_) => const Scaffold(body: _Workspace())},
        ),
      );
      navigator.currentState!.pushNamed('/colegios');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-A')));
      await tester.pumpAndSettle();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Colegio A'), findsOneWidget);
      expect(find.text('Ficha A'), findsNothing);
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsOneWidget);
    },
  );

  testWidgets('field values stack below labels at narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: SchoolDetailRow(
              label: 'Contacto',
              value: 'correo@example.test',
            ),
          ),
        ),
      ),
    );
    final label = tester.getTopLeft(find.text('Contacto'));
    final value = tester.getTopLeft(find.text('correo@example.test'));
    expect(value.dy, greaterThan(label.dy));
    expect(value.dx, label.dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report metrics reflow at narrow widths with enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: SchoolMetricGrid(
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Tareas publicadas: 100000'),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Asignaturas cubiertas: 100000'),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Presentes: 100000'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final tasks = tester.getTopLeft(find.text('Tareas publicadas: 100000'));
    final subjects = tester.getTopLeft(
      find.text('Asignaturas cubiertas: 100000'),
    );
    expect(subjects.dy, greaterThan(tasks.dy));
    expect(subjects.dx, tasks.dx);
  });

  testWidgets(
    'the real analysis header scrolls without unbounded Expanded errors',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final width in [320.0, 720.0, 1400.0]) {
        await tester.binding.setSurfaceSize(Size(width, 640));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SchoolAnalysisHeader(
                    title: 'Colegio San Rafael de Boca Chica',
                    subtitle:
                        'Reporte y análisis de todos los niveles del centro educativo',
                    createdAt: DateTime(2026, 10, 8),
                    attendanceRate: 0.955,
                    totalStudents: 1000000,
                    totalTeachers: 100000,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Colegio San Rafael de Boca Chica'), findsOneWidget);
      }
    },
  );
}
