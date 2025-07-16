import 'package:flutter_test/flutter_test.dart';
import 'package:edupro/main.dart';

void main() {
  testWidgets('Smoke test de la app', (WidgetTester tester) async {
    // Arranca la app real:
    await tester.pumpWidget(const EduProApp());

    // Verifica que el título aparezca en pantalla
    expect(find.text('EduPro Admin'), findsOneWidget);
  });
}
