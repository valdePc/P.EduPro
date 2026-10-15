import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:edupro/widgets/school_creation_dialog.dart';
import 'package:edupro/widgets/school_plan_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const submit = ValueKey('school-create-submit');

class _Draft {
  final plan = SchoolPlanController();
  final navigator = GlobalKey<NavigatorState>();
  String name = '';
  String email = '';
  bool? result;
}

Future<_Draft> _mountDialog(
  WidgetTester tester,
  Future<bool> Function(BuildContext context, _Draft draft) create,
) async {
  final draft = _Draft();
  final form = GlobalKey<FormState>();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    draft.plan.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: draft.navigator,
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  draft.result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (_) => SchoolCreationDialog(
                          formKey: form,
                          onCreate: () => create(context, draft),
                          errorMessage:
                              (error) =>
                                  'No se pudo guardar (${(error as FirebaseFunctionsException).code}). Tus datos siguen aquí.',
                          contentBuilder:
                              (context, saving) => SingleChildScrollView(
                                child: Form(
                                  key: form,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextFormField(
                                        key: const ValueKey('draft-name'),
                                        decoration: const InputDecoration(
                                          labelText: 'Nombre',
                                        ),
                                        onChanged:
                                            (value) => draft.name = value,
                                        validator:
                                            (value) =>
                                                (value ?? '').isEmpty
                                                    ? 'Requerido'
                                                    : null,
                                      ),
                                      TextFormField(
                                        key: const ValueKey('draft-email'),
                                        decoration: const InputDecoration(
                                          labelText: 'Correo',
                                        ),
                                        onChanged:
                                            (value) => draft.email = value,
                                      ),
                                      SchoolPlanSelector(
                                        controller: draft.plan,
                                        editable: !saving,
                                      ),
                                      SchoolPlanLimitFields(
                                        controller: draft.plan,
                                        editable: !saving,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return draft;
}

String _visibleText(WidgetTester tester, String key) =>
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

void main() {
  for (final code in [
    'permission-denied',
    'unavailable',
    'failed-precondition',
  ]) {
    testWidgets(
      '$code preserves the draft, blocks concurrent submissions and permits retry',
      (tester) async {
        final attempts = <Completer<bool>>[];
        final sent = <(String, String, String, int)>[];
        final draft = await _mountDialog(tester, (context, draft) {
          final values = draft.plan.readValues();
          sent.add((
            draft.name,
            draft.email,
            values.planTier,
            values.studentsLimit,
          ));
          final pending = Completer<bool>();
          attempts.add(pending);
          return pending.future;
        });
        await tester.enterText(
          find.byKey(const ValueKey('draft-name')),
          'Colegio San Rafael',
        );
        await tester.enterText(
          find.byKey(const ValueKey('draft-email')),
          'synthetic@example.test',
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Premium').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('school-students-limit')),
          '1200',
        );

        await tester.tap(find.byKey(submit));
        await tester.tap(find.byKey(submit));
        await tester.pump();
        expect(attempts.length, 1);
        expect(find.text('Guardando…'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(submit)).onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('school-create-cancel')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<ExcludeFocus>(find.byType(ExcludeFocus).first)
              .excluding,
          isTrue,
        );
        await draft.navigator.currentState!.maybePop();
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(find.text('Nuevo colegio'), findsOneWidget);

        attempts.first.completeError(
          FirebaseFunctionsException(code: code, message: 'Synthetic failure'),
        );
        await tester.pumpAndSettle();
        expect(draft.result, isNull);
        expect(find.textContaining('Tus datos siguen aquí'), findsOneWidget);
        expect(_visibleText(tester, 'draft-name'), 'Colegio San Rafael');
        expect(_visibleText(tester, 'draft-email'), 'synthetic@example.test');
        expect(_visibleText(tester, 'school-students-limit'), '1200');
        expect(draft.plan.planTier, 'premium');
        expect(find.text('Reintentar'), findsOneWidget);

        await tester.tap(find.byKey(submit));
        await tester.pump();
        expect(attempts.length, 2);
        expect(sent[1], sent[0]);
        attempts.last.complete(true);
        await tester.pumpAndSettle();
        expect(draft.result, isTrue);
        expect(find.text('Nuevo colegio'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelled second factor keeps the form and a later verification can succeed',
    (tester) async {
      var creations = 0;
      final draft = await _mountDialog(tester, (context, draft) async {
        Future<dynamic>? transition;
        final verified = await showDialog<bool>(
          context: context,
          builder: (context) {
            transition = ModalRoute.of(context)?.completed;
            return AlertDialog(
              title: const Text('Segundo factor'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar verificación'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Verificar'),
                ),
              ],
            );
          },
        );
        await transition;
        if (verified != true) return false;
        creations++;
        return true;
      });
      await tester.enterText(
        find.byKey(const ValueKey('draft-name')),
        'Colegio de prueba',
      );
      await tester.tap(find.byKey(submit));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Segundo factor'), findsOneWidget);
      await tester.tap(find.text('Cancelar verificación'));
      await tester.pumpAndSettle();
      expect(creations, 0);
      expect(_visibleText(tester, 'draft-name'), 'Colegio de prueba');
      expect(draft.result, isNull);
      await tester.tap(find.byKey(submit));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(draft.result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid data never starts a request and the draft remains editable',
    (tester) async {
      var requests = 0;
      final draft = await _mountDialog(tester, (context, draft) async {
        requests++;
        return true;
      });
      await tester.tap(find.byKey(submit));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.text('Requerido'), findsOneWidget);
      expect(draft.result, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('draft-name')),
        'Colegio válido',
      );
      await tester.tap(find.byKey(submit));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(draft.result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('error and retry fit a small screen without losing the draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = await _mountDialog(tester, (context, draft) async {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Synthetic network failure',
      );
    });
    await tester.enterText(
      find.byKey(const ValueKey('draft-name')),
      'Colegio móvil',
    );
    await tester.tap(find.byKey(submit));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('Tus datos siguen aquí'), findsOneWidget);
    expect(_visibleText(tester, 'draft-name'), 'Colegio móvil');
    expect(draft.result, isNull);
    expect(tester.takeException(), isNull);
  });
}
