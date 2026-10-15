import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:edupro/widgets/school_plan_edit_dialog.dart';
import 'package:edupro/widgets/school_plan_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const reasonField = ValueKey('school-plan-reason');
const studentField = ValueKey('school-students-limit');
const saveButton = ValueKey('school-plan-save');

Future<void> mountEditor(
  WidgetTester tester,
  Future<bool> Function(
    BuildContext context,
    SchoolPlanValues values,
    String reason,
  )
  save,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder:
                      (_) => SchoolPlanEditDialog(
                        schoolName: 'Colegio de prueba',
                        initialValues: const SchoolPlanValues(
                          'plus',
                          4,
                          30,
                          400,
                        ),
                        onSave:
                            (values, reason) => save(context, values, reason),
                        errorMessage:
                            (error) =>
                                error is FirebaseFunctionsException
                                    ? 'Error controlado: ${error.code}'
                                    : 'No se pudo confirmar el cambio.',
                      ),
                );
              },
              child: const Text('Editar'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Editar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'validates justification and limits before requesting verification',
    (tester) async {
      var requests = 0;
      await mountEditor(tester, (_, values, reason) async {
        requests++;
        expect(values.planTier, 'plus');
        expect(values.adminsLimit, 4);
        expect(values.teachersLimit, 30);
        expect(values.studentsLimit, 450);
        expect(reason, 'Ampliación aprobada para el próximo curso');
        return true;
      });
      expect(
        tester.widget<TextFormField>(find.byKey(studentField)).controller!.text,
        '400',
      );
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.enterText(
        find.byKey(reasonField),
        '  Ampliación aprobada para el próximo curso  ',
      );
      await tester.enterText(find.byKey(studentField), '1000001');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.enterText(find.byKey(studentField), '450');
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.byType(SchoolPlanEditDialog), findsNothing);
    },
  );

  for (final code in ['permission-denied', 'unavailable']) {
    testWidgets(
      '$code preserves the draft, allows retry and blocks duplicate saves',
      (tester) async {
        var requests = 0;
        final first = Completer<bool>();
        await mountEditor(tester, (_, values, reason) {
          requests++;
          expect(values.studentsLimit, 500);
          expect(reason, 'Cambio autorizado por ampliación de matrícula');
          return requests == 1 ? first.future : Future.value(true);
        });
        await tester.enterText(find.byKey(studentField), '500');
        await tester.enterText(
          find.byKey(reasonField),
          'Cambio autorizado por ampliación de matrícula',
        );
        await tester.tap(find.byKey(saveButton));
        await tester.pump();
        await tester.tap(find.byKey(saveButton));
        await tester.pump();
        expect(requests, 1);
        expect(find.text('Guardando…'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
              .onPressed,
          isNull,
        );
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(SchoolPlanEditDialog), findsOneWidget);
        first.completeError(
          FirebaseFunctionsException(code: code, message: 'Synthetic failure'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Error controlado: $code'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(studentField))
              .controller!
              .text,
          '500',
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(reasonField))
              .controller!
              .text,
          'Cambio autorizado por ampliación de matrícula',
        );
        await tester.tap(find.byKey(saveButton));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(find.byType(SchoolPlanEditDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelled nested identity confirmation retains changes and justification',
    (tester) async {
      await mountEditor(tester, (context, _, __) async {
        ModalRoute<bool>? confirmation;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            confirmation = ModalRoute.of<bool>(ctx);
            return AlertDialog(
              title: const Text('Confirma tu identidad'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar verificación'),
                ),
              ],
            );
          },
        );
        await confirmation?.completed;
        return confirmed == true;
      });
      await tester.enterText(
        find.byKey(reasonField),
        'Cambio autorizado por ampliación de matrícula',
      );
      await tester.tap(find.byKey(saveButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancelar verificación'));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolPlanEditDialog), findsOneWidget);
      expect(
        find.text('No se completó la confirmación. Tus cambios siguen aquí.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(find.byKey(reasonField)).controller!.text,
        'Cambio autorizado por ampliación de matrícula',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor and inline error remain usable on a small mobile screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountEditor(tester, (_, __, ___) async => false);
      await tester.ensureVisible(find.byKey(reasonField));
      await tester.enterText(
        find.byKey(reasonField),
        'Cambio aprobado para el próximo curso',
      );
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
