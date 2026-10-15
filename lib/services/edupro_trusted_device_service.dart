import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class EduProTrustedDeviceIdentity {
  const EduProTrustedDeviceIdentity({
    required this.deviceId,
    required this.deviceLabel,
    required this.platformLabel,
  });

  final String deviceId;
  final String deviceLabel;
  final String platformLabel;
}

class EduProTrustedDeviceCheckResult {
  const EduProTrustedDeviceCheckResult({
    required this.allowed,
    required this.restricted,
    required this.device,
    required this.message,
  });

  final bool allowed;
  final bool restricted;
  final EduProTrustedDeviceIdentity device;
  final String message;
}

class EduProTrustedDeviceService {
  EduProTrustedDeviceService._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static EduProTrustedDeviceIdentity? _cachedIdentity;

  static Future<EduProTrustedDeviceIdentity> currentIdentity() async {
    if (_cachedIdentity != null) {
      return _cachedIdentity!;
    }

    final deviceInfo = DeviceInfoPlugin();
    final locale = ui.PlatformDispatcher.instance.locale.toLanguageTag();
    final base = <String, dynamic>{
      'locale': locale,
      'platform': defaultTargetPlatform.name,
      'isWeb': kIsWeb,
    };

    String deviceLabel = defaultTargetPlatform.name;

    try {
      if (kIsWeb) {
        final web = await deviceInfo.webBrowserInfo;
        final browser = web.browserName.name;
        final platform = web.platform ?? '';
        final vendor = web.vendor ?? '';
        final hardwareConcurrency = web.hardwareConcurrency;
        final userAgent = web.userAgent ?? '';
        base.addAll({
          'browser': browser,
          'platformRaw': platform,
          'vendor': vendor,
          'hardwareConcurrency': hardwareConcurrency,
          'userAgent': userAgent,
        });
        final platformLabel = platform.trim().isEmpty ? 'Web' : platform.trim();
        deviceLabel = '$browser • $platformLabel';
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await deviceInfo.androidInfo;
            base.addAll({
              'brand': info.brand,
              'model': info.model,
              'device': info.device,
              'product': info.product,
              'sdkInt': info.version.sdkInt,
            });
            deviceLabel = '${info.brand} ${info.model}'.trim();
            break;
          case TargetPlatform.iOS:
            final info = await deviceInfo.iosInfo;
            base.addAll({
              'machine': info.utsname.machine,
              'model': info.model,
              'systemVersion': info.systemVersion,
              'name': info.name,
            });
            deviceLabel = '${info.name} • ${info.model}'.trim();
            break;
          case TargetPlatform.windows:
            final info = await deviceInfo.windowsInfo;
            base.addAll({
              'computerName': info.computerName,
              'buildNumber': info.buildNumber,
              'numberOfCores': info.numberOfCores,
              'systemMemoryInMegabytes': info.systemMemoryInMegabytes,
            });
            deviceLabel = '${info.computerName} • Windows'.trim();
            break;
          case TargetPlatform.macOS:
            final info = await deviceInfo.macOsInfo;
            base.addAll({
              'computerName': info.computerName,
              'model': info.model,
              'osRelease': info.osRelease,
              'arch': info.arch,
            });
            deviceLabel = '${info.computerName} • macOS'.trim();
            break;
          case TargetPlatform.linux:
            final info = await deviceInfo.linuxInfo;
            base.addAll({
              'prettyName': info.prettyName,
              'version': info.version,
              'id': info.id,
            });
            deviceLabel = '${info.prettyName} • Linux'.trim();
            break;
          case TargetPlatform.fuchsia:
            base['platformRaw'] = 'fuchsia';
            deviceLabel = 'Fuchsia';
            break;
        }
      }
    } catch (_) {}

    final normalizedLabel = deviceLabel.trim().isEmpty
        ? defaultTargetPlatform.name
        : deviceLabel.trim();
    final digest = sha256.convert(utf8.encode(jsonEncode(base))).toString();

    final identity = EduProTrustedDeviceIdentity(
      deviceId: digest,
      deviceLabel: normalizedLabel,
      platformLabel: defaultTargetPlatform.name,
    );
    _cachedIdentity = identity;
    return identity;
  }

  static Future<EduProTrustedDeviceCheckResult> checkAccess({
    required String audience,
    String? schoolId,
  }) async {
    final identity = await currentIdentity();
    final callable = _fn.httpsCallable('checkEduProTrustedDevice');
    final response = await callable.call(<String, dynamic>{
      'audience': audience,
      'deviceId': identity.deviceId,
      'deviceLabel': identity.deviceLabel,
      if (schoolId != null && schoolId.trim().isNotEmpty)
        'schoolId': schoolId.trim(),
    });

    final raw = response.data;
    final data = raw is Map
        ? raw.map((key, value) => MapEntry('$key', value))
        : const <String, dynamic>{};

    return EduProTrustedDeviceCheckResult(
      allowed: data['allowed'] == true,
      restricted: data['restricted'] == true,
      device: identity,
      message: (data['message'] ?? '').toString(),
    );
  }
}
