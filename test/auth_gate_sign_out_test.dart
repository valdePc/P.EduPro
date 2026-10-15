import 'package:edupro/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _denied = AsyncSnapshot<bool>.withData(ConnectionState.done, false);

Future<BuildContext> _mountHome(
  WidgetTester tester, {
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  late BuildContext routeContext;
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    home: Builder(builder: (context) {
      routeContext = context;
      return const Scaffold(body: Text('Home route'));
    }),
  ));
  return routeContext;
}

void main() {
  testWidgets('An explicit rejection signs out the same user on the visible route',
      (tester) async {
    final context = await _mountHome(tester);
    var signOutCalls = 0;
    scheduleDeniedTeamSessionSignOut(
      context,
      access: _denied,
      expectedUid: 'user-a',
      currentUid: () => 'user-a',
      signOut: () async { signOutCalls++; },
    );
    expect(signOutCalls, 0);
    await tester.pump();
    expect(signOutCalls, 1);
  });

  testWidgets('A covered home route cannot sign out the active login',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final context = await _mountHome(tester, navigatorKey: navigatorKey);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Login route')),
    ));
    await tester.pumpAndSettle();
    expect(context.mounted, isTrue);
    expect(ModalRoute.of(context)!.isCurrent, isFalse);
    var signOutCalls = 0;
    scheduleDeniedTeamSessionSignOut(
      context,
      access: _denied,
      expectedUid: 'user-a',
      currentUid: () => 'user-a',
      signOut: () async { signOutCalls++; },
    );
    await tester.pump();
    expect(signOutCalls, 0);
    expect(find.text('Login route'), findsOneWidget);
  });

  testWidgets('A disposed gate cannot sign out after the deferred callback',
      (tester) async {
    final context = await _mountHome(tester);
    var signOutCalls = 0;
    scheduleDeniedTeamSessionSignOut(
      context,
      access: _denied,
      expectedUid: 'user-a',
      currentUid: () => 'user-a',
      signOut: () async { signOutCalls++; },
    );
    await tester.pumpWidget(const SizedBox());
    expect(context.mounted, isFalse);
    expect(signOutCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A changed or closed session is not signed out by an old result',
      (tester) async {
    final context = await _mountHome(tester);
    var signOutCalls = 0;
    String? uid = 'user-a';
    for (final replacement in <String?>['user-b', null]) {
      uid = 'user-a';
      scheduleDeniedTeamSessionSignOut(
        context,
        access: _denied,
        expectedUid: 'user-a',
        currentUid: () => uid,
        signOut: () async { signOutCalls++; },
      );
      uid = replacement;
      await tester.pump();
      expect(signOutCalls, 0);
    }
  });

  testWidgets('Read errors, unfinished reads and allowed access never sign out',
      (tester) async {
    final context = await _mountHome(tester);
    var signOutCalls = 0;
    for (final access in [
      AsyncSnapshot<bool>.withError(ConnectionState.done, StateError('offline')),
      const AsyncSnapshot<bool>.withData(ConnectionState.waiting, false),
      const AsyncSnapshot<bool>.nothing(),
      const AsyncSnapshot<bool>.withData(ConnectionState.done, true),
    ]) {
      scheduleDeniedTeamSessionSignOut(
        context,
        access: access,
        expectedUid: 'user-a',
        currentUid: () => 'user-a',
        signOut: () async { signOutCalls++; },
      );
      await tester.pump();
      expect(signOutCalls, 0);
    }
  });
}
