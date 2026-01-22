// lib/alumnos/screens/alumnos.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'perfil_inicial_screen.dart';
import 'perfil_primaria_screen.dart';
import 'perfil_secundaria_screen.dart';

enum _Nivel { inicial, primaria, secundaria }

class _AlumnoItem {
  final String id;
  final String nombres;
  final String apellidos;
  final String grado;
  final String? nivelDb;
  final String matricula;

  const _AlumnoItem({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.grado,
    required this.nivelDb,
    required this.matricula,
  });

  String get displayName {
    final base = '${apellidos.trim()}, ${nombres.trim()}'.trim();
    final num = matricula.trim();
    return num.isEmpty ? base : '$base  •  #$num';
  }
}

String _step = '';

Future<T> _guard<T>(String step, Future<T> Function() fn) async {
  _step = step;
  return await fn();
}

class AlumnosScreen extends StatefulWidget {
  final Escuela escuela;
  const AlumnosScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AlumnosScreen> createState() => _AlumnosScreenState();
}

class _AlumnosScreenState extends State<AlumnosScreen> {
  late final String _schoolId;

  // ----- UI / estados -----
  bool _loading = false; // botón principal (google / entrar)
  bool _loadingList = false; // leyendo alumnos permitidos
  String? _errorText;

  // 2 pasos:
  // 1) Google + permisos -> carga _alumnosAll
  // 2) Selección alumno (si hay varios) + entrar
  bool _accessReady = false; // true cuando ya cargamos alumnos permitidos

  // Filtros
  String? _gradoSel; // null = sin filtro
  _AlumnoItem? _alumnoSel;

  TextEditingController? _nameCtrl;

  // Data
  List<String> _catalogoGrados = []; // SOLO para mapa de nivel; NO para mostrar al padre
  final Map<String, _Nivel> _nivelPorGradoKey = {};
  List<_AlumnoItem> _alumnosAll = [];

  // Permisos por correo
  Set<String> _allowedIds = <String>{};

  // ---------------- Firestore refs ----------------
  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _alumnosCol =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('alumnos');

  CollectionReference<Map<String, dynamic>> get _estudiantesLegacyCol =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('estudiantes');

  CollectionReference<Map<String, dynamic>> get _alumnosLoginCol =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('alumnos_login');

