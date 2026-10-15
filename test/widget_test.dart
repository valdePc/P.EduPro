import 'package:edupro/screens/acceso_enlace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Access form fits a small screen and rejects an invalid link',
      (tester) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AccesoEnlaceScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Enlace de acceso'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enlace inv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
