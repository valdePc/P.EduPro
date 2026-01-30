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
  // 2) Selección alumno + entrar
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
    dynamic raw = data['studentIds'] ??
        data['studentsIds'] ??
        data['alumnoIds'] ??
        data['alumnosIds'];
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

  // ---------------- Auth (Google) ----------------
  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;

    // ✅ Web: popup (no usa accessToken)
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return await auth.signInWithPopup(provider);
    }

    // ✅ Mobile/desktop: google_sign_in v7+
    final google = GoogleSignIn.instance;
    await google.initialize();

    final gUser = await google.authenticate();
    final gAuth = gUser.authentication;

    final idToken = gAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google no devolvió idToken.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
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

      // 2) validar acceso por email
      final loginSnap = await _guard(
        'get alumnos_login/{email}',
        () => _alumnosLoginCol.doc(emailLower).get(),
      );

      if (!loginSnap.exists) {
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
          'Aún no te has registrado.\n'
          'Comunícate con la administración escolar.',
        );
        return;
      }

      final data = loginSnap.data() ?? {};
      _allowedIds = _extractStudentIds(data);

      if (_allowedIds.isEmpty) {
        await _setError('Tu acceso existe, pero no tiene alumnos asignados.');
        return;
      }

      // 3) cargar alumnos permitidos
      await _cargarAlumnosPermitidos(_allowedIds);

      if (_alumnosAll.isEmpty) {
        await _setError('No se encontraron alumnos para este acceso.');
        return;
      }

      // 4) listo para selección
      if (!mounted) return;
      setState(() {
        _accessReady = true;
        _gradoSel = null;
        _alumnoSel = null;
        _nameCtrl?.clear();
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _setError(
          'Permiso denegado.\n'
          'Paso actual: $_step\n'
          'Revisa rules para:\n'
          '1) leer schools/{schoolId}/alumnos_login/{email}\n'
          '2) leer schools/{schoolId}/alumnos/{alumnoId}',
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

  // ---------------- UI helpers (solo estética) ----------------
  Widget _statusPill({
    required Color bg,
    required IconData icon,
    required String text,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF0D47A1);
    const azul2 = Color(0xFF1976D2);
    const naranja = Color(0xFFFFA000);
    const bg = Color(0xFFF4F7FB);

    final escuelaNombre = (widget.escuela.nombre ?? '').toString().trim();

    // ✅ PRIVACIDAD:
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
    final botonOnPressed =
        _loading ? null : (!_accessReady ? _continuarConGoogle : _entrarConSeleccion);

    final theme = Theme.of(context);
    final localTheme = theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: azul, width: 1.8),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700),
      ),
    );

    return Theme(
      data: localTheme,
      child: Scaffold(
        backgroundColor: bg,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(''),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // HERO HEADER más pro (sin tocar tu lógica)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [azul, azul2],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 22,
                            offset: Offset(0, 10),
                            color: Color(0x26000000),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // decor (solo UI)
                          Positioned(
                            right: -30,
                            top: -40,
                            child: Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: -20,
                            bottom: -35,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                          ),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Logo con borde + sombra
                              GestureDetector(
                                onLongPress: kDebugMode ? _accesoRapidoDebug : null,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: const [
                                      BoxShadow(
                                        blurRadius: 16,
                                        offset: Offset(0, 8),
                                        color: Color(0x22000000),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  child: Image.asset('assets/LogoAlumnos.png'),
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
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Text(
                                        _loadingList
                                            ? 'Cargando alumnos…'
                                            : (!_accessReady
                                                ? 'Inicia con Google para cargar tus alumnos'
                                                : 'Elige grado y alumno, luego entra'),
                                        key: ValueKey('${_loadingList}_${_accessReady}'),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.82),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _statusPill(
                                          bg: Colors.white.withOpacity(0.12),
                                          icon: Icons.lock,
                                          text: 'Privado',
                                          fg: Colors.white,
                                        ),
                                        _statusPill(
                                          bg: Colors.white.withOpacity(0.12),
                                          icon: _accessReady ? Icons.verified : Icons.info_outline,
                                          text: _accessReady ? 'Acceso listo' : 'Paso 1',
                                          fg: Colors.white,
                                        ),
                                        if (_loadingList)
                                          _statusPill(
                                            bg: Colors.white.withOpacity(0.12),
                                            icon: Icons.sync,
                                            text: 'Sincronizando',
                                            fg: Colors.white,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              if (kDebugMode)
                                IconButton(
                                  tooltip: 'Acceso rápido (DEBUG)',
                                  onPressed: _accesoRapidoDebug,
                                  icon: const Icon(Icons.bolt, color: naranja),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // CARD FORM (más elegante, misma funcionalidad)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 22,
                            offset: Offset(0, 10),
                            color: Color(0x16000000),
                          ),
                        ],
                      ),
                      child: Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_circle, color: Colors.grey.shade800),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'EduAlumn',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                  ),
                                  if (_accessReady)
                                    _statusPill(
                                      bg: const Color(0xFFE9F7EF),
                                      icon: Icons.check_circle,
                                      text: 'Listo',
                                      fg: const Color(0xFF1E7F3B),
                                    )
                                  else
                                    _statusPill(
                                      bg: const Color(0xFFFFF5E6),
                                      icon: Icons.login,
                                      text: 'Paso 1',
                                      fg: const Color(0xFF8A5B00),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Divider(color: Colors.grey.shade200, height: 1),
                              const SizedBox(height: 14),

                              // Grado
                              IgnorePointer(
                                ignoring: !filtrosHabilitados,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  opacity: filtrosHabilitados ? 1 : 0.55,
                                  child: DropdownButtonFormField<String?>(
                                    value: (_gradoSel ?? '').trim().isEmpty ? null : _gradoSel,
                                    decoration: const InputDecoration(
                                      labelText: 'Grado',
                                      prefixIcon: Icon(Icons.class_),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('— Sin filtro —'),
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

                              // Nombre alumno (Autocomplete)
                              IgnorePointer(
                                ignoring: !filtrosHabilitados,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  opacity: filtrosHabilitados ? 1 : 0.55,
                                  child: Autocomplete<_AlumnoItem>(
                                    displayStringForOption: (o) => o.displayName,
                                    optionsBuilder: (text) {
                                      if (!filtrosHabilitados) {
                                        return const Iterable<_AlumnoItem>.empty();
                                      }
                                      return _alumnosVisibles(text.text);
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
                                    fieldViewBuilder:
                                        (context, ctrl, focusNode, onFieldSubmitted) {
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
                                          prefixIcon: const Icon(Icons.search),
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
                                                  tooltip: 'Limpiar',
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

                              const SizedBox(height: 12),

                              // Tips + privacidad
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F9FC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0x11000000)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.shield_outlined, color: Colors.grey.shade700),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        !_accessReady
                                            ? 'Alta Seguridad'
                                            : ((_gradoSel ?? '').trim().isEmpty)
                                                ? 'Tip: elige un grado para filtrar más rápido.'
                                                : 'Mostrando alumnos dentro del grado seleccionado.',
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (kDebugMode) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Step: $_step | AccessReady: $_accessReady | Alumnos: ${_alumnosAll.length}'
                                  '${((_gradoSel ?? '').trim().isEmpty) ? '' : ' | en grado: ${_alumnosVisibles("").length}'}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ],

                              // Error animado (más elegante)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: (_errorText == null)
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFEDEE),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: const Color(0x33D32F2F)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.error_outline, color: Colors.red),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _errorText!,
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),

                              const SizedBox(height: 14),

                              // Botón principal (misma acción, mejor presencia)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: botonOnPressed,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: naranja,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ).copyWith(
                                    // sombra suave sin cambiar lógica
                                    shadowColor: WidgetStateProperty.all(const Color(0x22000000)),
                                  ),
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Icon(!_accessReady ? Icons.g_mobiledata : Icons.login),
                                  label: Text(
                                    _loading ? 'Procesando...' : botonTexto,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // microcopy final (solo UI)
                              Text(
                                !_accessReady
                                    ? '¿No ves tu acceso? Pide a la administración que registre tu correo.'
                                    : 'Si tienes varios alumnos, asegúrate de elegir el correcto antes de entrar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
