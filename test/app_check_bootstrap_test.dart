import 'dart:async';

import 'package:edupro/services/app_check_bootstrap.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  const channel = MethodChannel('plugins.flutter.io/firebase_app_check');
  const events = MethodChannel('app-check-unit-test-events');
  final calls = <MethodCall>[];
  var failActivation = false;
  var failToken = false;
  String? responseToken = 'unit-test-attestation';
  Completer<void>? activationGate;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'FirebaseAppCheck#registerTokenListener':
          return events.name;
        case 'FirebaseAppCheck#activate':
          if (failActivation) {
            throw PlatformException(
              code: 'activation-failed',
              message: 'private-platform-detail',
            );
          }
          await activationGate?.future;
          return null;
        case 'FirebaseAppCheck#getToken':
          if (failToken) {
            throw PlatformException(
              code: 'invalid-token',
              message: 'private-platform-detail',
            );
          }
          return responseToken;
        default:
          return null;
      }
    });
    await Firebase.initializeApp();
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test(
    'A protected call fails closed when App Check is disabled',
    () async {
      await expectLater(
        AppCheckBootstrap.ensureReadyForProtectedCall(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'safe configuration error',
            contains('no esta configurada'),
          ),
        ),
      );
      expect(calls, isEmpty);
    },
    skip: AppCheckBootstrap.enabled,
  );

  // Run this native MethodChannel test additionally with
  // --dart-define=VALMICH_APP_CHECK=true. No Firebase service is contacted.
  test(
    'Protected calls require a token, share activation and redact failures',
    () async {
      failActivation = true;
      await expectLater(
        AppCheckBootstrap.ensureReadyForProtectedCall(),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'configuration',
                contains('no esta configurada'),
              )
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains('private-platform-detail')),
              ),
        ),
      );
      expect(calls.where((call) => call.method.endsWith('#getToken')), isEmpty);

      // A later explicit call may recover startup; concurrent callers share
      // one activation. This does not repeat any protected or TOTP request.
      failActivation = false;
      activationGate = Completer<void>();
      final first = AppCheckBootstrap.ensureReadyForProtectedCall();
      final second = AppCheckBootstrap.ensureReadyForProtectedCall();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.where((call) => call.method.endsWith('#activate')).length,
        2,
      );
      activationGate!.complete();
      await Future.wait([first, second]);

      for (final invalidToken in <String?>[null, '', '   ']) {
        responseToken = invalidToken;
        await expectLater(
          AppCheckBootstrap.ensureReadyForProtectedCall(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'authorization',
              contains('No se pudo autorizar'),
            ),
          ),
        );
      }
      failToken = true;
      await expectLater(
        AppCheckBootstrap.ensureReadyForProtectedCall(),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'authorization',
                contains('No se pudo autorizar'),
              )
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains('private-platform-detail')),
              ),
        ),
      );
      failToken = false;
      responseToken = 'unit-test-attestation';
      await AppCheckBootstrap.ensureReadyForProtectedCall();
      expect(
        calls.where((call) => call.method.endsWith('#activate')).length,
        2,
      );
      final tokenCalls =
          calls.where((call) => call.method.endsWith('#getToken')).toList();
      expect(tokenCalls.length, 7);
      expect(
        tokenCalls.every((call) => call.arguments['forceRefresh'] == false),
        isTrue,
      );
    },
    skip: !AppCheckBootstrap.enabled,
  );

  test(
    'An isolated registration app activates its own App Check provider',
    () async {
      final app = await Firebase.initializeApp(
        name: 'synthetic-registration',
        options: Firebase.app().options,
      );
      final start = calls.length;
      await AppCheckBootstrap.activateForApp(app);
      final newCalls = calls.skip(start).toList();
      final activation = newCalls.singleWhere(
        (call) => call.method == 'FirebaseAppCheck#activate',
      );
      expect(activation.arguments['appName'], 'synthetic-registration');
      expect(Firebase.app().name, '[DEFAULT]');
    },
    skip: !AppCheckBootstrap.enabled,
  );
}
