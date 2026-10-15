import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:edupro/utils/safe_external_uri.dart';
import 'package:edupro/utils/school_access_link.dart';
import 'package:edupro/utils/school_document_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reserved school documents are excluded without hiding real school IDs',
    () {
      final ids = [
        'ValMichapp_admin_ABC',
        'valmichapp_admin_ABC',
        'VALMICHAPP_ADMIN_ABC',
        'eduproapp_admin_ABC',
        'EduProApp_Admin_ABC',
        'EDUPROAPP_ADMIN_ABC',
        'ABC-123',
        'school_eduproapp_admin_ABC',
        'ValMichapp_admin',
        'EduPro_SanRafael',
      ];
      final visible =
          ids.where((id) => !isInternalSchoolDocumentId(id)).toList();
      expect(visible, [
        'ABC-123',
        'school_eduproapp_admin_ABC',
        'ValMichapp_admin',
        'EduPro_SanRafael',
      ]);
      // Filtering must not lowercase real IDs used to open Firestore documents.
      expect(visible.last, 'EduPro_SanRafael');
    },
  );

  test('Unknown team roles cannot inherit privileged permissions', () {
    for (final role in ['', 'teacher', 'admin', 'null', 'made_up']) {
      expect(EquipoEduProRoles.normalize(role), EquipoEduProRoles.denied);
      expect(EquipoEduProPermissions.canViewSchools(role), isFalse);
      expect(EquipoEduProPermissions.canCreateSchools(role), isFalse);
      expect(EquipoEduProPermissions.canEditSchoolCore(role), isFalse);
      expect(EquipoEduProPermissions.canUseSchoolQuickActions(role), isFalse);
      expect(
        EquipoEduProPermissions.canChangeSchoolPlansAndLimits(role),
        isFalse,
      );
      expect(EquipoEduProPermissions.canViewBilling(role), isFalse);
      expect(EquipoEduProPermissions.canViewInsights(role), isFalse);
      expect(EquipoEduProPermissions.canViewSensitiveConfig(role), isFalse);
      expect(EquipoEduProRoles.defaultRoute(role), '/login');
    }
    expect(EquipoEduProRoles.normalize(null), EquipoEduProRoles.denied);
    expect(
      EquipoEduProRoles.normalize(' SUPERADMIN '),
      EquipoEduProRoles.superAdmin,
    );
    expect(EquipoEduProPermissions.canViewBilling('billing_admin'), isTrue);
    expect(EquipoEduProPermissions.canViewSchools('billing_admin'), isFalse);
    expect(
      EquipoEduProPermissions.canViewSensitiveConfig('super_admin'),
      isTrue,
    );
  });

  test(
    'Document links require HTTPS and reject executable or local schemes',
    () {
      for (final url in [
        '',
        'javascript:alert(1)',
        'data:text/html,test',
        'file:///etc/passwd',
        'intent://app',
        '//example.org/doc.pdf',
        '/relative.pdf',
        'http://example.org/doc.pdf',
        'https://',
        'https://user:pass@example.org',
        'https://example.org/\nunsafe',
        r'https://example.org\@other.org',
      ]) {
        expect(safeExternalDocumentUri(url), isNull, reason: url);
      }
      expect(
        safeExternalDocumentUri(
          ' https://example.org/doc.pdf?q=ok#page=1 ',
        )?.host,
        'example.org',
      );
    },
  );

  test(
    'School links preserve tenant IDs and reject paths across boundaries',
    () {
      for (final link in [
        'https://example.org/#/eduproapp/school-1/docentes',
        '/eduproapp/school-1/docentes',
        'eduproapp://school-1/docentes',
        'valmichapp://school-1/docentes',
      ]) {
        final target = SchoolAccessLink.parse(link);
        expect(target?.schoolId, 'school-1');
        expect(target?.module, 'docentes');
      }
      for (final link in [
        'javascript:/eduproapp/school-1/docentes',
        '/eduproapp/school-1%2fother/docentes',
        '/eduproapp/school-1/unknown',
        '/eduproapp/school-1/docentes/extra',
        '/eduproapp/%00/docentes',
        'https://user:pass@example.org/eduproapp/school-1/docentes',
      ]) {
        expect(SchoolAccessLink.parse(link), isNull, reason: link);
      }
    },
  );
}
