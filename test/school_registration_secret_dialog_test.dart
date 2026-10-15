import 'dart:async';

import 'package:edupro/widgets/school_registration_secret_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'test-only-registration-key';
  late StreamController<bool> access;
  late List<String> copies;
  late bool allowed;
  late bool clipboardFails;

  setUp(() {
    access = StreamController<bool>.broadcast();
    copies = [];
    allowed = true;
    clipboardFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (clipboardFails) throw PlatformException(code: 'unavailable');
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() async {
    await access.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (_) => SchoolRegistrationSecretDialog(
                          schoolName: 'Colegio de prueba',
                          secret: secret,
                          canAccess: () => allowed,
                          accessChanges: access.stream,
                        ),
                  );
                },
                child: const Text('Abrir'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('secret is masked; only explicit copy writes the clipboard', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(secret), findsNothing);
    expect(copies, isEmpty);
    await tester.tap(find.text('Mostrar clave'));
    await tester.pump();
    expect(find.text(secret), findsOneWidget);
    expect(copies, isEmpty);
    await tester.tap(find.text('Copiar clave'));
    await tester.pumpAndSettle();
    expect(copies, [secret]);
    expect(find.text('Clave copiada.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text(secret), findsNothing);
    expect(copies, [secret]);
  });

  testWidgets('changing window hides the revealed secret', (tester) async {
    await open(tester);
    await tester.tap(find.text('Mostrar clave'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text(secret), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text(secret), findsNothing);
    expect(copies, isEmpty);
  });

  testWidgets('session change closes receipt without copying', (tester) async {
    await open(tester);
    await tester.tap(find.text('Mostrar clave'));
    await tester.pump();
    allowed = false;
    access.add(false);
    await tester.pumpAndSettle();
    expect(find.byType(SchoolRegistrationSecretDialog), findsNothing);
    expect(find.text(secret), findsNothing);
    expect(copies, isEmpty);
  });

  testWidgets(
    'copy checks the current session even before stream notification',
    (tester) async {
      await open(tester);
      allowed = false;
      await tester.tap(find.text('Copiar clave'));
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      expect(find.byType(SchoolRegistrationSecretDialog), findsNothing);
    },
  );

  testWidgets(
    'clipboard failure reveals no secret and allows retry on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      clipboardFails = true;
      await open(tester);
      await tester.tap(find.text('Copiar clave'));
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      expect(find.text(secret), findsNothing);
      expect(
        find.text('No se pudo copiar la clave. Intenta nuevamente.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      clipboardFails = false;
      await tester.tap(find.text('Copiar clave'));
      await tester.pumpAndSettle();
      expect(copies, [secret]);
    },
  );
}
