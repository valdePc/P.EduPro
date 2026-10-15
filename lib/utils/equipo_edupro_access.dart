import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/app_check_bootstrap.dart';
import 'package:flutter/foundation.dart';

class EquipoEduProRoles {
  static const String denied = 'denied';
  static const String superAdmin = 'super_admin';
  static const String operationsAdmin = 'operations_admin';
  static const String supportOnboarding = 'support_onboarding';
  static const String billingAdmin = 'billing_admin';

  static const List<String> all = [
    superAdmin,
    operationsAdmin,
    supportOnboarding,
    billingAdmin,
  ];

  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'superadmin':
        return superAdmin;
      case superAdmin:
      case operationsAdmin:
      case supportOnboarding:
      case billingAdmin:
        return value;
      default:
        return denied;
    }
  }

  static String label(String role) {
    switch (normalize(role)) {
      case operationsAdmin:
        return 'Administrador operativo';
      case supportOnboarding:
        return 'Soporte / implementacion';
      case billingAdmin:
        return 'Encargado de facturacion';
      case superAdmin:
        return 'Super admin';
      default:
        return 'Sin acceso';
    }
  }

  static String summary(String role) {
    switch (normalize(role)) {
      case operationsAdmin:
        return 'Puede ver colegios, crearlos, editar datos operativos y apoyar onboarding.';
      case supportOnboarding:
        return 'Puede ver colegios, revisar operacion y acompanar implementacion sin cambios criticos.';
      case billingAdmin:
        return 'Puede revisar planes, pagos y vencimientos sin acceso operativo ni sensible.';
      case superAdmin:
        return 'Tiene control total de EduPro, colegios, equipo, seguridad y facturacion.';
      default:
        return 'No tiene permisos del equipo.';
    }
  }

  static String defaultRoute(String role) {
    switch (normalize(role)) {
      case billingAdmin:
        return '/facturacion';
      case operationsAdmin:
      case supportOnboarding:
      case superAdmin:
        return '/panel';
      default:
        return '/login';
    }
  }
}

class EquipoEduProPermissions {
  static String _normalized(String role) => EquipoEduProRoles.normalize(role);

  static bool canViewSchools(String role) {
    final normalized = _normalized(role);
    return normalized == EquipoEduProRoles.superAdmin ||
        normalized == EquipoEduProRoles.operationsAdmin ||
        normalized == EquipoEduProRoles.supportOnboarding;
  }

  static bool canCreateSchools(String role) {
    final normalized = _normalized(role);
    return normalized == EquipoEduProRoles.superAdmin ||
        normalized == EquipoEduProRoles.operationsAdmin;
  }

  static bool canEditSchoolCore(String role) {
    final normalized = _normalized(role);
    return normalized == EquipoEduProRoles.superAdmin ||
        normalized == EquipoEduProRoles.operationsAdmin;
  }

  static bool canUseSchoolQuickActions(String role) {
    return _normalized(role) == EquipoEduProRoles.superAdmin;
  }

  static bool canAssignSchoolAdmin(String role) =>
      _normalized(role) == EquipoEduProRoles.superAdmin;

  static bool canAccessRoute(String role, String route) {
    switch (route) {
      case '/panel':
        return EquipoEduProRoles.all.contains(_normalized(role));
      case '/colegios':
        return canViewSchools(role);
      case '/analisis-general':
      case '/red-escolar':
        return canViewInsights(role);
      case '/facturacion':
        return canViewBilling(role);
      case '/configuracion':
      case '/pagos-facturacion':
      case '/gestion-accesos':
      case '/seguridad':
      case '/coleAdmin':
        return canViewSensitiveConfig(role);
      default:
        return false;
    }
  }

  static bool canChangeSchoolPlansAndLimits(String role) =>
      _normalized(role) == EquipoEduProRoles.superAdmin;

  static bool canViewBilling(String role) {
    final normalized = _normalized(role);
    return normalized == EquipoEduProRoles.superAdmin ||
        normalized == EquipoEduProRoles.billingAdmin;
  }

  static bool canViewInsights(String role) {
    final normalized = _normalized(role);
    return normalized == EquipoEduProRoles.superAdmin ||
        normalized == EquipoEduProRoles.operationsAdmin;
  }

  static bool canViewSensitiveConfig(String role) =>
      _normalized(role) == EquipoEduProRoles.superAdmin;
}

class EquipoEduProAccess {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<String> currentTeamRole(User user) async {
    return _requestTeamRole(user).timeout(const Duration(seconds: 30));
  }

