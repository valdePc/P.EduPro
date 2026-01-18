// lib/alumnos/screens/alumnos.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'perfil_inicial_screen.dart';
import 'perfil_primaria_screen.dart';
import 'perfil_secundaria_screen.dart';

enum _Nivel { inicial, primaria, secundaria }

class _GradeItem {
  final String name;
  final _Nivel? nivel; // puede ser null si el doc no trae "nivel"
  final bool hasExplicitNivel;
  const _GradeItem({
    required this.name,
    required this.nivel,
    required this.hasExplicitNivel,
  });
}

class AlumnosScreen extends StatefulWidget {
  final Escuela escuela;
  const AlumnosScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AlumnosScreen> createState() => _AlumnosScreenState();
}

class _AlumnosScreenState extends State<AlumnosScreen> {
  late final String _schoolId;

  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController(); // número de lista
  final _contrasenaCtrl = TextEditingController();

  bool _showPassword = false;
  String? _errorText;
  bool _loading = false;

  _Nivel _nivelSel = _Nivel.primaria;
  String? _gradoSel;

  // Fallback solo si no hay grados en Firestore
  final List<String> _gradosFallbackRD = const [
    'Inicial 1',
    'Inicial 2',
    '1ro Primaria',
    '2do Primaria',
    '3ro Primaria',
    '4to Primaria',
    '5to Primaria',
    '6to Primaria',
    '1ro Secundaria',
    '2do Secundaria',
    '3ro Secundaria',
    '4to Secundaria',
    '5to Secundaria',
    '6to Secundaria',
  ];

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _numeroCtrl.dispose();
    _contrasenaCtrl.dispose();
    super.dispose();
  }

  // -------------------- Normalizadores --------------------
  String _onlyLettersSpaces(String s) =>
      s.replaceAll(RegExp(r"[^a-zA-ZñÑáéíóúÁÉÍÓÚüÜ\s'-]"), '');

  String _normalizeName(String input) {
    final cleaned =
        _onlyLettersSpaces(input).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '';
    return cleaned
        .split(' ')
        .map((w) =>
            w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  String _nameKey(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r"[^a-z0-9ñáéíóúü ]"), '');
  }

  // -------------------- Nivel desde grados --------------------
  _Nivel? _nivelFromAny(dynamic raw) {
    if (raw == null) return null;

    // numérico (por si algún día guardas 0/1/2)
    if (raw is int) {
      if (raw == 0) return _Nivel.inicial;
      if (raw == 1) return _Nivel.primaria;
      if (raw == 2) return _Nivel.secundaria;
      return null;
    }

    final s = raw.toString().toLowerCase().trim();
    if (s.isEmpty) return null;

    if (s.startsWith('ini')) return _Nivel.inicial;
    if (s.startsWith('pri')) return _Nivel.primaria;
    if (s.startsWith('sec')) return _Nivel.secundaria;

    // variantes
    if (s.contains('inicial')) return _Nivel.inicial;
    if (s.contains('primaria')) return _Nivel.primaria;
    if (s.contains('secundaria')) return _Nivel.secundaria;

    return null;
  }

  // Heurística solo para fallback viejo (no confíes en esto si tus nombres son "5to A")
  _Nivel _nivelPorNombreFallback(String gradoName) {
    final g = gradoName.toLowerCase();
    if (g.contains('inicial')) return _Nivel.inicial;
    if (g.contains('primaria')) return _Nivel.primaria;
    if (g.contains('secundaria')) return _Nivel.secundaria;
    return _Nivel.primaria; // mejor default que secundaria
  }

  // -------------------- Password (plano o hash) --------------------
  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();
  String _md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

  bool _looksLikeHexOfLen(String s, int len) {
    final t = s.trim().toLowerCase();
    if (t.length != len) return false;
    return RegExp(r'^[0-9a-f]+$').hasMatch(t);
  }

  String _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      if (data.containsKey(k) && data[k] != null) {
        final v = data[k].toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  bool _passwordMatches(Map<String, dynamic> data, String input) {
    final inPass = input.trim();

    final plain = _firstString(data, const [
      'password',
      'contrasena',
      'clave',
      'pass',
    ]);

    final hashField = _firstString(data, const [
      'passwordHash',
      'passHash',
      'hash',
    ]);

    // 1) Si hay hash explícito
    if (hashField.isNotEmpty) {
      final h = hashField.toLowerCase();
      if (_looksLikeHexOfLen(h, 64)) return _sha256Hex(inPass) == h;
      if (_looksLikeHexOfLen(h, 32)) return _md5Hex(inPass) == h;
      return false;
    }

    // 2) Si el password guardado "parece hash"
    if (plain.isNotEmpty) {
      final p = plain.toLowerCase();
      if (_looksLikeHexOfLen(p, 64)) return _sha256Hex(inPass) == p;
      if (_looksLikeHexOfLen(p, 32)) return _md5Hex(inPass) == p;
      // 3) plano vs plano
      return plain == inPass;
    }

    return false;
  }

  // -------------------- Firestore refs --------------------
  CollectionReference<Map<String, dynamic>> get _gradosCol => FirebaseFirestore
      .instance
      .collection('escuelas')
      .doc(_schoolId)
      .collection('grados');

  CollectionReference<Map<String, dynamic>> get _estudiantesCol =>
      FirebaseFirestore.instance
          .collection('escuelas')
          .doc(_schoolId)
          .collection('estudiantes');

  // -------------------- Auth helpers (Camino B) --------------------
  String _studentEmailFor(String studentDocId) {
    // Email sintético estable
    final safeSchool = _schoolId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
    return 'student_$studentDocId@$safeSchool.edupro';
  }

  Future<UserCredential> _signInOrCreateStudentAuth({
    required String studentDocId,
    required String password,
  }) async {
    final auth = FirebaseAuth.instance;
    final email = _studentEmailFor(studentDocId);

    try {
      return await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // Si no existe, lo creamos (solo después de validar contra Firestore)
      if (e.code == 'user-not-found') {
        return await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      // Password incorrecto en Auth (si lo cambiaron)
      if (e.code == 'wrong-password') {
        throw Exception(
          'Tu contraseña cambió o tu cuenta está desincronizada. Pide al admin que regenere tu acceso.',
        );
      }
      throw Exception('Auth error (${e.code}).');
    }
  }

  Future<void> _upsertUserProfile({
    required String uid,
    required String studentDocId,
    required String displayName,
    required String grado,
  }) async {
    final usersRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await usersRef.set({
      'role': 'student',
      'schoolId': _schoolId,
      'enabled': true,
      'displayName': displayName,
      'estudianteId': studentDocId,
      'grado': grado,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Amarra el estudiante al uid (opcional pero MUY recomendado)
    await _estudiantesCol.doc(studentDocId).set({
      'authUid': uid,
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // -------------------- Navegación por nivel --------------------
  void _irAPerfil({
    required _Nivel nivel,
    required String estudianteId,
    required String nombreAlumno,
    required String gradoSeleccionado,
  }) {
    Widget screen;
    switch (nivel) {
      case _Nivel.inicial:
        screen = PerfilInicialScreen(
          escuela: widget.escuela,
          estudianteId: estudianteId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
      case _Nivel.primaria:
        screen = PerfilPrimariaScreen(
          escuela: widget.escuela,
          estudianteId: estudianteId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
      case _Nivel.secundaria:
        screen = PerfilSecundariaScreen(
          escuela: widget.escuela,
          estudianteId: estudianteId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  // -------------------- Query estudiante (matrícula string o int) --------------------
  Future<QuerySnapshot<Map<String, dynamic>>> _queryByField(
    String grado,
    String field,
    String numero,
  ) async {
    // string
    var q = await _estudiantesCol
        .where('grado', isEqualTo: grado)
        .where(field, isEqualTo: numero)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) return q;

    // int
    final n = int.tryParse(numero);
    if (n != null) {
      q = await _estudiantesCol
          .where('grado', isEqualTo: grado)
          .where(field, isEqualTo: n)
          .limit(1)
          .get();
    }
    return q;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _findStudent(
    String grado,
    String numero,
  ) async {
    // intenta en orden de probabilidad
    const fields = ['matricula', 'numero', 'numeroLista', 'numLista'];
    for (final f in fields) {
      final q = await _queryByField(grado, f, numero);
      if (q.docs.isNotEmpty) return q;
    }
    // vacío
    return await _estudiantesCol.limit(0).get();
  }

  // -------------------- LOGIN --------------------
  Future<void> _validarDatos() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _loading = true;
    });

    try {
      final grado = (_gradoSel ?? '').trim();
      if (grado.isEmpty) {
        setState(() => _errorText = 'Selecciona tu aula/grado');
        return;
      }

      final nombres = _normalizeName(_nombresCtrl.text);
      final apellidos = _normalizeName(_apellidosCtrl.text);
      final numero = _numeroCtrl.text.trim();
      final pass = _contrasenaCtrl.text.trim();

      _nombresCtrl.text = nombres;
      _apellidosCtrl.text = apellidos;

      if (nombres.isEmpty || apellidos.isEmpty) {
        setState(() => _errorText = 'Escribe nombres y apellidos');
        return;
      }
      if (numero.isEmpty) {
        setState(() => _errorText = 'Escribe tu número de lista');
        return;
      }
      if (pass.isEmpty) {
        setState(() => _errorText = 'Escribe tu contraseña');
        return;
      }

      final q = await _findStudent(grado, numero);

      if (q.docs.isEmpty) {
        setState(() => _errorText =
            'No encontramos tu registro en ese grado con ese número');
        return;
      }

      final doc = q.docs.first;
      final data = doc.data();

      // contraseña (plano o hash)
      final hasAlgunaPassword = (data['password'] != null) ||
          (data['contrasena'] != null) ||
          (data['pass'] != null) ||
          (data['passwordHash'] != null) ||
          (data['passHash'] != null);

      if (!hasAlgunaPassword) {
        setState(() => _errorText =
            'Este estudiante no tiene contraseña configurada. Pide al admin regenerarla.');
        return;
      }

      if (!_passwordMatches(data, pass)) {
        if (kDebugMode) {
          debugPrint('LOGIN FAIL doc=${doc.id}');
          debugPrint('keys=${data.keys.toList()}');
          debugPrint('grado=$grado numero=$numero');
          debugPrint(
              'stored(password)="${data['password']}" stored(hash)="${data['passwordHash']}"');
        }
        setState(() => _errorText = 'Contraseña incorrecta');
        return;
      }

      // ✅ nombreKey/apellidoKey o nombresKey/apellidosKey
      final dbNombreKey = _firstString(data, const ['nombresKey', 'nombreKey']);
      final dbApellidoKey =
          _firstString(data, const ['apellidosKey', 'apellidoKey']);

      final inNombreKey = _nameKey(nombres);
      final inApellidoKey = _nameKey(apellidos);

      if (dbNombreKey.isNotEmpty && dbApellidoKey.isNotEmpty) {
        if (inNombreKey != dbNombreKey || inApellidoKey != dbApellidoKey) {
          setState(() => _errorText = 'Tu nombre no coincide con el registro');
          return;
        }
      }

      final nombreAlumno = '$nombres $apellidos'.trim();

      // ✅ CAMINO B: Auth real (sign-in o create) y guardado de rol en /users/{uid}
      final userCred = await _signInOrCreateStudentAuth(
        studentDocId: doc.id,
        password: pass,
      );

      final user = userCred.user;
      if (user == null) {
        setState(() => _errorText = 'No se pudo completar la autenticación.');
        return;
      }

      await _upsertUserProfile(
        uid: user.uid,
        studentDocId: doc.id,
        displayName: nombreAlumno,
        grado: grado,
      );

      // ✅ aquí usamos el nivel seleccionado
      _irAPerfil(
        nivel: _nivelSel,
        estudianteId: doc.id,
        nombreAlumno: nombreAlumno,
        gradoSeleccionado: grado,
      );
    } catch (e) {
      setState(() => _errorText = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _accesoRapidoDebug() {
    if (!kDebugMode) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Acceso rápido (DEBUG)'),
              subtitle: Text('Solo para diseñar perfiles sin login real'),
            ),
            ListTile(
              leading: const Icon(Icons.child_care),
              title: const Text('Perfil INICIAL'),
              onTap: () {
                Navigator.pop(context);
                _irAPerfil(
                  nivel: _Nivel.inicial,
                  estudianteId: 'demo_estudiante',
                  nombreAlumno: 'Alumno Inicial',
                  gradoSeleccionado: 'Inicial 1',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.school),
              title: const Text('Perfil PRIMARIA'),
              onTap: () {
                Navigator.pop(context);
                _irAPerfil(
                  nivel: _Nivel.primaria,
                  estudianteId: 'demo_estudiante',
                  nombreAlumno: 'Alumno Primaria',
                  gradoSeleccionado: '5to A',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Perfil SECUNDARIA'),
              onTap: () {
                Navigator.pop(context);
                _irAPerfil(
                  nivel: _Nivel.secundaria,
                  estudianteId: 'demo_estudiante',
                  nombreAlumno: 'Alumno Secundaria',
                  gradoSeleccionado: '2do B',
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final azul = Colors.blue.shade900;
    final escuelaNombre = (widget.escuela.nombre ?? '').toString().trim();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: azul,
        title: const Text(''),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _gradosCol.orderBy('name').snapshots(),
        builder: (context, snapGrades) {
          if (snapGrades.hasError) {
            return Center(
              child: Text('Error cargando grados: ${snapGrades.error}'),
            );
          }

          final docs = snapGrades.data?.docs ?? [];

          // Convertir docs -> items (usa nivel del doc)
          final items = docs.map((d) {
            final data = d.data();

            final name = (data['name'] ?? data['grado'] ?? data['nombre'] ?? '')
                .toString()
                .trim();
            if (name.isEmpty) return null;

            final explicitRaw =
                data['nivel'] ?? data['level'] ?? data['nivelIndex'];
            final explicitNivel = _nivelFromAny(explicitRaw);
            final hasExplicit = explicitRaw != null && explicitNivel != null;

            final nivel = explicitNivel ??
                _nivelFromAny(data['nivel']) ??
                _nivelFromAny(data['level']);

            // si no hay nada explícito, fallback SOLO para nombres tipo "1ro Primaria"
            final finalNivel = nivel ??
                _nivelFromAny(explicitRaw) ??
                (name.contains(RegExp(r'(inicial|primaria|secundaria)',
                        caseSensitive: false))
                    ? _nivelPorNombreFallback(name)
                    : null);

            return _GradeItem(
                name: name, nivel: finalNivel, hasExplicitNivel: hasExplicit);
          }).whereType<_GradeItem>().toList();

          // Si existe al menos un grado con nivel explícito, filtramos por ese nivel.
          final hayNivelExplicito =
              items.any((x) => x.hasExplicitNivel || x.nivel != null);

          List<String> gradesNivel;
          if (items.isNotEmpty && hayNivelExplicito) {
            gradesNivel = items
                .where((x) => x.nivel == _nivelSel)
                .map((x) => x.name)
                .toSet()
                .toList()
              ..sort();
          } else if (items.isNotEmpty) {
            // Si no hay nivel en docs, mostramos TODOS (mejor que vacío)
            gradesNivel =
                items.map((x) => x.name).toSet().toList()..sort();
          } else {
            // si no hay grados en Firestore, fallback
            gradesNivel = _gradosFallbackRD
                .where((g) => _nivelPorNombreFallback(g) == _nivelSel)
                .toList();
          }

          // sincroniza seleccionado
          if (_gradoSel != null && !gradesNivel.contains(_gradoSel)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _gradoSel = null);
            });
          }
          if (_gradoSel == null && gradesNivel.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _gradoSel = gradesNivel.first);
            });
          }

          final noHayGrados = gradesNivel.isEmpty;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(colors: [azul, Colors.blue.shade700]),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onLongPress: _accesoRapidoDebug,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset('assets/LogoAlumnos.png'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              escuelaNombre.isEmpty ? '—' : escuelaNombre,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Área de estudiantes',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if (kDebugMode)
                        IconButton(
                          tooltip: 'Acceso rápido (DEBUG)',
                          onPressed: _accesoRapidoDebug,
                          icon: const Icon(Icons.bolt, color: Colors.orange),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Nivel
                DropdownButtonFormField<_Nivel>(
                  value: _nivelSel,
                  decoration: InputDecoration(
                    labelText: 'Nivel',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: _Nivel.inicial, child: Text('Inicial')),
                    DropdownMenuItem(value: _Nivel.primaria, child: Text('Primaria')),
                    DropdownMenuItem(value: _Nivel.secundaria, child: Text('Secundaria')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _nivelSel = v;
                      _gradoSel = null;
                      _errorText = null;
                    });
                  },
                ),

                const SizedBox(height: 12),

                // Aula/Grado
                DropdownButtonFormField<String>(
                  value: noHayGrados ? null : _gradoSel,
                  decoration: InputDecoration(
                    labelText: 'Aula / Grado',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: gradesNivel
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: noHayGrados
                      ? null
                      : (v) => setState(() {
                            _gradoSel = v;
                            _errorText = null;
                          }),
                ),

                if (noHayGrados) ...[
                  const SizedBox(height: 10),
                  Text(
                    'No hay grados para este nivel.\n'
                    'Pídele al admin que los cree y que cada grado tenga: nivel = "inicial|primaria|secundaria".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],

                const SizedBox(height: 12),

                // Nombres / Apellidos
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nombresCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nombres',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) {
                          final n = _normalizeName(v);
                          _nombresCtrl.value = _nombresCtrl.value.copyWith(
                            text: n,
                            selection: TextSelection.collapsed(offset: n.length),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _apellidosCtrl,
                        decoration: InputDecoration(
                          labelText: 'Apellidos',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (v) {
                          final n = _normalizeName(v);
                          _apellidosCtrl.value = _apellidosCtrl.value.copyWith(
                            text: n,
                            selection: TextSelection.collapsed(offset: n.length),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Número + contraseña
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _numeroCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Número de lista',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _contrasenaCtrl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onSubmitted: (_) => _validarDatos(),
                      ),
                    ),
                  ],
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(_errorText!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_loading || noHayGrados) ? null : _validarDatos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Entrar',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
