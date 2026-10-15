import 'package:edupro/widgets/team_section_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('back returns to panel after the menu replaces its route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.pushReplacementNamed(
                        context,
                        '/red-escolar',
                      ),
                  child: const Text('Abrir Red Escolar'),
                ),
              ),
        ),
        routes: {
          '/panel': (_) => const Scaffold(body: Text('Panel principal')),
          '/red-escolar':
              (context) => Scaffold(
                appBar: AppBar(
                  leading: TeamSectionNavigation.backButton(context),
                ),
                body: const Text('Red Escolar'),
              ),
        },
      ),
    );

    await tester.tap(find.text('Abrir Red Escolar'));
    await tester.pumpAndSettle();
    expect(find.text('Red Escolar'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.text('Red Escolar'))).canPop(),
      isFalse,
    );

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Panel principal'), findsOneWidget);
    expect(find.text('Red Escolar'), findsNothing);
  });

  testWidgets('configuration subsections return to configuration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () =>
                          Navigator.pushReplacementNamed(context, '/seguridad'),
                  child: const Text('Abrir seguridad'),
                ),
              ),
        ),
        routes: {
          '/configuracion': (_) => const Scaffold(body: Text('Configuración')),
          '/seguridad':
              (context) => Scaffold(
                appBar: AppBar(
                  leading: TeamSectionNavigation.backButton(
                    context,
                    targetRoute: '/configuracion',
                  ),
                ),
                body: const Text('Seguridad'),
              ),
        },
      ),
    );

    await tester.tap(find.text('Abrir seguridad'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Configuración'), findsOneWidget);
  });
}
