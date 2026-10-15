import 'dart:ui' show Tristate;

import 'package:edupro/admin_escolar/widgets/registro_equipo_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Registration layout fits $width at text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.binding.setSurfaceSize(null);
        });
        var selected = '';
        var exited = false;
        await tester.pumpWidget(
          MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
            home: Scaffold(
              appBar: AppBar(
                backgroundColor: RegistroEquipoColors.blue,
                foregroundColor: Colors.white,
                title: const Text('Registro'),
                actions: [
                  RegistroEquipoExitAction(
                    compact: width < 520,
                    onPressed: () => exited = true,
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      const RegistroEquipoHero(
                        schoolName: 'Escuela de prueba',
                        level: 'Primaria',
                      ),
                      const SizedBox(height: 16),
                      RegistroEquipoChoiceWrap(
                        choices: [
                          for (final level in [
                            'Inicial',
                            'Primaria',
                            'Secundaria',
                          ])
                            RegistroEquipoChoiceTile(
                              label: level,
                              icon: Icons.school_outlined,
                              selected: level == 'Primaria',
                              accent: RegistroEquipoColors.blue,
                              onTap: () => selected = level,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const RegistroEquipoFieldRow(
                        fields: [
                          TextField(
                            decoration: InputDecoration(labelText: 'Nombre'),
                          ),
                          TextField(
                            decoration: InputDecoration(labelText: 'Apellidos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const RegistroEquipoFieldRow(
                        fields: [
                          TextField(
                            decoration: InputDecoration(labelText: 'Matrícula'),
                          ),
                          TextField(
                            decoration: InputDecoration(labelText: 'Tanda'),
                          ),
                          TextField(
                            decoration: InputDecoration(labelText: 'Grado'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (scale == 1.0) {
          final heroHeight =
              tester.getSize(find.byType(RegistroEquipoHero)).height;
          expect(heroHeight, lessThan(110));
        }
        await tester.scrollUntilVisible(
          find.text('Secundaria'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final selectedOption = tester.getSemantics(
          find.byType(RegistroEquipoChoiceTile).at(1),
        );
        expect(selectedOption.flagsCollection.isSelected, Tristate.isTrue);
        await tester.tap(find.text('Secundaria'));
        expect(selected, 'Secundaria');
        await tester.scrollUntilVisible(
          find.text('Grado'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(find.byType(RegistroEquipoExitAction));
        expect(exited, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Desktop header scrolls with the form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RegistroEquipoDesktopLayout(
            header: RegistroEquipoHero(
              schoolName: 'Escuela de prueba',
              level: 'Primaria',
            ),
            form: SizedBox(height: 1200, child: Text('Formulario')),
            list: SizedBox(height: 1200, child: Text('Listado')),
          ),
        ),
      ),
    );
    final formList = find.byKey(const ValueKey('registro-form-scroll'));
    final resultList = find.byKey(const ValueKey('registro-list-scroll'));
    expect(
      find.descendant(of: formList, matching: find.byType(RegistroEquipoHero)),
      findsOneWidget,
    );
    await tester.drag(formList, const Offset(0, -300));
    await tester.pumpAndSettle();
    final formScroll = tester.state<ScrollableState>(
      find.descendant(of: formList, matching: find.byType(Scrollable)),
    );
    final resultScroll = tester.state<ScrollableState>(
      find.descendant(of: resultList, matching: find.byType(Scrollable)),
    );
    expect(formScroll.position.pixels, greaterThan(0));
    expect(resultScroll.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Exit dialog cancels or confirms leaving a draft', (
    tester,
  ) async {
    final decisions = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async => decisions.add(
                        await showDialog<bool>(
                          context: context,
                          builder: (_) => const RegistroEquipoExitDialog(),
                        ),
                      ),
                  child: const Text('Abrir salida'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir salida'));
    await tester.pumpAndSettle();
    expect(find.text('Salir del formulario'), findsOneWidget);
    await tester.tap(find.text('Continuar registrando'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);

    await tester.tap(find.text('Abrir salida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir'));
    await tester.pumpAndSettle();
    expect(decisions, [false, true]);
  });
}
