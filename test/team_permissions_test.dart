import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:edupro/services/team_school_access_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'routes follow the same least-privilege matrix as the internal menus',
    () {
      const permitted = {
        'super_admin': [
          '/panel',
          '/colegios',
          '/analisis-general',
          '/red-escolar',
          '/facturacion',
          '/configuracion',
          '/gestion-accesos',
          '/seguridad',
          '/coleAdmin',
          '/pagos-facturacion',
        ],
        'operations_admin': [
          '/panel',
          '/colegios',
          '/analisis-general',
          '/red-escolar',
        ],
        'support_onboarding': ['/panel', '/colegios'],
        'billing_admin': ['/panel', '/facturacion'],
      };
      final routes =
          permitted.values.expand((value) => value).toSet()..add('/unknown');
      for (final role in [
        ...EquipoEduProRoles.all,
        'denied',
        '',
        'admin_escolar',
        'teacher',
      ]) {
        for (final route in routes) {
          expect(
            EquipoEduProPermissions.canAccessRoute(role, route),
            permitted[role]?.contains(route) ?? false,
            reason: '$role -> $route',
          );
        }
      }
      for (final route in routes) {
        expect(
          EquipoEduProPermissions.canAccessRoute('superadmin', route),
          EquipoEduProPermissions.canAccessRoute('super_admin', route),
        );
      }
    },
  );

  test(
    'operations can create and locate schools but cannot take over accounts or change plans',
    () {
      expect(
        EquipoEduProPermissions.canCreateSchools('operations_admin'),
        isTrue,
      );
      expect(
        EquipoEduProPermissions.canEditSchoolCore('operations_admin'),
        isTrue,
      );
      expect(
        EquipoEduProPermissions.canAssignSchoolAdmin('operations_admin'),
        isFalse,
      );
      expect(
        EquipoEduProPermissions.canChangeSchoolPlansAndLimits(
          'operations_admin',
        ),
        isFalse,
      );
      expect(
        EquipoEduProPermissions.canUseSchoolQuickActions('operations_admin'),
        isFalse,
      );
      for (final role in ['support_onboarding', 'billing_admin', 'unknown']) {
        expect(EquipoEduProPermissions.canCreateSchools(role), isFalse);
        expect(EquipoEduProPermissions.canEditSchoolCore(role), isFalse);
        expect(EquipoEduProPermissions.canAssignSchoolAdmin(role), isFalse);
      }
    },
  );

  test(
    'server catalog timestamps decode without treating limits or coordinates as dates',
    () {
      final result = TeamSchoolRecord.decode({
        'createdAt': 1700000000000,
        'studentsLimit': 150,
        'location': {'latitude': 18.5, 'longitude': -69.9},
        'contact': {'email': 'synthetic@example.test'},
      });
      expect(result['createdAt'], isA<Timestamp>());
      expect(result['studentsLimit'], 150);
      expect(result['location']['latitude'], 18.5);
      expect(result['contact']['email'], 'synthetic@example.test');
    },
  );
}
