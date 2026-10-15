import 'package:edupro/admin_escolar/utils/registration_error_message.dart';
import 'package:edupro/admin_escolar/widgets/registro_equipo_widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Photo permission disables selection and still permits removing a draft photo',
    (tester) async {
      var picked = 0;
      var removed = 0;
      Widget field({required bool canUpload, bool saving = false}) =>
          MaterialApp(
            home: Scaffold(
              body: RegistroEquipoPhotoField(
                canUpload: canUpload,
                saving: saving,
                photoPicked: true,
                onPick: () => picked++,
                onRemove: () => removed++,
              ),
            ),
          );
      await tester.pumpWidget(field(canUpload: true));
      await tester.tap(find.byTooltip('Elegir foto'));
      expect(picked, 1);
      await tester.pumpWidget(field(canUpload: false));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.photo_library_outlined),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('desactivada para el equipo'), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar foto'));
      expect(removed, 1);
      expect(picked, 1);
      await tester.pumpWidget(field(canUpload: true, saving: true));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.photo_library_outlined),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('Provider errors explain recovery without exposing private details', () {
    for (final code in [
      'permission-denied',
      'unauthenticated',
      'unavailable',
      'deadline-exceeded',
      'already-exists',
      'resource-exhausted',
      'invalid-argument',
      'failed-precondition',
      'internal',
      'unknown',
    ]) {
      final error = FirebaseException(
        plugin: 'synthetic-provider',
        code: code,
        message: 'private-path-and-input-must-not-be-shown',
      );
      final text = registrationErrorMessage(error);
      expect(text, isNot(contains(error.message!)));
      expect(text, isNot(contains('synthetic-provider')));
      expect(text, isNotEmpty);
      expect(
        registrationNeedsRenewal(error),
        code == 'permission-denied' || code == 'unauthenticated',
      );
    }
    expect(
      registrationErrorMessage(StateError('private-data')),
      isNot(contains('private-data')),
    );
  });

  testWidgets(
    'Renewal keeps the draft behind the dialog and preserves exact code',
    (tester) async {
      final draft = TextEditingController(text: 'Synthetic draft');
      addTearDown(draft.dispose);
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => Column(
                    children: [
                      TextField(controller: draft),
                      TextButton(
                        onPressed: () async {
                          submitted = await showDialog<String>(
                            context: context,
                            builder: (_) => const RegistroEquipoCodeDialog(),
                          );
                        },
                        child: const Text('Abrir renovación'),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir renovación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renovar acceso'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este campo.'), findsOneWidget);
      final input = find.byType(TextFormField);
      final editor = tester.widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );
      expect(editor.obscureText, isTrue);
      await tester.enterText(input, ' synthetic exact code ');
      await tester.tap(find.text('Renovar acceso'));
      await tester.pumpAndSettle();
      expect(submitted, ' synthetic exact code ');
      expect(draft.text, 'Synthetic draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Creating a grade validates the name and returns the selected name',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      submitted = await showDialog<String>(
                        context: context,
                        builder:
                            (_) => const RegistroEquipoGradeDialog(
                              level: 'Primaria',
                            ),
                      );
                    },
                    child: const Text('Abrir grado'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir grado'));
      await tester.pumpAndSettle();
      expect(find.text('Crear grado de Primaria'), findsOneWidget);
      await tester.tap(find.text('Crear grado'));
      await tester.pumpAndSettle();
      expect(find.text('Completa este campo.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), ' 1 ');
      await tester.tap(find.text('Crear grado'));
      await tester.pumpAndSettle();
      expect(submitted, '1');
      expect(tester.takeException(), isNull);
    },
  );
}
