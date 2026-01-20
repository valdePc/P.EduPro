// lib/docentes/screens/docentes.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'package:edupro/docentes/screens/paneldedocentes.dart';
import 'package:edupro/docentes/screens/crearcuentadocentes.dart';

class DocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const DocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<DocentesScreen> createState() => _DocentesScreenState();
}

class _DocentesScreenState extends State<DocentesScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameCtrl = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();

  bool _loading = false;
  bool _invalidLogin = false;
  String? _errorMessage;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolId;

  // -------------------------------
  // Autocomplete (docentes activos)
  // -------------------------------
  bool _loadingTeachers = true;
  String? _teachersLoadError;
  List<_TeacherOption> _activeTeachers = const [];
  _TeacherOption? _selectedTeacher;

  @override
  void initState() {
    super.initState();

    // ✅ MISMA lógica que en crear_cuenta_docente.dart (prefijo incluido)
    final rawId = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _cleanSchoolId(
      rawId.startsWith('eduproapp_admin_') ? rawId : 'eduproapp_admin_$rawId',
    );

    _loadActiveTeachers();

    // Si el usuario escribe algo diferente a la selección, quitamos la selección.
    _usernameCtrl.addListener(() {
      final sel = _selectedTeacher;
      if (sel == null) return;

      final txt = _usernameCtrl.text.trim();
      if (txt.isEmpty) {
        if (mounted) setState(() => _selectedTeacher = null);
        return;
      }

      final n = _norm(txt);

      // ✅ No borrar selección si el usuario escribe el correo del docente
      if (_norm(sel.name) != n &&
          _norm(sel.loginKey) != n &&
          _norm(_canonUserInput(sel.emailLower)) != n) {
        if (mounted) setState(() => _selectedTeacher = null);
      }
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  // Firestore no permite "/" en docId
  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  // ✅ Privado (detalles)
  CollectionReference<Map<String, dynamic>> get _teachersColl =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  // ✅ PUBLIC (tu captura muestra: teachers_public)
  // Aquí debe vivir el statusLower active/blocked
  CollectionReference<Map<String, dynamic>> get _teachersPublicColl =>
      _db.collection('schools').doc(_schoolId).collection('teachers_public');

  // -------------------------------
  // Normalización
  // -------------------------------
  String _stripAccents(String s) {
    const from = 'ÁÀÂÄÃáàâäãÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕóòôöõÚÙÛÜúùûüÑñ';
    const to = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNn';
    for (int i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  String _norm(String s) => _stripAccents(s).trim().toLowerCase();

  // ✅ Canoniza input (y corrige typo común: ggmail -> gmail) SOLO para búsqueda/matching
  String _canonUserInput(String s) {
    var t = s.trim();
    if (t.contains('@')) {
      t = t.toLowerCase();
      if (t.endsWith('@ggmail.com')) {
        t = t.replaceAll('@ggmail.com', '@gmail.com');
      }
    }
    return t;
  }

  bool _looksLikePhone(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 6;
  }

  String _phoneDigitsForHash(String input) {
    final d = input.replaceAll(RegExp(r'\D'), '');
    if (d.length <= 10) return d;
    return d.substring(d.length - 10);
  }

  String _sha1Hex(String s) => sha1.convert(utf8.encode(s)).toString();

  // -------------------------------
  // Cargar docentes activos (NO depende solo de where)
  // - Trae hasta 600 recientes y filtra "active" en cliente
  // - Así no te deja fuera docs sin statusLower
  // -------------------------------
  Future<void> _loadActiveTeachers() async {
    if (!mounted) return;
    setState(() {
      _loadingTeachers = true;
      _teachersLoadError = null;
    });

    try {
      final snap = await _teachersPublicColl.limit(600).get();

      final list = snap.docs
          .map(_TeacherOption.fromDoc)
          .where((t) => t.name.trim().isNotEmpty)
          .where((t) => t.statusLower == 'active')
          .toList();

      list.sort((a, b) => _norm(a.name).compareTo(_norm(b.name)));

      if (!mounted) return;
      setState(() {
        _activeTeachers = list;
        _loadingTeachers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeTeachers = const [];
        _loadingTeachers = false;
        _teachersLoadError = e.toString();
      });
    }
  }

  void _clearTeacherSelection() {
    if (!mounted) return;
    setState(() => _selectedTeacher = null);
    _usernameCtrl.clear();
  }

  List<_TeacherOption> _filterOptions(String query) {
    final q = _norm(_canonUserInput(query));
    if (q.isEmpty) return const [];

    final isPhone = _looksLikePhone(query);
    final qPhoneHash = isPhone ? _sha1Hex(_phoneDigitsForHash(query)) : null;

    final out = <_TeacherOption>[];
    for (final t in _activeTeachers) {
      final name = _norm(t.name);
      final user = _norm(t.loginKey);
      final email = _norm(_canonUserInput(t.emailLower));

      final matchName = name.startsWith(q) || name.contains(q);
      final matchUser = user.isNotEmpty && (user.startsWith(q) || user.contains(q));
      final matchEmail = email.isNotEmpty && (email.startsWith(q) || email.contains(q));

      var matchPhone = false;
      if (isPhone && qPhoneHash != null && t.phoneHash.isNotEmpty) {
        matchPhone = (t.phoneHash == qPhoneHash);
      }

      if (matchName || matchUser || matchEmail || matchPhone) out.add(t);
      if (out.length >= 20) break;
    }

    out.sort((a, b) {
      final an = _norm(a.name);
      final bn = _norm(b.name);
      final aStarts = an.startsWith(q) ? 0 : 1;
      final bStarts = bn.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts - bStarts;
      return an.compareTo(bn);
    });

    return out;
  }

  _TeacherOption? _pickTeacherFromInput(String input) {
    final q = _norm(_canonUserInput(input));
    if (q.isEmpty) return null;

    if (_selectedTeacher != null) return _selectedTeacher;

    final isPhone = _looksLikePhone(input);
    final phoneHash = isPhone ? _sha1Hex(_phoneDigitsForHash(input)) : null;

    for (final t in _activeTeachers) {
      if (_norm(t.name) == q) return t;
      if (_norm(t.loginKey) == q) return t;
      if (_norm(_canonUserInput(t.emailLower)) == q) return t;
      if (phoneHash != null && t.phoneHash.isNotEmpty && t.phoneHash == phoneHash) return t;
    }

    for (final t in _activeTeachers) {
      if (_norm(t.name).contains(q)) return t;
      if (_norm(t.loginKey).contains(q)) return t;
      if (_norm(_canonUserInput(t.emailLower)).contains(q)) return t;
    }

    return null;
  }

  // -------------------------------
  // ✅ Si NO aparece en la lista, busca directo en Firestore
  // (evita que “está activo pero no sale” te rompa el login)
  // -------------------------------
  Future<_TeacherOption?> _findTeacherServerSide(String input) async {
    final qRaw = input.trim();
    if (qRaw.isEmpty) return null;

    final q = _canonUserInput(qRaw);
    final qLower = q.toLowerCase();

    QuerySnapshot<Map<String, dynamic>> snap;

    // 1) Por emailLower
    if (qLower.contains('@')) {
      snap = await _teachersPublicColl
          .where('emailLower', isEqualTo: qLower)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return _TeacherOption.fromDoc(snap.docs.first);
    }

    // 2) Por loginKey
    snap = await _teachersPublicColl.where('loginKey', isEqualTo: qLower).limit(1).get();
    if (snap.docs.isNotEmpty) return _TeacherOption.fromDoc(snap.docs.first);

    // 3) Por name exacto (si tu data guarda el name tal cual)
    snap = await _teachersPublicColl.where('name', isEqualTo: qRaw).limit(1).get();
    if (snap.docs.isNotEmpty) return _TeacherOption.fromDoc(snap.docs.first);

    // 4) Teléfono (phoneHash)
    if (_looksLikePhone(qRaw)) {
      final ph = _sha1Hex(_phoneDigitsForHash(qRaw));
      snap = await _teachersPublicColl.where('phoneHash', isEqualTo: ph).limit(1).get();
      if (snap.docs.isNotEmpty) return _TeacherOption.fromDoc(snap.docs.first);
    }

    return null;
  }

  // -------------------------------
  // VAPID / Push
  // -------------------------------
  Future<String?> _loadWebVapidKey() async {
    try {
      final doc = await _db.collection('app_config').doc('notifications').get();
      final data = doc.data();
      final k = (data?['vapidKey'] ?? '').toString().trim();
      return k.isEmpty ? null : k;
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerPushTeacher() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      if (_schoolId.trim().isEmpty) return;

      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {}

      String? token;

      if (kIsWeb) {
        final vapid = await _loadWebVapidKey();
        try {
          token = await FirebaseMessaging.instance.getToken(
            vapidKey: (vapid == null || vapid.isEmpty) ? null : vapid,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('FCM Web token error: $e');
          return;
        }
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }

      token = token?.trim();
      if (token == null || token.isEmpty) return;

      final membersRef = _db
          .collection('schools')
          .doc(_schoolId)
          .collection('members')
          .doc(user.uid);

      try {
        final existing = await membersRef.get();

        if (!existing.exists) {
          await membersRef.set({
            'uid': user.uid,
            'role': 'teacher',
            'audience': 'teachers',
            'tokens': [token],
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await membersRef.update({
            'tokens': FieldValue.arrayUnion([token]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error guardando members token: $e');
      }

      try {
        await FirebaseMessaging.instance.subscribeToTopic('school_$_schoolId');
        await FirebaseMessaging.instance.subscribeToTopic('school_${_schoolId}_teachers');
      } catch (e) {
        if (kDebugMode) debugPrint('Error suscribiendo topics: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error registrando push: $e');
    }
  }

  // -------------------------------
  // LOGIN con GOOGLE (VALIDA EN teachers_public)
  // -------------------------------
  Future<UserCredential> _signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return await _auth.signInWithPopup(provider);
    } else {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();

      final account = await googleSignIn.authenticate();
      final auth = await account.authentication;

      if (auth.idToken == null || auth.idToken!.isEmpty) {
        throw Exception('Google no devolvió idToken.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    }
  }

  Future<void> _onLoginWithGoogle() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _invalidLogin = false;
      _errorMessage = null;
      _loading = true;
    });

    try {
      if (!_formKey.currentState!.validate()) return;

      // ✅ REFRESH antes de intentar (tu caso: activaste y “no sale”)
      await _loadActiveTeachers();

      final inputUser = _usernameCtrl.text.trim();

      // 1) intenta por lista
      var teacherOpt = _pickTeacherFromInput(inputUser);

      // 2) si no lo encuentra, busca directo en Firestore (server)
      teacherOpt ??= await _findTeacherServerSide(inputUser);

      if (teacherOpt == null) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'Docente no encontrado o no activo.';
        });
        return;
      }

      // ✅ Validación REAL: teachers_public (donde está active/blocked)
      final tdSnap = await _teachersPublicColl.doc(teacherOpt.id).get();
      if (!tdSnap.exists) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'No estás registrado en docentes públicos.';
        });
        return;
      }

      final td = tdSnap.data() ?? {};
      final tdStatusRaw =
          (td['statusLower'] ?? td['status'] ?? '').toString().trim().toLowerCase();
      final tdStatus = (tdStatusRaw == 'activo' || tdStatusRaw == 'activa')
          ? 'active'
          : tdStatusRaw;

      if (tdStatus != 'active') {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'Tu cuenta no está activa. La administración debe aprobarla.';
        });
        return;
      }

      final expectedEmail =
          (td['emailLower'] ?? teacherOpt.emailLower).toString().trim().toLowerCase();

      if (expectedEmail.isEmpty) {
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Tu cuenta no tiene correo registrado. Pide a administración que agregue tu correo.';
        });
        return;
      }

      // 1) Google Sign-In
      final cred = await _signInWithGoogle();
      final user = cred.user;
      if (user == null) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'No se pudo completar el inicio de sesión con Google.';
        });
        return;
      }

      final googleEmail = (user.email ?? '').trim().toLowerCase();
      if (googleEmail.isEmpty) {
        await _auth.signOut();
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'Google no devolvió un correo. Prueba con otra cuenta.';
        });
        return;
      }

      // 2) Validar correo contra teachers_public
      if (_canonUserInput(googleEmail) != _canonUserInput(expectedEmail)) {
        await _auth.signOut();
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Ese Google ($googleEmail) no coincide con el correo registrado ($expectedEmail).';
        });
        return;
      }

      // 3) Vincular uid (best effort)
      try {
        await _teachersColl.doc(teacherOpt.id).set({
          'authUid': user.uid,
          'authProvider': 'google',
          'authLinkedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'emailLower': expectedEmail,
        }, SetOptions(merge: true));
      } catch (_) {}

      try {
        await _teachersPublicColl.doc(teacherOpt.id).set({
          'authUid': user.uid,
          'authProvider': 'google',
          'updatedAt': FieldValue.serverTimestamp(),
          'emailLower': expectedEmail,
        }, SetOptions(merge: true));
      } catch (_) {}

      await _registerPushTeacher();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaneldedocentesScreen(escuela: widget.escuela),
        ),
      );
    } catch (e) {
      setState(() {
        _invalidLogin = true;
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CrearCuentaDocentesScreen(escuela: widget.escuela),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final bg = const Color(0xFFF4F7FB);
    final amber = const Color(0xFFFFA000);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(''),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/LogoDocentes.png', height: 96),
                    const SizedBox(height: 14),
                    Text(
                      widget.escuela.nombre ?? '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Bienvenido al área de docentes',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: azul.withOpacity(0.12)),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 14,
                      offset: Offset(0, 10),
                      color: Color(0x14000000),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      RawAutocomplete<_TeacherOption>(
                        textEditingController: _usernameCtrl,
                        focusNode: _usernameFocus,
                        displayStringForOption: (opt) => opt.name,
                        optionsBuilder: (TextEditingValue value) {
                          if (_loadingTeachers) {
                            return const Iterable<_TeacherOption>.empty();
                          }
                          final q = value.text.trim();
                          if (q.isEmpty) return const Iterable<_TeacherOption>.empty();
                          return _filterOptions(q);
                        },
                        onSelected: (opt) {
                          setState(() => _selectedTeacher = opt);
                          _usernameCtrl.text = opt.name;
                          _usernameCtrl.selection =
                              TextSelection.collapsed(offset: _usernameCtrl.text.length);
                        },
                        fieldViewBuilder: (context, ctrl, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: ctrl,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Nombre de usuario',
                              filled: true,
                              fillColor: const Color(0xFFF4F7FB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.person_search),
                              helperText: 'Escriba para ver sugerencias y seleccione su nombre.',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((_selectedTeacher != null) || ctrl.text.trim().isNotEmpty)
                                    IconButton(
                                      tooltip: 'Limpiar',
                                      icon: const Icon(Icons.clear),
                                      onPressed: _loading ? null : _clearTeacherSelection,
                                    ),
                                  IconButton(
                                    tooltip: 'Actualizar lista',
                                    icon: const Icon(Icons.refresh),
                                    onPressed: _loading ? null : _loadActiveTeachers,
                                  ),
                                ],
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Escriba su nombre' : null,
                            onFieldSubmitted: (_) => _loading ? null : _onLoginWithGoogle(),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          final list = options.toList();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(14),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 620),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final t = list[i];
                                    return ListTile(
                                      onTap: () => onSelected(t),
                                      title: Text(
                                        t.name,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      subtitle: (t.loginKey.trim().isEmpty)
                                          ? null
                                          : Text('Usuario: ${t.loginKey}'),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_loadingTeachers) ...[
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Cargando docentes activos...',
                              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ] else if ((_teachersLoadError ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No se pudo cargar la lista de docentes.',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              if (kDebugMode) ...[
                                const SizedBox(height: 6),
                                Text('Detalle: $_teachersLoadError'),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (_selectedTeacher != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Seleccionado: ${_selectedTeacher!.name}',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Quitar selección',
                                onPressed: _loading
                                    ? null
                                    : () => setState(() => _selectedTeacher = null),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_invalidLogin && (_errorMessage ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.20)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _onLoginWithGoogle,
                          icon: const Icon(Icons.g_mobiledata, size: 28),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: amber,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          label: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation(Colors.black),
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Iniciar con Google'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _onCreateAccount,
                            child: const Text('Crear cuenta'),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherOption {
  final String id;
  final String name;
  final String loginKey;
  final String phoneHash;

  final String authEmail;
  final String emailLower;
  final String statusLower;

  const _TeacherOption({
    required this.id,
    required this.name,
    required this.loginKey,
    required this.phoneHash,
    required this.authEmail,
    required this.emailLower,
    required this.statusLower,
  });

  factory _TeacherOption.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();

    final ph = (data['phoneHash'] ?? '').toString().trim();

    String computedHash = '';
    final rawPhone = (data['phone'] ?? '').toString();
    if (rawPhone.trim().isNotEmpty) {
      final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
      final last10 = digits.length <= 10 ? digits : digits.substring(digits.length - 10);
      computedHash = last10.isEmpty ? '' : sha1.convert(utf8.encode(last10)).toString();
    }
    final finalHash = ph.isNotEmpty ? ph : computedHash;

    final authEmail = (data['authEmail'] ?? '').toString().trim();

    final e1 = (data['emailLower'] ?? '').toString().trim().toLowerCase();
    final e2 = (data['email'] ?? '').toString().trim().toLowerCase();
    final emailLower = e1.isNotEmpty ? e1 : e2;

    final rawStatus = (data['statusLower'] ?? data['status'] ?? '').toString().trim();
    var st = rawStatus.toLowerCase();
    if (st == 'activo' || st == 'activa') st = 'active';
    if (st == 'bloqueado') st = 'blocked';
    if (st.isEmpty) st = 'active';

    return _TeacherOption(
      id: d.id,
      name: (data['name'] ?? '').toString(),
      loginKey: (data['loginKey'] ?? '').toString(),
      phoneHash: finalHash,
      authEmail: authEmail,
      emailLower: emailLower,
      statusLower: st,
    );
  }
}
