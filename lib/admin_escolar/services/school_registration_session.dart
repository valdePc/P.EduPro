import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:edupro/services/app_check_bootstrap.dart';

/// A separate Firebase app keeps registration out of the main account/session.
/// Its credentials are memory-only on web and its Firestore cache is disabled.
class SchoolRegistrationSession {
  SchoolRegistrationSession._(this._app, this.schoolId);

  final FirebaseApp _app;
  final String schoolId;
  DateTime? _expiresAt;
  bool permitirFotoAlumno = false;
  bool permitirEditarEstudiantes = false;
  Future<void>? _closing;
  Future<void>? _renewal;
  bool _closed = false;

  FirebaseAuth get _auth => FirebaseAuth.instanceFor(app: _app);
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: _app, region: 'us-central1');
  FirebaseFirestore get firestore => FirebaseFirestore.instanceFor(app: _app);
  String get uid => _auth.currentUser?.uid ?? '';

  static Future<SchoolRegistrationSession> open({
    required String schoolId,
    required Map<String, dynamic> access,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'edupro-registro-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final session = SchoolRegistrationSession._(app, schoolId);
    try {
      session.firestore.settings = const Settings(persistenceEnabled: false);
      if (kIsWeb) await session._auth.setPersistence(Persistence.NONE);
      await AppCheckBootstrap.activateForApp(app);
      await session._acceptAccess(access);
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<void> _acceptAccess(Map<String, dynamic> access) async {
    final token = access['customToken'];
    final expiresAt = access['expiresAtMs'];
    if (access['ok'] != true ||
        access['schoolId'] != schoolId ||
        token is! String ||
        token.isEmpty ||
        expiresAt is! num) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'failed-precondition',
      );
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt());
    if (!expiry.isAfter(DateTime.now())) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'unauthenticated',
      );
    }
    await _auth.signInWithCustomToken(token);
    _expiresAt = expiry;
    permitirFotoAlumno = access['permitirFotoAlumno'] == true;
    permitirEditarEstudiantes = access['permitirEditarEstudiantes'] == true;
  }

  void ensureActive() {
    if (_closed ||
        uid.isEmpty ||
        _expiresAt == null ||
        !_expiresAt!.isAfter(DateTime.now())) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'unauthenticated',
      );
    }
  }

  Future<void> renew(String code) {
    if (_closed) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'unauthenticated',
      );
    }
    return _renewal ??= _renew(code).whenComplete(() => _renewal = null);
  }

  Future<void> _renew(String code) async {
    // The backend can renew this same restricted UID after verifying the code.
    final response = await _functions
        .httpsCallable('validateSchoolRegistroAccess')
        .call({'schoolId': schoolId, 'code': code});
    final raw = response.data;
    if (raw is! Map || raw['ok'] != true) {
      throw FirebaseException(
        plugin: 'school_registration',
        code:
            raw is Map && raw['blocked'] == true
                ? 'resource-exhausted'
                : 'invalid-argument',
      );
    }
    await _acceptAccess(Map<String, dynamic>.from(raw));
  }

  Future<void> register(String studentId, Map<String, dynamic> student) async {
    ensureActive();
    final response = await _functions
        .httpsCallable('registerSchoolStudent')
        .call({
          'schoolId': schoolId,
          'studentId': studentId,
          'student': student,
        });
    if (response.data is! Map || response.data['ok'] != true) {
      throw FirebaseException(plugin: 'school_registration', code: 'internal');
    }
  }

  Future<void> createGrade({
    required String name,
    required String nivel,
  }) async {
    ensureActive();
    await _functions.httpsCallable('createSchoolRegistroGrade').call({
      'schoolId': schoolId,
      'name': name,
      'nivel': nivel,
    });
  }

  Future<String> uploadPhoto(String studentId, Uint8List bytes) async {
    ensureActive();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'invalid-argument',
      );
    }
    final png =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    if (!png && !jpeg) {
      throw FirebaseException(
        plugin: 'school_registration',
        code: 'invalid-argument',
      );
    }
    final response = await _functions
        .httpsCallable('uploadSchoolRegistroPhoto')
        .call({
          'schoolId': schoolId,
          'studentId': studentId,
          'contentType': png ? 'image/png' : 'image/jpeg',
          'base64': base64Encode(bytes),
        });
    final raw = response.data;
    if (raw is! Map || raw['ok'] != true || raw['photoPath'] is! String) {
      throw FirebaseException(plugin: 'school_registration', code: 'internal');
    }
    return raw['photoPath'] as String;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // A code request may renew the same server grant. Wait for it before
    // revocation so it cannot reactivate access after this local logout.
    final renewal = _renewal;
    if (renewal != null) {
      try {
        await renewal;
      } catch (_) {}
    }
    if (_auth.currentUser != null) {
      try {
        await _functions
            .httpsCallable('endSchoolRegistroSession')
            .call({'schoolId': schoolId})
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Server expiry still applies if offline; local credentials are cleared.
      }
    }
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      await firestore.terminate();
    } catch (_) {}
    try {
      await _app.delete();
    } catch (_) {}
  }
}
