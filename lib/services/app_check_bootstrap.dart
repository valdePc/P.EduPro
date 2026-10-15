import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AppCheckBootstrap {
  static const bool enabled = bool.fromEnvironment(
    'VALMICH_APP_CHECK',
    defaultValue: kIsWeb,
  );
  static const bool strict = bool.fromEnvironment(
    'VALMICH_APP_CHECK_STRICT',
    defaultValue: false,
  );

  static const String _webSiteKey = String.fromEnvironment(
    'VALMICH_RECAPTCHA_V3_SITE_KEY',
    defaultValue: '',
  );

  // This is a public site key; it is not a server or debug-token secret.
  static const String _enterpriseSiteKey = String.fromEnvironment(
    'VALMICH_RECAPTCHA_ENTERPRISE_SITE_KEY',
    defaultValue: '6LefmKosAAAAABHcoFFbE_ekwlbP9nRY8rTV-jCx',
  );

  static const String _configurationError =
      'La verificacion de seguridad de la aplicacion no esta configurada. '
      'Contacta con soporte.';
  static const String authorizationError =
      'No se pudo autorizar esta aplicacion. Recarga la pagina o contacta con soporte.';
  static bool _activated = false;
  static Future<void>? _activation;

  static Future<void> _activate() async {
    await _activateInstance(FirebaseAppCheck.instance);
    _activated = true;
  }

  static Future<void> _activateInstance(FirebaseAppCheck appCheck) async {
    if (kIsWeb) {
      // Preserve explicitly configured V3 deployments during the migration.
      final v3Key = _webSiteKey.trim();
      final enterpriseKey = _enterpriseSiteKey.trim();
      if (v3Key.isEmpty && enterpriseKey.isEmpty) {
        throw StateError(_configurationError);
      }
      await appCheck.activate(
        webProvider:
            v3Key.isNotEmpty
                ? ReCaptchaV3Provider(v3Key)
                : ReCaptchaEnterpriseProvider(enterpriseKey),
      );
    } else {
      await appCheck.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      );
    }
    await appCheck.setTokenAutoRefreshEnabled(true);
  }

  /// Uses the same configured provider for isolated registration sessions.
  static Future<void> activateForApp(FirebaseApp app) async {
    if (!enabled) return;
    await _activateInstance(FirebaseAppCheck.instanceFor(app: app));
  }

  static Future<void> _ensureActivated() async {
    if (_activated) return;
    final attempt = _activation ??= _activate();
    try {
      await attempt;
    } finally {
      if (identical(_activation, attempt)) _activation = null;
    }
  }

  static Future<void> activateIfConfigured() async {
    if (!enabled) {
      debugPrint('[APP_CHECK] disabled_by_define');
      return;
    }

    try {
      await _ensureActivated();
      debugPrint('[APP_CHECK] activated');
    } catch (_) {
      debugPrint('[APP_CHECK] activation_failed');
      if (strict) throw StateError(_configurationError);
    }
  }

  /// Fails closed before protected calls, even when startup is non-strict.
  /// The SDK attaches the token; it must never be logged or sent as user data.
  static Future<void> ensureReadyForProtectedCall() async {
    if (!enabled) throw StateError(_configurationError);
    try {
      await _ensureActivated();
    } catch (_) {
      throw StateError(_configurationError);
    }
    try {
      final token = await FirebaseAppCheck.instance.getToken(false);
      if (token == null || token.trim().isEmpty) {
        throw StateError(authorizationError);
      }
    } catch (_) {
      throw StateError(authorizationError);
    }
  }
}
