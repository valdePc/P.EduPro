import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/admin_escolar/widgets/admin_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Standalone back button returns to the previous screen', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => Scaffold(
                                appBar: AppBar(
                                  leading: const AdminBackButton(),
                                  title: const Text('Calendario'),
                                ),
                                body: const Text('Contenido del calendario'),
                              ),
                        ),
                      ),
                  child: const Text('Abrir calendario'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir calendario'));
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(find.text('Contenido del calendario'), findsOneWidget);

    await tester.tap(find.byTooltip('Regresar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir calendario'), findsOneWidget);
    expect(find.text('Contenido del calendario'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final hasPreviousRoute in [false, true]) {
    testWidgets('Embedded back returns to Inicio and preserves state '
        '${hasPreviousRoute ? 'above another route' : 'on the root route'}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        hasPreviousRoute ? const Size(1200, 800) : const Size(390, 844),
      );
      final section = ValueNotifier<int>(0);
      final search = TextEditingController();
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        section.dispose();
        search.dispose();
        await tester.binding.setSurfaceSize(null);
      });

      final pages = <Widget>[
        Scaffold(
          key: const ValueKey('inicio'),
          body: TextField(key: const ValueKey('busqueda'), controller: search),
        ),
        Scaffold(
          appBar: AppBar(
            leading: AdminBackButton(onBack: () => section.value = 0),
            title: const Text('Calendario académico'),
          ),
          body: const Text('Contenido del calendario'),
        ),
      ];
      final shell = AdminShell(
        controller: section,
        pages: pages,
        navItems: [
          NavItem(label: 'Inicio', icon: Icons.home, page: pages[0]),
          NavItem(
            label: 'Calendario académico',
            icon: Icons.calendar_month,
            page: pages[1],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home:
              hasPreviousRoute
                  ? const Scaffold(body: Text('Pantalla anterior'))
                  : shell,
        ),
      );
      if (hasPreviousRoute) {
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => shell),
        );
        await tester.pumpAndSettle();
      }

      await tester.enterText(
        find.byKey(const ValueKey('busqueda')),
        'Primaria',
      );
      section.value = 1;
      await tester.pumpAndSettle();
      expect(find.text('Contenido del calendario'), findsOneWidget);
      expect(find.byKey(const ValueKey('inicio')), findsNothing);

      await tester.tap(find.byTooltip('Regresar'));
      await tester.pumpAndSettle();
      expect(section.value, 0);
      expect(find.byKey(const ValueKey('inicio')), findsOneWidget);
      expect(find.text('Primaria'), findsOneWidget);
      expect(find.text('Pantalla anterior'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), hasPreviousRoute);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Back respects a route that prevents leaving', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Inicio')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder:
            (_) => PopScope(
              canPop: false,
              child: Scaffold(
                appBar: AppBar(leading: const AdminBackButton()),
                body: const Text('Cambios pendientes'),
              ),
            ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Regresar'));
    await tester.pumpAndSettle();
    expect(find.text('Cambios pendientes'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
