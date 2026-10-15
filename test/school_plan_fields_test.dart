import 'package:edupro/widgets/school_plan_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  String visibleText(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets(
    'changing plans updates visible limits and the submitted values',
    (tester) async {
      final controller = SchoolPlanController();
      final form = GlobalKey<FormState>();
      SchoolPlanValues? submitted;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: Column(
                children: [
                  SchoolPlanSelector(controller: controller, editable: true),
                  SchoolPlanLimitFields(controller: controller, editable: true),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        submitted = controller.readValues();
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final choice in [
        ('Premium', 'premium', '5', '60', '900'),
        ('Plus', 'plus', '3', '25', '300'),
        ('Enterprise', 'enterprise', '10', '150', '3000'),
        ('Base', 'base', '1', '10', '150'),
      ]) {
        await select(tester, choice.$1);
        expect(visibleText(tester, 'school-admins-limit'), choice.$3);
        expect(visibleText(tester, 'school-teachers-limit'), choice.$4);
        expect(visibleText(tester, 'school-students-limit'), choice.$5);
        await tester.tap(find.text('Guardar'));
        expect(submitted!.planTier, choice.$2);
        expect('${submitted!.adminsLimit}', choice.$3);
        expect('${submitted!.teachersLimit}', choice.$4);
        expect('${submitted!.studentsLimit}', choice.$5);
      }

      await tester.enterText(
        find.byKey(const ValueKey('school-admins-limit')),
        '7',
      );
      await tester.enterText(
        find.byKey(const ValueKey('school-teachers-limit')),
        '75',
      );
      await tester.enterText(
        find.byKey(const ValueKey('school-students-limit')),
        '1200',
      );
      await tester.tap(find.text('Guardar'));
      expect(submitted!.adminsLimit, 7);
      expect(submitted!.teachersLimit, 75);
      expect(submitted!.studentsLimit, 1200);
      await select(tester, 'Premium');
      expect(visibleText(tester, 'school-students-limit'), '900');
      await tester.tap(find.text('Guardar'));
      expect(submitted!.studentsLimit, 900);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid or cleared limits block submission instead of retaining previous numbers',
    (tester) async {
      final controller = SchoolPlanController();
      final form = GlobalKey<FormState>();
      var submissions = 0;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: Column(
                children: [
                  SchoolPlanLimitFields(controller: controller, editable: true),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        controller.readValues();
                        submissions++;
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final invalid in ['', '0', '-1', '1.5', '1000001']) {
        await tester.enterText(
          find.byKey(const ValueKey('school-students-limit')),
          invalid,
        );
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        expect(submissions, 0);
        expect(controller.readValues, throwsFormatException);
      }
      await tester.enterText(
        find.byKey(const ValueKey('school-students-limit')),
        '500',
      );
      await tester.tap(find.text('Guardar'));
      expect(submissions, 1);
      expect(controller.readValues().studentsLimit, 500);
    },
  );

  testWidgets(
    'operations sees Base with disabled plan selection and read-only limits',
    (tester) async {
      final controller = SchoolPlanController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SchoolPlanSelector(controller: controller, editable: false),
                SchoolPlanLimitFields(controller: controller, editable: false),
              ],
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      for (final key in [
        'school-admins-limit',
        'school-teachers-limit',
        'school-students-limit',
      ]) {
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
      }
      expect(controller.readValues().planTier, 'base');
      expect(controller.readValues().studentsLimit, 150);
      expect(tester.takeException(), isNull);
    },
  );
}