  DocumentReference<Map<String, dynamic>> get _usersDoc =>
      FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid ?? '__no_uid__');

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _ensureSchoolDocId(raw);

    // Carga catálogo SOLO para mapear nivel por grado (no para mostrar al tutor).
    _cargarCatalogoGrados();
  }

  // ---------------- Helpers ----------------
  String _ensureSchoolDocId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    return id.startsWith('eduproapp_admin_') ? id : 'eduproapp_admin_$id';
  }

  String _key(String s) {
    return s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\sñáéíóúü]'), '');
  }

  _Nivel? _nivelFromAny(dynamic raw) {
    if (raw == null) return null;

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
    if (s.contains('inicial')) return _Nivel.inicial;
    if (s.contains('primaria')) return _Nivel.primaria;
    if (s.contains('secundaria')) return _Nivel.secundaria;
    return null;
  }

  _Nivel _nivelFallbackPorGrado(String grado) {
    final g = grado.toLowerCase();
    if (g.contains('ini')) return _Nivel.inicial;
    if (g.contains('sec')) return _Nivel.secundaria;
    return _Nivel.primaria;
  }

  Future<void> _setError(String msg) async {
    if (!mounted) return;
    setState(() => _errorText = msg);
  }

  Set<String> _extractStudentIds(Map<String, dynamic> data) {
    dynamic raw =
        data['studentIds'] ?? data['studentsIds'] ?? data['alumnoIds'] ?? data['alumnosIds'];
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toSet();
    }
    return <String>{};
  }

  // ---------------- Cargar grados (para mapa de nivel) ----------------
  Future<void> _cargarCatalogoGrados() async {
    try {
      final snap = await _gradosCol.get();

      final grados = <String>{};
      final mapa = <String, _Nivel>{};

      for (final d in snap.docs) {
        final m = d.data();
        final name = (m['name'] ?? m['grado'] ?? m['nombre'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        grados.add(name);

        final nivel = _nivelFromAny(m['nivel'] ?? m['level'] ?? m['nivelIndex']);
        if (nivel != null) {
          mapa[_key(name)] = nivel;
        }
      }

      final list = grados.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _catalogoGrados = list;
        _nivelPorGradoKey
          ..clear()
          ..addAll(mapa);
      });
    } catch (_) {
      // silencioso
    }
  }

  // ---------------- Cargar alumnos permitidos ----------------
  Future<void> _cargarAlumnosPermitidos(Set<String> allowedIds) async {
    if (_loadingList) return;

    setState(() {
      _loadingList = true;
      _errorText = null;
    });

    try {
      final out = <_AlumnoItem>[];

      for (final id in allowedIds) {
        if (id.trim().isEmpty) continue;

        DocumentSnapshot<Map<String, dynamic>> s = await _alumnosCol.doc(id).get();
        if (!s.exists) {
          s = await _estudiantesLegacyCol.doc(id).get();
        }
        if (!s.exists) continue;

        final m = s.data() ?? {};
        final nombres = (m['nombres'] ?? '').toString().trim();
        final apellidos = (m['apellidos'] ?? '').toString().trim();
        final grado = (m['grado'] ?? '').toString().trim();
        final nivel = (m['nivel'] ?? m['level'] ?? m['nivelIndex']);
        final matricula =
            (m['matricula'] ?? m['numero'] ?? m['numeroLista'] ?? '').toString().trim();

        out.add(_AlumnoItem(
          id: s.id,
          nombres: nombres,
          apellidos: apellidos,
          grado: grado,
          nivelDb: nivel == null ? null : nivel.toString().trim(),
          matricula: matricula,
        ));
      }

      out.sort((a, b) {
        final aa = '${a.apellidos} ${a.nombres}'.toLowerCase();
        final bb = '${b.apellidos} ${b.nombres}'.toLowerCase();
        return aa.compareTo(bb);
      });

      if (!mounted) return;
      setState(() => _alumnosAll = out);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _setError(
          'Permiso denegado leyendo alumnos permitidos.\n'
          'Verifica rules para leer schools/{schoolId}/alumnos/{alumnoId} y alumnos_login.',
        );
      } else {
        await _setError('Error cargando alumnos: ${e.code}');
      }
    } catch (e) {
      await _setError('Error cargando alumnos: $e');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  // ✅ Grados SOLO desde los alumnos permitidos (privacidad)
  List<String> _gradosDesdeAlumnos() {
    final s = <String>{};
    for (final a in _alumnosAll) {
      final g = a.grado.trim();
      if (g.isNotEmpty) s.add(g);
    }
    final list = s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<_AlumnoItem> _alumnosVisibles(String queryText) {
    final gradoKeySel = _key(_gradoSel ?? '');
    final q = _key(queryText);

    Iterable<_AlumnoItem> base = _alumnosAll;

    if ((_gradoSel ?? '').trim().isNotEmpty) {
      base = base.where((a) => _key(a.grado) == gradoKeySel);
    }

    if (q.isNotEmpty) {
      base = base.where((a) {
        final k1 = _key('${a.nombres} ${a.apellidos}');
        final k2 = _key('${a.apellidos} ${a.nombres}');
        return k1.contains(q) || k2.contains(q);
      });
    }

    return base.take(60).toList();
  }

  Future<_AlumnoItem?> _seleccionarAlumnoModal() async {
    return showModalBottomSheet<_AlumnoItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        final ctrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = ctrl.text;
            final list = _alumnosVisibles(q);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar alumno',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final a = list[i];
                          return ListTile(
                            title: Text(a.displayName),
                            subtitle: Text(a.grado),
                            onTap: () => Navigator.pop(ctx, a),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- Auth (Google) ----------------
  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return await auth.signInWithPopup(provider);
    }

    final google = GoogleSignIn.instance;
    final gUser = await google.authenticate();
    final gAuth = gUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
    );

    return await auth.signInWithCredential(credential);
  }


  // ---------------- Perfil ----------------
  void _irAPerfil({
    required _Nivel nivel,
    required String alumnoId,
    required String nombreAlumno,
    required String gradoSeleccionado,
  }) {
    Widget screen;
    switch (nivel) {
      case _Nivel.inicial:
        screen = PerfilInicialScreen(
          escuela: widget.escuela,
          estudianteId: alumnoId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
      case _Nivel.primaria:
        screen = PerfilPrimariaScreen(
          escuela: widget.escuela,
          estudianteId: alumnoId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
      case _Nivel.secundaria:
        screen = PerfilSecundariaScreen(
          escuela: widget.escuela,
          estudianteId: alumnoId,
          nombreAlumno: nombreAlumno,
          gradoSeleccionado: gradoSeleccionado,
        );
        break;
    }

    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  // ---------------- Paso 1: Google + permisos + cargar lista ----------------
  Future<void> _continuarConGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _loading = true;
    });

    try {
      // 1) Google sign-in
      final cred = await _signInWithGoogle();
      final user = cred.user;
      if (user == null) {
        await _setError('No se pudo completar el inicio de sesión.');
        return;
      }

      final email = (user.email ?? '').trim();
      if (email.isEmpty) {
        await _setError('Tu cuenta de Google no tiene email disponible.');
        return;
      }
      final emailLower = email.toLowerCase().trim();

      // 1.5) organigrama (si tus rules lo exigen)
 //     final orgRef = FirebaseFirestore.instance.collection('organigrama').doc(user.uid);
 //     await _guard(
 //       'set organigrama/{uid}',
//        () => orgRef.set({
  //        'role': 'student',
   //       'accessType': 'google_student_or_tutor',
    //      'schoolId': _schoolId,
    //      'enabled': true,
   //       'email': emailLower,
     //     'updatedAt': FieldValue.serverTimestamp(),
      //    'createdAt': FieldValue.serverTimestamp(),
      //  }, SetOptions(merge: true)),
     // );

      // 2) validar acceso por email
      final loginSnap = await _guard(
        'get alumnos_login/{email}',
        () => _alumnosLoginCol.doc(emailLower).get(),
      );

      if (!loginSnap.exists) {
        // resetea UI para que NO quede “activado” nada
        if (mounted) {
          setState(() {
            _accessReady = false;
            _alumnosAll = [];
            _gradoSel = null;
            _alumnoSel = null;
            _allowedIds = <String>{};
            _nameCtrl?.clear();
          });
        }
        await _setError(
          'Aun no te has registrado.\n'
          'comuniquese con la administacuion escolar.',
        );
        return;
      }

      final data = loginSnap.data() ?? {};
      _allowedIds = _extractStudentIds(data);

      if (_allowedIds.isEmpty) {
        await _setError('Tu acceso existe, pero no tiene alumnos asignados.');
        return;
      }

      // ✅ bootstrap users/{uid} para evitar permission-denied luego en "Entrar"
      //await _ensureUserDocExists(
        //user: user,
        //emailLower: emailLower,
       // allowedIds: _allowedIds,
      //);

      // 3) cargar alumnos permitidos
      await _cargarAlumnosPermitidos(_allowedIds);

      if (_alumnosAll.isEmpty) {
        await _setError('No se encontraron alumnos para este acceso.');
        return;
      }

      // 4) listo para selección (y por privacidad, grados vendrán SOLO de _alumnosAll)
      if (!mounted) return;
      setState(() {
        _accessReady = true;
        _gradoSel = null; // por defecto sin filtro
        _alumnoSel = null;
        _nameCtrl?.clear();
      });

      // 5) si solo hay 1 alumno, entrar directo
    //  if (_alumnosAll.length == 1) {
    //    setState(() => _alumnoSel = _alumnosAll.first);
   //     await _entrarConSeleccion();
   //   }

    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _setError(
          'Permiso denegado.\n'
          'Paso actual: $_step\n'
          'Revisa rules para:\n'
          '1) crear/actualizar /organigrama/{uid}\n'
          '2) leer schools/{schoolId}/alumnos_login/{email}\n'
          '3) leer schools/{schoolId}/alumnos/{alumnoId}\n'
          '4) crear /users/{uid} (bootstrap student)',
        );
      } else {
        await _setError('Error: ${e.code}\nPaso: $_step');
      }
    } catch (e) {
      await _setError('Error: $e\nPaso: $_step');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- Paso 2: validar selección + entrar ----------------
  Future<void> _entrarConSeleccion() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await _setError('No hay sesión activa. Presiona "Continuar con Google".');
        return;
      }

      if (_alumnosAll.isEmpty) {
        await _setError('No hay alumnos cargados. Presiona "Continuar con Google".');
        return;
      }

      // si hay varios y no han seleccionado, pedimos
  if (_alumnoSel == null) {
  if (_alumnosAll.length == 1) {
    setState(() => _alumnoSel = _alumnosAll.first);
  } else {
    await _setError('Selecciona un alumno antes de entrar.');
    return;
  }
}


      final selFinal = _alumnoSel!;
      if (!_allowedIds.contains(selFinal.id)) {
        await _setError(
          'Este correo NO tiene acceso a ese alumno.\n'
          'Selecciona el alumno correcto o pide al admin que agregue este correo.',
        );
        return;
      }

      // leer alumno real
      DocumentSnapshot<Map<String, dynamic>> alumnoSnap =
          await _guard('get alumnos/{alumnoId}', () => _alumnosCol.doc(selFinal.id).get());
      if (!alumnoSnap.exists) {
        alumnoSnap = await _guard(
          'get estudiantes legacy/{alumnoId}',
          () => _estudiantesLegacyCol.doc(selFinal.id).get(),
        );
      }
      if (!alumnoSnap.exists) {
        await _setError('No se encontró el alumno en la escuela.');
        return;
      }

      final a = alumnoSnap.data() ?? {};
      final nombres = (a['nombres'] ?? selFinal.nombres).toString().trim();
      final apellidos = (a['apellidos'] ?? selFinal.apellidos).toString().trim();
      final grado = (a['grado'] ?? selFinal.grado).toString().trim();

      if (grado.isEmpty) {
        await _setError('El alumno no tiene grado definido.');
        return;
      }

      // activo / bloqueado
      final status = (a['status'] ?? a['estado'] ?? 'activo').toString().toLowerCase().trim();
      final enabled = (a['enabled'] is bool) ? (a['enabled'] as bool) : true;
      final isActivo = enabled && (status.isEmpty || status == 'activo');

      if (!isActivo) {
        final msg = (status == 'pendiente')
            ? 'Este alumno está PENDIENTE de aprobación. Habla con el administrador.'
            : 'Este alumno está BLOQUEADO. Habla con el administrador.';
        await _setError(msg);
        return;
      }

      // coherencia con grado elegido (si eligieron)
      final gradoSel = (_gradoSel ?? '').trim();
      if (gradoSel.isNotEmpty && _key(gradoSel) != _key(grado)) {
        await _setError(
          'El alumno seleccionado no pertenece al grado elegido.\n'
          'Cambia el grado o el alumno.',
        );
        return;
      }

      // nivel
      final nivel = _nivelFromAny(a['nivel'] ?? a['level'] ?? a['nivelIndex']) ??
          _nivelPorGradoKey[_key(grado)] ??
          _nivelFallbackPorGrado(grado);

      final nombreAlumno = ('$nombres $apellidos').trim().isEmpty
          ? selFinal.displayName
          : ('$nombres $apellidos').trim();


      // navegar
      _irAPerfil(
        nivel: nivel,
        alumnoId: selFinal.id,
        nombreAlumno: nombreAlumno,
        gradoSeleccionado: grado,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _setError('Error: permission-denied\nPaso: $_step');
      } else {
        await _setError('Error: ${e.code}\nPaso: $_step');
      }
    } catch (e) {
      await _setError('Error: $e\nPaso: $_step');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- DEBUG ----------------
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
                  alumnoId: 'demo_estudiante',
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
                  alumnoId: 'demo_estudiante',
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
                  alumnoId: 'demo_estudiante',
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

    // ✅ PRIVACIDAD:
    // - Antes de login: no mostramos grados (y el control está deshabilitado igual)
    // - Luego de login: SOLO grados de los alumnos permitidos
    final gradosUI = _accessReady ? _gradosDesdeAlumnos() : <String>[];

    // si el grado seleccionado ya no existe, limpiar
    if ((_gradoSel ?? '').trim().isNotEmpty && gradosUI.isNotEmpty) {
      final ok = gradosUI.any((g) => _key(g) == _key(_gradoSel!));
      if (!ok) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _gradoSel = null;
            _alumnoSel = null;
            _nameCtrl?.clear();
          });
        });
      }
    }

    final filtrosHabilitados = _accessReady && !_loadingList && _alumnosAll.isNotEmpty;

    final botonTexto = !_accessReady ? 'Continuar con Google' : 'Entrar';
    final botonOnPressed = _loading
        ? null
        : (!_accessReady ? _continuarConGoogle : _entrarConSeleccion);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: azul,
        title: const Text(''),
      ),
      body: Padding(
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
                    onLongPress: null,  // esto GestureDetector( en lugar de null
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
                        Text(
                          _loadingList
                              ? 'Cargando alumnos…'
                              : (!_accessReady
                                  ? 'Primero continúa con Google para cargar tus alumnos'
                                  : 'Selecciona grado y alumno, luego entra'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (kDebugMode)
                    IconButton(
                      tooltip: 'Acceso rápido (DEBUG)',
                      onPressed: null,  //_accesoRapidoDebug, esto en lugar de null
                      icon: const Icon(Icons.bolt, color: Colors.orange),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Grado
            IgnorePointer(
              ignoring: !filtrosHabilitados,
              child: Opacity(
                opacity: filtrosHabilitados ? 1 : 0.5,
                child: DropdownButtonFormField<String?>(
                  value: (_gradoSel ?? '').trim().isEmpty ? null : _gradoSel,
                  decoration: InputDecoration(
                    labelText: 'Grado',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Sin filtro (mis grados) —'),
                    ),
                    ...gradosUI.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g,
                        child: Text(g),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _gradoSel = v;
                      _alumnoSel = null;
                      _nameCtrl?.clear();
                      _errorText = null;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Nombre
            IgnorePointer(
              ignoring: !filtrosHabilitados,
              child: Opacity(
                opacity: filtrosHabilitados ? 1 : 0.5,
                child: Autocomplete<_AlumnoItem>(
                  displayStringForOption: (o) => o.displayName,
                  optionsBuilder: (text) {
                    if (!filtrosHabilitados) return const Iterable<_AlumnoItem>.empty();
                    final q = text.text;
                    return _alumnosVisibles(q);
                  },
                  onSelected: (o) {
                    setState(() {
                      _alumnoSel = o;
                      _errorText = null;
                    });
                    _nameCtrl?.text = o.displayName;
                    _nameCtrl?.selection = TextSelection.collapsed(
                      offset: _nameCtrl!.text.length,
                    );
                  },
                  fieldViewBuilder: (context, ctrl, focusNode, onFieldSubmitted) {
                    _nameCtrl = ctrl;

                    return TextFormField(
                      controller: ctrl,
                      focusNode: focusNode,
                      onChanged: (v) {
                        if (_alumnoSel != null && v != _alumnoSel!.displayName) {
                          setState(() => _alumnoSel = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Nombre del alumno',
                        hintText: !_accessReady
                            ? 'Primero continúa con Google'
                            : ((_gradoSel ?? '').trim().isEmpty)
                                ? 'Escribe para buscar (mis alumnos)'
                                : 'Escribe para buscar (en el grado)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: _loadingList
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  ctrl.clear();
                                  setState(() => _alumnoSel = null);
                                },
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              !_accessReady
                  ? 'Tip: toca "Continuar con Google" para cargar SOLO tus alumnos.'
                  : ((_gradoSel ?? '').trim().isEmpty)
                      ? 'Tip: elige un grado para filtrar más rápido.'
                      : 'Nombres filtrados por el grado seleccionado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),

            if (kDebugMode) ...[
              const SizedBox(height: 6),
              Text(
                'Step: $_step | AccessReady: $_accessReady | Alumnos: ${_alumnosAll.length}'
                '${((_gradoSel ?? '').trim().isEmpty) ? '' : ' | en grado: ${_alumnosVisibles("").length}'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],

            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: botonOnPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _loading ? 'Procesando...' : botonTexto,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
