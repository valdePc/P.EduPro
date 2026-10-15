import 'package:edupro/admin_escolar/widgets/admin_notification_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Notifications fit width $width with text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.binding.setSurfaceSize(null);
        });
        var opened = false;
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
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      const AdminNotificationHero(
                        schoolName: 'Escuela de prueba',
                      ),
                      const SizedBox(height: 12),
                      AdminNotificationHistoryCard(
                        title: 'Reunión de familias de todos los grados',
                        body:
                            'El próximo viernes tendremos una reunión para compartir el calendario escolar y responder preguntas.',
                        date: '14/10/2026 • 10:30 AM',
                        target: 'Todos los docentes',
                        include: 'Incluye: Docentes + Alumnos',
                        readCount: 12,
                        onTap: () => opened = true,
                      ),
                      const SizedBox(height: 12),
                      const AdminNotificationEmptyState(
                        title: 'Aún no hay notificaciones',
                        description: 'Aquí aparecerán los avisos enviados.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Reunión de familias de todos los grados'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reunión de familias de todos los grados'));
        expect(opened, isTrue);
        await tester.scrollUntilVisible(
          find.text('Aún no hay notificaciones'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Delete dialog requires an explicit confirmation', (
    tester,
  ) async {
    final decisions = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    decisions.add(
                      await showDialog<bool>(
                        context: context,
                        builder: (_) => const AdminNotificationDeleteDialog(),
                      ),
                    );
                  },
                  child: const Text('Abrir confirmación'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir confirmación'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar notificación'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);

    await tester.tap(find.text('Abrir confirmación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar aviso'));
    await tester.pumpAndSettle();
    expect(decisions, [false, true]);
  });
}
