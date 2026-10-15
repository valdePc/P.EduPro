import 'package:edupro/models/school_administrator_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'assigned administrator without name displays canonical email and assignment',
    () {
      final details = SchoolAdministratorDetails.fromMap({
        'adminAssigned': true,
        'adminName': '  ',
        'adminEmail': '  admin@example.test  ',
      });
      expect(details.name, 'Administrador asignado');
      expect(details.emailLabel, 'admin@example.test');
      expect(details.assigned, isTrue);
    },
  );

  test(
    'missing email is explained without implying that assignment failed',
    () {
      final details = SchoolAdministratorDetails.fromMap({
        'adminAssigned': true,
        'adminName': 'Nombre del administrador',
        'adminEmail': '',
      });
      expect(details.name, 'Nombre del administrador');
      expect(details.emailLabel, 'Correo no registrado');
      final unassigned = SchoolAdministratorDetails.fromMap({
        'adminAssigned': false,
      });
      expect(unassigned.name, 'No asignado');
      expect(unassigned.emailLabel, 'Sin asignar');
    },
  );

  test(
    'legacy summaries infer assignment from email without showing empty values',
    () {
      final details = SchoolAdministratorDetails.fromMap({
        'adminName': 'No asignado',
        'adminEmail': 'admin@example.test',
      });
      expect(details.name, 'Administrador asignado');
      expect(details.emailLabel, 'admin@example.test');
      expect(SchoolAdministratorDetails.fromMap({}).emailLabel, 'Sin asignar');
    },
  );
}
