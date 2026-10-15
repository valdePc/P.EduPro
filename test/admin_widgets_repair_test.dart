import 'package:edupro/admin_escolar/widgets/curriculum_progress_chart.dart';
import 'package:edupro/admin_escolar/widgets/teacher_card_widget.dart';
import 'package:edupro/models/curricular_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Curricular progress reads and preserves report values', () {
    final progress = CurricularProgress.fromMap({
      'period': 'P1',
      'completed': 7,
      'target': '10',
    });
    expect(progress.period, 'P1');
    expect(progress.completed, 7);
    expect(progress.target, 10);
    expect(
      CurricularProgress.fromMap(progress.toMap()).toMap(),
      progress.toMap(),
    );
  });

  testWidgets(
    'Teacher card fits narrow screens and opens the selected teacher',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TeacherCard(
              name: 'Ana Pérez',
              level: 'Primaria',
              grade: '3.º',
              curriculumScore: 87,
              attendanceRate: 95,
              status: TeacherStatus.attention,
              onClick: () => selected = true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('87%'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);
      await tester.tap(find.text('Ana Pérez'));
      expect(selected, isTrue);
    },
  );

  testWidgets('Curriculum chart shows empty and populated states', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CurriculumProgressChart(data: [])),
      ),
    );
    expect(find.text('No hay datos de avance curricular.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CurriculumProgressChart(
            data: [
              CurricularProgress(period: 'P1', completed: 7, target: 10),
              CurricularProgress(period: 'P2', completed: 8, target: 10),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Avance curricular por período'), findsOneWidget);
    expect(find.byType(CurriculumProgressChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Many periods remain scrollable on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CurriculumProgressChart(data: [
          for (var index = 1; index <= 12; index++)
            CurricularProgress(period: 'P$index', completed: index.toDouble(), target: 12),
        ]),
      ),
    ));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
