import 'package:edupro/admin_escolar/widgets/admin_chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Chat fits width $width with text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        final controller = TextEditingController();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
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
                      const AdminChatHero(schoolName: 'Escuela de prueba'),
                      const SizedBox(height: 12),
                      AdminChatConversationTile(
                        title: 'María Fernanda de los Santos Rodríguez',
                        subtitle: const Text(
                          '3 grados asignados · Cuenta activa',
                        ),
                        onTap: () => opened = true,
                      ),
                      const AdminChatMessageBubble(
                        isMe: false,
                        sender:
                            'Docente · María Fernanda de los Santos Rodríguez',
                        timeLabel: '10:35',
                        child: Text(
                          'Este mensaje de prueba contiene texto suficiente para comprobar que se adapta a pantallas pequeñas.',
                        ),
                      ),
                      const AdminChatMessageBubble(
                        key: ValueKey('last-message'),
                        isMe: true,
                        timeLabel: '10:36',
                        child: Text(
                          'Respuesta de administración con información para el equipo docente.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const AdminChatEmptyState(
                        title: 'Inicia la conversación',
                        description:
                            'Escribe un mensaje o comparte un archivo con el equipo.',
                      ),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: AdminChatComposer(
                controller: controller,
                sending: false,
                onSend: () {},
                onImage: () async {},
                onFile: () async {},
              ),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('María Fernanda de los Santos Rodríguez'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('María Fernanda de los Santos Rodríguez'));
        expect(opened, isTrue);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('last-message')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(find.byTooltip('Enviar mensaje'), findsOneWidget);
        expect(find.byTooltip('Adjuntar imagen o archivo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Composer sends typed text and opens both attachment actions', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    final sent = <String>[];
    var images = 0;
    var files = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AdminChatComposer(
            controller: controller,
            sending: false,
            onSend: () => sent.add(controller.text),
            onImage: () async {
              images++;
            },
            onFile: () async {
              files++;
            },
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.send_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Aviso del equipo');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar mensaje'));
    expect(sent, ['Aviso del equipo']);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sent, ['Aviso del equipo', 'Aviso del equipo']);

    await tester.tap(find.byTooltip('Adjuntar imagen o archivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imagen'));
    await tester.pumpAndSettle();
    expect(images, 1);
    await tester.tap(find.byTooltip('Adjuntar imagen o archivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archivo'));
    await tester.pumpAndSettle();
    expect(files, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Composer protects a draft and prevents duplicate actions while sending',
    (tester) async {
      final controller = TextEditingController(text: 'Mensaje pendiente');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      var sent = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AdminChatComposer(
              controller: controller,
              sending: true,
              onSend: () => sent++,
              onImage: () async {},
              onFile: () async {},
            ),
          ),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.byTooltip('Enviando mensaje'));
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, 0);
      expect(controller.text, 'Mensaje pendiente');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Bubbles adapt to their container on a large screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: AdminChatMessageBubble(
                isMe: false,
                sender: 'Docente de prueba',
                timeLabel: '09:15',
                child: Text(
                  'Mensaje largo que debe permanecer dentro de un panel estrecho aunque la pantalla completa sea grande.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bubbleBounds = tester.getRect(find.byType(AdminChatMessageBubble));
    final textBounds = tester.getRect(
      find.text(
        'Mensaje largo que debe permanecer dentro de un panel estrecho aunque la pantalla completa sea grande.',
      ),
    );
    expect(textBounds.left, greaterThanOrEqualTo(bubbleBounds.left));
    expect(textBounds.right, lessThanOrEqualTo(bubbleBounds.right));
    expect(tester.takeException(), isNull);
  });
}