  static Future<String> _requestTeamRole(User user) async {
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('La sesión ha cambiado.');
    }
    await AppCheckBootstrap.ensureReadyForProtectedCall();
    final response =
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('getTeamAccess').call();
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw StateError('La sesión ha cambiado.');
    }
    return roleFromResponse(response.data);
  }

  /// Only an explicit server decision can be presented as denied access.
  static String roleFromResponse(Object? response) {
    if (response is! Map || response['allowed'] is! bool) {
      throw const FormatException('Respuesta de permisos incompleta.');
    }
    if (response['allowed'] == false) return EquipoEduProRoles.denied;
    final rawRole = response['role'];
    if (rawRole is! String) {
      throw const FormatException('Rol no válido en la respuesta.');
    }
    final role = EquipoEduProRoles.normalize(rawRole);
    if (!EquipoEduProRoles.all.contains(role)) {
      throw const FormatException('Rol no reconocido en la respuesta.');
    }
    return role;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> loadDoc(String uid) {
    return _db.collection('EquipoEduPro').doc(uid).get();
  }

  static bool isAllowedNow(Map<String, dynamic> data, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc().subtract(
      const Duration(hours: 4),
    );
    final enabled = data['enabled'] == true;
    if (!enabled) return false;
    if (EquipoEduProRoles.normalize(
          (data['teamRole'] ?? data['role'])?.toString(),
        ) ==
        EquipoEduProRoles.superAdmin) {
      return true;
    }

    final weekdaysRaw = data['allowedWeekdays'];
    final weekdays =
        weekdaysRaw is List
            ? weekdaysRaw
                .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
                .whereType<int>()
                .toSet()
            : <int>{};

    if (weekdays.isNotEmpty && !weekdays.contains(current.weekday)) {
      return false;
    }

    final startMinute =
        (data['startMinute'] is num) ? (data['startMinute'] as num).toInt() : 0;
    final endMinute =
        (data['endMinute'] is num) ? (data['endMinute'] as num).toInt() : 1439;
    final nowMinute = current.hour * 60 + current.minute;

    if (startMinute == endMinute) return true;
    if (startMinute < endMinute) {
      return nowMinute >= startMinute && nowMinute <= endMinute;
    }
    return nowMinute >= startMinute || nowMinute <= endMinute;
  }

  static String denialReason(Map<String, dynamic> data, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc().subtract(
      const Duration(hours: 4),
    );
    if (data['enabled'] == false) {
      return 'Tu acceso del Equipo EduPro esta desactivado.';
    }

    final weekdaysRaw = data['allowedWeekdays'];
    final weekdays =
        weekdaysRaw is List
            ? weekdaysRaw
                .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
                .whereType<int>()
                .toSet()
            : <int>{};

    if (weekdays.isNotEmpty && !weekdays.contains(current.weekday)) {
      final labels =
          (data['allowedDayLabels'] is List)
              ? (data['allowedDayLabels'] as List)
                  .map((e) => e.toString())
                  .join(', ')
              : 'los dias autorizados';
      return 'Hoy no esta dentro de tus dias permitidos ($labels).';
    }

    final startLabel = (data['startLabel'] ?? '').toString().trim();
    final endLabel = (data['endLabel'] ?? '').toString().trim();
    return 'Tu acceso esta fuera del horario permitido${startLabel.isNotEmpty && endLabel.isNotEmpty ? ' ($startLabel - $endLabel)' : ''}.';
  }

  static Future<String?> validateUser(User user) async {
    final role = await currentTeamRole(user);
    return role == EquipoEduProRoles.denied
        ? 'Tu cuenta no está autorizada o está fuera de su horario de acceso.'
        : null;
  }

  static Future<void> registerLogin(User user) async {
    final docRef = _db.collection('EquipoEduPro').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final ctx = await _buildLoginContext();
    final now = FieldValue.serverTimestamp();

    await docRef.set({
      'lastLoginAt': now,
      'lastLoginContext': ctx,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await docRef.collection('logins').add({
      'createdAt': now,
      'context': ctx,
      'email': user.email?.trim().toLowerCase(),
      'uid': user.uid,
    });
  }

  static Future<Map<String, dynamic>> _buildLoginContext() async {
    final deviceInfo = DeviceInfoPlugin();
    final localeTag = ui.PlatformDispatcher.instance.locale.toLanguageTag();
    final timezone = DateTime.now().timeZoneName;
    final offset = DateTime.now().timeZoneOffset.inHours;

    final data = <String, dynamic>{
      'locale': localeTag,
      'timezone': timezone,
      'timezoneOffsetHours': offset,
      'platform': defaultTargetPlatform.name,
      'approxLocation': '$localeTag • $timezone',
      'isWeb': kIsWeb,
    };

    try {
      if (kIsWeb) {
        final web = await deviceInfo.webBrowserInfo;
        data.addAll({
          'browser': web.browserName.name,
          'userAgent': web.userAgent ?? '',
          'vendor': web.vendor ?? '',
          'hardwareConcurrency': web.hardwareConcurrency,
        });
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await deviceInfo.androidInfo;
            data.addAll({
              'device': info.model,
              'brand': info.brand,
              'sdkInt': info.version.sdkInt,
            });
            break;
          case TargetPlatform.iOS:
            final info = await deviceInfo.iosInfo;
            data.addAll({
              'device': info.utsname.machine,
              'systemVersion': info.systemVersion,
              'model': info.model,
            });
            break;
          case TargetPlatform.windows:
            final info = await deviceInfo.windowsInfo;
            data.addAll({
              'device': info.computerName,
              'buildNumber': info.buildNumber,
            });
            break;
          case TargetPlatform.macOS:
            final info = await deviceInfo.macOsInfo;
            data.addAll({
              'device': info.computerName,
              'model': info.model,
              'osRelease': info.osRelease,
            });
            break;
          case TargetPlatform.linux:
            final info = await deviceInfo.linuxInfo;
            data.addAll({'device': info.prettyName, 'version': info.version});
            break;
          case TargetPlatform.fuchsia:
            break;
        }
      }
    } catch (_) {}

    return data;
  }
}
