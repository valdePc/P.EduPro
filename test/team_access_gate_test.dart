import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:edupro/widgets/team_access_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only an explicit denial is classified as denied access', () {
    expect(
      EquipoEduProAccess.roleFromResponse({'allowed': false}),
      EquipoEduProRoles.denied,
    );
    for (final role in EquipoEduProRoles.all) {
      expect(
        EquipoEduProAccess.roleFromResponse({'allowed': true, 'role': role}),
        role,
      );
    }
    for (final malformed in <Object?>[
      null,
      [],
      {},
      {'role': 'super_admin'},
      {'allowed': 'false'},
      {'allowed': true},
      {'allowed': true, 'role': 1},
      {'allowed': true, 'role': 'invented'},
    ]) {
      expect(
        () => EquipoEduProAccess.roleFromResponse(malformed),
        throwsFormatException,
      );
    }
  });

  late StreamController<String?> sessions;
  String? sessionId;
  int starts = 0;
  int exits = 0;
  int renders = 0;
  setUp(() {
    sessions = StreamController<String?>.broadcast(sync: true);
    sessionId = 'first-account';
    starts = exits = renders = 0;
  });
  tearDown(() => sessions.close());

  Widget gate(Future<String> Function() loader) => MaterialApp(
    home: TeamAccessGate(
      loadRole: loader,
      currentSessionId: () => sessionId,
      sessionChanges: sessions.stream,
      timeout: const Duration(seconds: 2),
      onCheckStarted: () => starts++,
      onExit: () => exits++,
      allowedBuilder: (_, role) {
        renders++;
        return Scaffold(body: Text('Panel $role'));
      },
    ),
  );

  testWidgets(
    'network failure offers retry without signing out or rendering data',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        gate(() async {
          calls++;
          if (calls == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'private server diagnostics',
            );
          }
          return EquipoEduProRoles.operationsAdmin;
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo comprobar el acceso'), findsOneWidget);
      expect(find.text('Acceso restringido'), findsNothing);
      expect(find.textContaining('private server'), findsNothing);
      expect(renders, 0);
      expect(exits, 0);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(starts, 2);
      expect(find.text('Panel operations_admin'), findsOneWidget);
    },
  );

  testWidgets('timeout permits retry and ignores the late first response', (
    tester,
  ) async {
    final first = Completer<String>();
    final second = Completer<String>();
    var calls = 0;
    await tester.pumpWidget(
      gate(() => ++calls == 1 ? first.future : second.future),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    first.complete(EquipoEduProRoles.superAdmin);
    await tester.pump();
    expect(renders, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    second.complete(EquipoEduProRoles.supportOnboarding);
    await tester.pumpAndSettle();
    expect(find.text('Panel support_onboarding'), findsOneWidget);
    expect(find.text('Panel super_admin'), findsNothing);
  });

  testWidgets('explicit denial never offers the protected content', (
    tester,
  ) async {
    await tester.pumpWidget(gate(() async => EquipoEduProRoles.denied));
    await tester.pumpAndSettle();
    expect(find.text('Acceso restringido'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(renders, 0);
    expect(exits, 0);
    await tester.tap(find.text('Salir'));
    expect(exits, 1);
  });

  testWidgets('session change discards a previous account response', (
    tester,
  ) async {
    final first = Completer<String>();
    final second = Completer<String>();
    var calls = 0;
    await tester.pumpWidget(
      gate(() => ++calls == 1 ? first.future : second.future),
    );
    sessionId = 'second-account';
    sessions.add(sessionId);
    await tester.pump();
    first.complete(EquipoEduProRoles.superAdmin);
    await tester.pump();
    expect(renders, 0);
    second.complete(EquipoEduProRoles.denied);
    await tester.pumpAndSettle();
    expect(find.text('Acceso restringido'), findsOneWidget);
    expect(renders, 0);
  });

  testWidgets('signing out removes an already authorized panel', (
    tester,
  ) async {
    await tester.pumpWidget(gate(() async => EquipoEduProRoles.superAdmin));
    await tester.pumpAndSettle();
    expect(find.text('Panel super_admin'), findsOneWidget);
    sessionId = null;
    sessions.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Panel super_admin'), findsNothing);
    expect(find.text('Sesión finalizada'), findsOneWidget);
  });

  testWidgets('malformed response is retryable and fits a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      gate(() async => EquipoEduProAccess.roleFromResponse({'allowed': true})),
    );
    await tester.pumpAndSettle();
    expect(find.text('No se pudo comprobar el acceso'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Acceso restringido'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(renders, 0);
  });

  testWidgets('completion after disposal cannot update the gate', (
    tester,
  ) async {
    final request = Completer<String>();
    await tester.pumpWidget(gate(() => request.future));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    request.completeError(StateError('late error'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home fallback runs only for an explicit denial', (
    tester,
  ) async {
    var calls = 0;
    var fallbackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TeamAccessGate(
          loadRole: () async {
            if (++calls == 1) throw const FormatException('bad response');
            return EquipoEduProRoles.denied;
          },
          currentSessionId: () => sessionId,
          sessionChanges: sessions.stream,
          onCheckStarted: () {},
          onExit: () {},
          allowedBuilder: (_, _) => const Text('Protected'),
          deniedBuilder: (_) {
            fallbackCalls++;
            return const Scaffold(body: Text('Login fallback'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fallbackCalls, 0);
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Login fallback'), findsOneWidget);
    expect(fallbackCalls, 1);
  });
}
