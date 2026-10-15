import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'team_school_catalog_controller.dart';
export '../models/team_school_catalog.dart';
import 'app_check_bootstrap.dart';

class TeamSchoolAccessService {
  TeamSchoolAccessService._();

  static TeamSchoolCatalogController? _catalog;
  static String? _catalogRole;
  static StreamSubscription<User?>? _sessionSubscription;

  static TeamSchoolCatalogController sharedCatalog({required String role}) {
    final auth = FirebaseAuth.instance;
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Inicia sesión para continuar.');
    if (_catalog == null ||
        _catalog!.sessionUid != uid ||
        _catalogRole != role) {
      _sessionSubscription?.cancel();
      _catalog?.dispose();
      final controller = TeamSchoolCatalogController(
        fetch: (query) => call('listTeamSchools', query),
        currentUid: () => auth.currentUser?.uid,
        sessionUid: uid,
      );
      _catalog = controller;
      _catalogRole = role;
      _sessionSubscription = auth.authStateChanges().listen((user) {
        if (user?.uid != uid) controller.invalidateSession();
      });
    }
    return _catalog!;
  }

  static void refresh() {
    final catalog = _catalog;
    if (catalog != null && catalog.currentUid() == catalog.sessionUid) {
      unawaited(catalog.refresh());
    }
  }

  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Inicia sesión para continuar.');
    }
    await AppCheckBootstrap.ensureReadyForProtectedCall();
    final response = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable(name).call(data);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('La sesión ha cambiado. Vuelve a iniciar sesión.');
    }
    if (response.data is! Map) {
      throw StateError('No se pudo leer la respuesta del servidor.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
