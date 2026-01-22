// lib/admin_escolar/screens/registro_equipo_screen.dart
import 'dart:math'; // (si no lo usas puedes quitarlo; no rompe)
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // (si no lo usas puedes quitarlo)
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// 👇 IMPORTA TU PANTALLA DE GRADOS
import 'A_grados.dart';

// ✅ Colores a nivel de archivo
const Color _blue = Color(0xFF0D47A1);
const Color _orange = Color(0xFFFFA000);

/// ✅
enum EstadoAlumno { activo, pendiente, bloqueado }
enum NivelAcademico { inicial, primaria, secundaria }

String nivelToDb(NivelAcademico n) {
  switch (n) {
    case NivelAcademico.inicial:
      return 'inicial';
    case NivelAcademico.primaria:
      return 'primaria';
    case NivelAcademico.secundaria:
      return 'secundaria';
  }
}

/// ✅ Estado del alumno (login + control)
String estadoToDb(EstadoAlumno e) {
  switch (e) {
    case EstadoAlumno.activo:
      return 'activo';
    case EstadoAlumno.pendiente:
      return 'pendiente';
    case EstadoAlumno.bloqueado:
      return 'bloqueado';
  }
}

EstadoAlumno estadoFromDb(String s) {
  final v = s.trim().toLowerCase();
  if (v == 'pendiente') return EstadoAlumno.pendiente;
  if (v == 'bloqueado') return EstadoAlumno.bloqueado;
  return EstadoAlumno.activo;
}

String estadoLabel(EstadoAlumno e) {
  switch (e) {
    case EstadoAlumno.activo:
      return 'Activo';
    case EstadoAlumno.pendiente:
      return 'Pendiente';
    case EstadoAlumno.bloqueado:
      return 'Bloqueado';
  }
}

IconData estadoIcon(EstadoAlumno e) {
  switch (e) {
    case EstadoAlumno.activo:
      return Icons.check_circle;
    case EstadoAlumno.pendiente:
      return Icons.hourglass_top;
    case EstadoAlumno.bloqueado:
      return Icons.block;
  }
}

Color estadoColor(EstadoAlumno e) {
  switch (e) {
    case EstadoAlumno.activo:
      return Colors.green;
    case EstadoAlumno.pendiente:
      return Colors.amber;
    case EstadoAlumno.bloqueado:
      return Colors.red;
  }
}

String nivelLabel(NivelAcademico n) {
  switch (n) {
    case NivelAcademico.inicial:
      return 'Inicial';
    case NivelAcademico.primaria:
      return 'Primaria';
    case NivelAcademico.secundaria:
      return 'Secundaria';
  }
}

IconData nivelIcon(NivelAcademico n) {
  switch (n) {
    case NivelAcademico.inicial:
      return Icons.child_care;
    case NivelAcademico.primaria:
      return Icons.menu_book;
    case NivelAcademico.secundaria:
      return Icons.school;
  }
}

int _leadingNumberOrBig(String s) {
  final m = RegExp(r'^\s*(\d+)').firstMatch(s);
  if (m == null) return 999999;
  return int.tryParse(m.group(1)!) ?? 999999;
}

/// ✅ Entrada dinámica de accesos por correo (email + usuario)
class _AccessEmailEntry {
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController userCtrl = TextEditingController();

  void dispose() {
    emailCtrl.dispose();
    userCtrl.dispose();
  }
}

class RegistroEquipoScreen extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride; // ✅ NUEVO

  const RegistroEquipoScreen({
    super.key,
    required this.escuela,
    this.schoolIdOverride, // ✅ NUEVO
  });

  @override
  State<RegistroEquipoScreen> createState() => _RegistroEquipoScreenState();
}

class _RegistroEquipoScreenState extends State<RegistroEquipoScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ NIVEL (STATE REAL)
  NivelAcademico _nivelSel = NivelAcademico.primaria;

  // ✅ ESTADO (por defecto: ACTIVO)
  EstadoAlumno _estadoSel = EstadoAlumno.activo;

  void _setEstado(EstadoAlumno e) {
    setState(() => _estadoSel = e);
  }

  // ✅ TANDA (STATE REAL)
  String? _tandaSel;
  static const List<String> _tandas = ['Mañana', 'Tarde', 'Nocturna'];

  late final String _schoolId;

  // ----- UI State -----
  bool _saving = false;
  bool _hydratedConfig = false;

  // Config (viene de config/registro)
  bool _permitirFotoAlumno = true;

  // Búsqueda en lista
  final _searchListCtrl = TextEditingController();
  String _searchList = '';

  // ----- FORM -----
  final _formKey = GlobalKey<FormState>();

  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _matriculaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _observCtrl = TextEditingController();

  // DOB/Edad
  DateTime? _fechaNacimiento;
  final _fechaCtrl = TextEditingController();
  final _edadCtrl = TextEditingController();

  // Grado (único)
  String? _gradoSeleccionadoForm;

  // Grado para la lista
  String? _gradoSeleccionadoLista;

  // Datos tutor
  final _tutorNombreCtrl = TextEditingController();
  final _tutorParentescoCtrl = TextEditingController(text: 'Padre/Madre');
  final _tutorTelefonoCtrl = TextEditingController();
  final _tutorWhatsappCtrl = TextEditingController();
  final _tutorEmailCtrl = TextEditingController();

  // Emergencia
  final _emergNombreCtrl = TextEditingController();
  final _emergTelefonoCtrl = TextEditingController();

  // ✅ lista dinámica de correos con acceso (Google)
  final List<_AccessEmailEntry> _accessEntries = [];

  // ✅ Foto alumno
  final ImagePicker _picker = ImagePicker();
  Uint8List? _photoBytes;
  String? _photoExt;
  bool _photoPicked = false;

  @override
  void initState() {
    super.initState();

    final o = (widget.schoolIdOverride ?? '').trim();
    final raw = o.isNotEmpty ? o : normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _ensureSchoolDocId(raw);

    _tandaSel ??= _tandas.first;

    _accessEntries.add(_AccessEmailEntry());
  }

  @override
  void dispose() {
    _searchListCtrl.dispose();

    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _matriculaCtrl.dispose();
    _direccionCtrl.dispose();
    _observCtrl.dispose();

    _fechaCtrl.dispose();
    _edadCtrl.dispose();

    _tutorNombreCtrl.dispose();
    _tutorParentescoCtrl.dispose();
    _tutorTelefonoCtrl.dispose();
    _tutorWhatsappCtrl.dispose();
    _tutorEmailCtrl.dispose();

    _emergNombreCtrl.dispose();
    _emergTelefonoCtrl.dispose();

    for (final e in _accessEntries) {
      e.dispose();
    }

    super.dispose();
  }

  // ------------------ Helpers ------------------

  String _ensureSchoolDocId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    return id.startsWith('eduproapp_admin_') ? id : 'eduproapp_admin_$id';
  }

  String _normSpacesLower(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool _gradoTerminaConNivel(String gradoName, NivelAcademico nivel) {
    final s = _normSpacesLower(gradoName);

    bool endsWithWord(String w) => s.endsWith(' $w') || s.endsWith(' de $w');

    switch (nivel) {
      case NivelAcademico.inicial:
        return endsWithWord('inicial');
      case NivelAcademico.primaria:
        return endsWithWord('primaria');
      case NivelAcademico.secundaria:
        return endsWithWord('secundaria');
    }
  }

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
    final s = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r"[^a-z0-9ñáéíóúü ]"), '');
    return s;
  }

  String _normalizePhone(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[\s\-\(\)]'), '')
        .replaceAll(RegExp(r'[^0-9\+]'), '');
  }

  bool _isValidEmail(String s) {
    final v = s.trim();
    final r = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return r.hasMatch(v);
  }

  int _calcAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthday = (now.month > dob.month) ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age < 0 ? 0 : age;
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  // ------------------ Config ------------------

  DocumentReference<Map<String, dynamic>> get _registroConfigRef => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('config')
      .doc('registro');

  // ------------------ Firestore paths ------------------

  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      _db.collection('schools').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _alumnosCol =>
      _db.collection('schools').doc(_schoolId).collection('alumnos');

  CollectionReference<Map<String, dynamic>> get _alumnosGlobalCol =>
      _db.collection('alumnos_global');

  // ✅ alumnos_login (docId = emailLower)
  CollectionReference<Map<String, dynamic>> get _alumnosLoginCol =>
      _db.collection('schools').doc(_schoolId).collection('alumnos_login');

  Future<void> _irAGrados() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AGrados(escuela: widget.escuela),
      ),
    );
  }

  // ------------------ Foto alumno ------------------

  Future<void> _pickFotoAlumno() async {
    if (_saving) return;
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      final ext = (x.name.split('.').last).toLowerCase();

      setState(() {
        _photoBytes = bytes;
        _photoExt = ext.isEmpty ? 'jpg' : ext;
        _photoPicked = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo seleccionar la foto: $e')),
      );
    }
  }

  void _removeFotoAlumno() {
    if (_saving) return;
    setState(() {
      _photoBytes = null;
      _photoExt = null;
      _photoPicked = false;
    });
  }

  Future<Map<String, String?>?> _uploadFotoIfAny(String alumnoId) async {
    if (_photoBytes == null || !_photoPicked) return null;

    final safeExt = (_photoExt ?? 'jpg').replaceAll(RegExp(r'[^a-z0-9]'), '');
    final path = 'schools/$_schoolId/alumnos/$alumnoId/profile.$safeExt';

    final ref = FirebaseStorage.instance.ref().child(path);
    final contentType = (safeExt == 'png') ? 'image/png' : 'image/jpeg';

    await ref.putData(
      _photoBytes!,
      SettableMetadata(contentType: contentType),
    );

    final url = await ref.getDownloadURL();
    return {'photoUrl': url, 'photoPath': path};
  }

  // ------------------ Fecha nacimiento ------------------

  Future<void> _pickFechaNacimiento() async {
    final now = DateTime.now();
    final initial =
        _fechaNacimiento ?? DateTime(now.year - 10, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
    );

    if (picked == null) return;

    final edad = _calcAge(picked);
    setState(() {
      _fechaNacimiento = picked;
      _fechaCtrl.text = _fmtDate(picked);
      _edadCtrl.text = edad.toString();
    });
  }

  // ------------------ Duplicados ------------------

  Future<bool> _yaExistePorNumeroEnGradoYTanda({
    required String numero,
    required String grado,
    required String tanda,
    required String nivelDb,
  }) async {
    final gradoKey = _nameKey(grado);

    final a = await _alumnosCol
        .where('matricula', isEqualTo: numero)
        .where('gradoKey', isEqualTo: gradoKey)
        .where('tanda', isEqualTo: tanda)
        .where('nivel', isEqualTo: nivelDb)
        .limit(1)
        .get();

    return a.docs.isNotEmpty;
  }

  Future<bool> _yaExistePorNombreDob({
    required String nombresKey,
    required String apellidosKey,
    required DateTime dob,
  }) async {
    final a = await _alumnosCol
        .where('nombresKey', isEqualTo: nombresKey)
        .where('apellidosKey', isEqualTo: apellidosKey)
        .limit(8)
        .get();

    for (final d in a.docs) {
      final ts = d.data()['fechaNacimiento'];
      if (ts is Timestamp) {
        final other = ts.toDate();
        if (other.year == dob.year &&
            other.month == dob.month &&
            other.day == dob.day) {
          return true;
        }
      }
    }

    return false;
  }

  // ------------------ Accesos ------------------

  void _addAccessRow() {
    setState(() => _accessEntries.add(_AccessEmailEntry()));
  }

  void _removeAccessRow(int i) {
    if (_accessEntries.length <= 1) return;
    final entry = _accessEntries.removeAt(i);
    entry.dispose();
    setState(() {});
  }

  List<Map<String, dynamic>> _buildAccesosOrThrow() {
    final list = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final e in _accessEntries) {
      final email = e.emailCtrl.text.trim();
      final user = e.userCtrl.text.trim();

      if (email.isEmpty && user.isEmpty) continue;

      if (email.isEmpty || user.isEmpty) {
        throw 'Completa email y usuario en los accesos (o deja la fila vacía).';
      }
      if (!_isValidEmail(email)) {
        throw 'Email inválido en accesos: $email';
      }

      final emailLower = email.toLowerCase();
      if (seen.contains(emailLower)) {
        throw 'Email duplicado en accesos: $email';
      }
      seen.add(emailLower);

      list.add({
        'email': email,
        'emailLower': emailLower,
        'usuario': user,
      });
    }

    return list;
  }

  // ------------------ Guardar alumno ------------------

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();

    final nombres = _normalizeName(_nombresCtrl.text);
    final apellidos = _normalizeName(_apellidosCtrl.text);
    _nombresCtrl.text = nombres;
    _apellidosCtrl.text = apellidos;

    final tutorNombre = _normalizeName(_tutorNombreCtrl.text);
    _tutorNombreCtrl.text = tutorNombre;

    final tutorTel = _normalizePhone(_tutorTelefonoCtrl.text);
    final tutorWa = _normalizePhone(_tutorWhatsappCtrl.text);
    _tutorTelefonoCtrl.text = tutorTel;
    _tutorWhatsappCtrl.text = tutorWa;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_fechaNacimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la fecha de nacimiento')),
      );
      return;
    }

    final grado = (_gradoSeleccionadoForm ?? '').trim();
    if (grado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un grado')),
      );
      return;
    }

    final tanda = (_tandaSel ?? '').trim();
    if (tanda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la tanda')),
      );
      return;
    }

    // ✅ Accesos por correo (Google)
    List<Map<String, dynamic>> accesos;
    try {
      accesos = _buildAccesosOrThrow();
    } catch (msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.toString())),
      );
      return;
    }

    if (accesos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Agrega al menos un correo con acceso (email + usuario).'),
        ),
      );
      return;
    }

    final accessEmails = accesos.map((a) => a['emailLower'] as String).toList();

    final numero = _matriculaCtrl.text.trim();

    final nivelDb = nivelToDb(_nivelSel);
    final nivelTxt = nivelLabel(_nivelSel);

    setState(() => _saving = true);
    try {
      final dup = await _yaExistePorNumeroEnGradoYTanda(
        numero: numero,
        grado: grado,
        tanda: tanda,
        nivelDb: nivelDb,
      );

      if (dup) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ese número ya existe en este grado, tanda y nivel'),
          ),
        );
        return;
      }

      final dup2 = await _yaExistePorNombreDob(
        nombresKey: _nameKey(nombres),
        apellidosKey: _nameKey(apellidos),
        dob: _fechaNacimiento!,
      );
      if (dup2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Posible duplicado: mismo nombre y fecha de nacimiento'),
          ),
        );
        return;
      }

      final edad = _calcAge(_fechaNacimiento!);

      // ✅ principal: alumnos
      final alumnoRef = _alumnosCol.doc();
      final idGlobal = alumnoRef.id;

      // ✅ Foto (si existe): sube primero para guardar URL
      Map<String, String?>? photoData;
      try {
        photoData = await _uploadFotoIfAny(idGlobal);
      } catch (_) {
        photoData = null;
      }

      final baseData = <String, dynamic>{
        'idGlobal': idGlobal,
        'fx': idGlobal,
        'nivel': nivelDb,
        'nivelLabel': nivelTxt,
        'schoolId': _schoolId,
        'schoolRef': 'schools/$_schoolId',

        // ✅ ESTADO / BLOQUEO
        'status': estadoToDb(_estadoSel),
        'enabled': _estadoSel != EstadoAlumno.bloqueado, // bloqueado = false
        'statusAt': FieldValue.serverTimestamp(),

        'nombres': nombres,
        'apellidos': apellidos,
        'nombresKey': _nameKey(nombres),
        'apellidosKey': _nameKey(apellidos),

        'matricula': numero,

        'grado': grado,
        'gradoKey': _nameKey(grado),

        'tanda': tanda,

        'fechaNacimiento': Timestamp.fromDate(_fechaNacimiento!),
        'edad': edad,

        'direccion': _direccionCtrl.text.trim().isEmpty
            ? null
            : _direccionCtrl.text.trim(),
        'observaciones': _observCtrl.text.trim().isEmpty
            ? null
            : _observCtrl.text.trim(),

        'tutor': {
          'nombre': tutorNombre,
          'parentesco': _tutorParentescoCtrl.text.trim(),
          'telefono': tutorTel,
          'whatsapp': tutorWa.isEmpty ? null : tutorWa,
          'email': _tutorEmailCtrl.text.trim().isEmpty
              ? null
              : _tutorEmailCtrl.text.trim(),
        },

        'emergencia': {
          'nombre': _normalizeName(_emergNombreCtrl.text),
          'telefono': _normalizePhone(_emergTelefonoCtrl.text),
        },

        'accesos': accesos,
        'accesosEmails': accessEmails,

        'photoUrl': photoData?['photoUrl'],
        'photoPath': photoData?['photoPath'],

        'ingresoAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final batch = _db.batch();

      // 1) alumno en su escuela
      batch.set(alumnoRef, baseData);

      // 2) índice global (solo “alumnos_global”)
      final globalAlumnoRef = _alumnosGlobalCol.doc(idGlobal);
      batch.set(globalAlumnoRef, {
        'idGlobal': idGlobal,
        'fx': idGlobal,
        'schoolId': _schoolId,
        'studentPath': alumnoRef.path,
        'nivel': nivelDb,
        'nivelLabel': nivelTxt,
        'nombres': nombres,
        'apellidos': apellidos,
        'nombresKey': _nameKey(nombres),
        'apellidosKey': _nameKey(apellidos),
        'matricula': numero,
        'grado': grado,
        'gradoKey': _nameKey(grado),
        'tanda': tanda,
        'fechaNacimiento': Timestamp.fromDate(_fechaNacimiento!),
        'accesosEmails': accessEmails,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': estadoToDb(_estadoSel),
        'enabled': _estadoSel != EstadoAlumno.bloqueado,
      });

      // 3) alumnos_login (por emailLower) -> agrega studentIds
      for (final a in accesos) {
        final email = (a['email'] ?? '').toString().trim();
        final emailLower =
            (a['emailLower'] ?? '').toString().trim().toLowerCase();
        final usuario = (a['usuario'] ?? '').toString().trim();

        if (emailLower.isEmpty) continue;

        final loginRef = _alumnosLoginCol.doc(emailLower);

        batch.set(
          loginRef,
          {
            'email': email,
            'emailLower': emailLower,
            'schoolId': _schoolId,

            // ✅ un mismo email puede tener varios hijos
            'studentIds': FieldValue.arrayUnion([idGlobal]),

            // opcional
            'usuarios': FieldValue.arrayUnion([usuario]),

            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      // reset form
      _nombresCtrl.clear();
      _apellidosCtrl.clear();
      _matriculaCtrl.clear();
      _direccionCtrl.clear();
      _observCtrl.clear();

      _fechaNacimiento = null;
      _fechaCtrl.clear();
      _edadCtrl.clear();

      _tutorNombreCtrl.clear();
      _tutorTelefonoCtrl.clear();
      _tutorWhatsappCtrl.clear();
      _tutorEmailCtrl.clear();

      _emergNombreCtrl.clear();
      _emergTelefonoCtrl.clear();

      for (final e in _accessEntries) {
        e.emailCtrl.clear();
        e.userCtrl.clear();
      }
      if (_accessEntries.length > 1) {
        for (int i = _accessEntries.length - 1; i >= 1; i--) {
          _removeAccessRow(i);
        }
      }

      _removeFotoAlumno();

      setState(() {
        _gradoSeleccionadoLista = grado;
        _estadoSel = EstadoAlumno.activo;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alumno registrado en $nivelTxt')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------ Nivel selector ------------------

  void _setNivel(NivelAcademico n) {
    setState(() {
      _nivelSel = n;
      _gradoSeleccionadoForm = null;
      _gradoSeleccionadoLista = null;

      // ✅ IMPORTANTÍSIMO: la foto NO se “queda pegada” entre niveles
      _photoBytes = null;
      _photoExt = null;
      _photoPicked = false;
    });
  }

  // ------------------ Build ------------------

  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (widget.escuela.nombre ?? '—').trim().isEmpty
        ? '—'
        : widget.escuela.nombre!.trim();

    final nivelTxt = nivelLabel(_nivelSel);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(
          'Registro • $nivelTxt • $nombreEscuela',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _registroConfigRef.snapshots(),
        builder: (context, snapConfig) {
          final cfg = snapConfig.data?.data() ?? {};

          if (!_hydratedConfig && snapConfig.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final permitir = (cfg['permitirFotoAlumno'] is bool)
                  ? cfg['permitirFotoAlumno'] as bool
                  : true;
              setState(() {
                _permitirFotoAlumno = permitir;
                _hydratedConfig = true;
              });
            });
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _gradosCol.orderBy('name').snapshots(),
            builder: (context, snapGrades) {
              final gradeDocs = snapGrades.data?.docs ?? [];
              final nivelDb = nivelToDb(_nivelSel);

              final hasNivelField = gradeDocs.any((d) {
                final v = (d.data()['nivel'] ?? '').toString().trim();
                return v.isNotEmpty;
              });

              final gradesFinal = gradeDocs
                  .map((d) => d.data())
                  .where((m) {
                    final name = (m['name'] ?? '').toString().trim();
                    if (name.isEmpty) return false;

                    if (hasNivelField) {
                      final v = (m['nivel'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                      return v == nivelDb;
                    }

                    return _gradoTerminaConNivel(name, _nivelSel);
                  })
                  .map((m) => (m['name'] ?? '').toString().trim())
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort((a, b) {
                  final na = _leadingNumberOrBig(a);
                  final nb = _leadingNumberOrBig(b);
                  if (na != nb) return na.compareTo(nb);
                  return a.toLowerCase().compareTo(b.toLowerCase());
                });

              final hasGrados = gradesFinal.isNotEmpty;

              if (_gradoSeleccionadoForm != null &&
                  !gradesFinal.contains(_gradoSeleccionadoForm)) {
                _gradoSeleccionadoForm = null;
              }
              if (_gradoSeleccionadoLista != null &&
                  !gradesFinal.contains(_gradoSeleccionadoLista)) {
                _gradoSeleccionadoLista = null;
              }

              if (hasGrados && _gradoSeleccionadoForm == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _gradoSeleccionadoForm = gradesFinal.first;
                    _gradoSeleccionadoLista ??= gradesFinal.first;
                  });
                });
              }

              final isWide = MediaQuery.of(context).size.width >= 980;

              final formPanel = _FormPanel(
                schoolId: _schoolId,
                nivel: _nivelSel,
                onNivelChanged: _setNivel,
                permitirFotoAlumno: _permitirFotoAlumno,
                gradesNivel: gradesFinal,
                saving: _saving,
                formKey: _formKey,
                nombresCtrl: _nombresCtrl,
                apellidosCtrl: _apellidosCtrl,
                matriculaCtrl: _matriculaCtrl,
                direccionCtrl: _direccionCtrl,
                observCtrl: _observCtrl,
                fechaCtrl: _fechaCtrl,
                edadCtrl: _edadCtrl,
                estado: _estadoSel,
                onEstadoChanged: _setEstado,
                gradoSeleccionado: _gradoSeleccionadoForm,
                onGradoChanged: (v) => setState(() {
                  _gradoSeleccionadoForm = v;
                  if (v != null && v.trim().isNotEmpty) {
                    _gradoSeleccionadoLista = v;
                  }
                }),
                tandaSeleccionada: _tandaSel,
                tandas: _tandas,
                onTandaChanged: (v) => setState(() => _tandaSel = v),
                onPickFecha: _pickFechaNacimiento,
                tutorNombreCtrl: _tutorNombreCtrl,
                tutorParentescoCtrl: _tutorParentescoCtrl,
                tutorTelefonoCtrl: _tutorTelefonoCtrl,
                tutorWhatsappCtrl: _tutorWhatsappCtrl,
                tutorEmailCtrl: _tutorEmailCtrl,
                emergNombreCtrl: _emergNombreCtrl,
                emergTelefonoCtrl: _emergTelefonoCtrl,
                onCrearGrado: _irAGrados,
                onGuardar: _guardar,
                normalizeName: _normalizeName,
                normalizePhone: _normalizePhone,
                isValidEmail: _isValidEmail,
                photoBytes: _photoBytes,
                photoPicked: _photoPicked,
                onPickPhoto: _pickFotoAlumno,
                onRemovePhoto: _removeFotoAlumno,
                accessEntries: _accessEntries,
                onAddAccess: _addAccessRow,
                onRemoveAccess: _removeAccessRow,
              );

              final listPanel = _ListPanel(
                schoolId: _schoolId,
                nivel: _nivelSel,
                gradesNivel: gradesFinal,
                gradoSeleccionadoLista: _gradoSeleccionadoLista,
                onGradoChanged: (v) =>
                    setState(() => _gradoSeleccionadoLista = v),
                searchCtrl: _searchListCtrl,
                onSearchChanged: (v) =>
                    setState(() => _searchList = v.trim().toLowerCase()),
                search: _searchList,
              );

              if (!isWide) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!hasGrados)
                      _NoGradosBanner(
                        nivelTxt: nivelLabel(_nivelSel),
                        onCrearGrado: _irAGrados,
                      ),
                    formPanel,
                    const SizedBox(height: 14),
                    listPanel,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!hasGrados)
                          _NoGradosBanner(
                            nivelTxt: nivelLabel(_nivelSel),
                            onCrearGrado: _irAGrados,
                          ),
                        formPanel
                      ],
                    ),
                  ),
                  Container(width: 1, color: Colors.grey.shade300),
                  Expanded(
                    flex: 5,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [listPanel],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- UI Panels ----------------

class _FormPanel extends StatelessWidget {
  final String schoolId;

  final EstadoAlumno estado;
  final ValueChanged<EstadoAlumno> onEstadoChanged;

  final NivelAcademico nivel;
  final ValueChanged<NivelAcademico> onNivelChanged;

  final bool permitirFotoAlumno;
  final List<String> gradesNivel;
  final bool saving;

  final GlobalKey<FormState> formKey;

  final TextEditingController nombresCtrl;
  final TextEditingController apellidosCtrl;
  final TextEditingController matriculaCtrl;
  final TextEditingController direccionCtrl;
  final TextEditingController observCtrl;

  final TextEditingController fechaCtrl;
  final TextEditingController edadCtrl;

  final String? gradoSeleccionado;
  final ValueChanged<String?> onGradoChanged;

  final String? tandaSeleccionada;
  final List<String> tandas;
  final ValueChanged<String?> onTandaChanged;

  final VoidCallback onPickFecha;

  final TextEditingController tutorNombreCtrl;
  final TextEditingController tutorParentescoCtrl;
  final TextEditingController tutorTelefonoCtrl;
  final TextEditingController tutorWhatsappCtrl;
  final TextEditingController tutorEmailCtrl;

  final TextEditingController emergNombreCtrl;
  final TextEditingController emergTelefonoCtrl;

  final VoidCallback onCrearGrado;
  final VoidCallback onGuardar;

  final String Function(String) normalizeName;
  final String Function(String) normalizePhone;
  final bool Function(String) isValidEmail;

  final Uint8List? photoBytes;
  final bool photoPicked;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  final List<_AccessEmailEntry> accessEntries;
  final VoidCallback onAddAccess;
  final void Function(int) onRemoveAccess;

  const _FormPanel({
    required this.schoolId,
    required this.nivel,
    required this.onNivelChanged,
    required this.permitirFotoAlumno,
    required this.gradesNivel,
    required this.saving,
    required this.formKey,
    required this.nombresCtrl,
    required this.apellidosCtrl,
    required this.matriculaCtrl,
    required this.direccionCtrl,
    required this.observCtrl,
    required this.fechaCtrl,
    required this.edadCtrl,
    required this.gradoSeleccionado,
    required this.onGradoChanged,
    required this.tandaSeleccionada,
    required this.tandas,
    required this.onTandaChanged,
    required this.onPickFecha,
    required this.tutorNombreCtrl,
    required this.tutorParentescoCtrl,
    required this.tutorTelefonoCtrl,
    required this.tutorWhatsappCtrl,
    required this.tutorEmailCtrl,
    required this.emergNombreCtrl,
    required this.emergTelefonoCtrl,
    required this.onCrearGrado,
    required this.onGuardar,
    required this.normalizeName,
    required this.normalizePhone,
    required this.isValidEmail,
    required this.photoBytes,
    required this.photoPicked,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    required this.accessEntries,
    required this.onAddAccess,
    required this.onRemoveAccess,
    required this.estado,
    required this.onEstadoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final nTxt = nivelLabel(nivel);
    final hasGrados = gradesNivel.isNotEmpty;

    return _CardShell(
      title: 'Formulario de inscripción • $nTxt',
      subtitle:
          'Grados filtrados por campo "nivel" (fallback por nombre si falta).',
      icon: Icon(nivelIcon(nivel), color: _orange),
      background: Colors.white,
      child: Form(
        key: formKey,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _NivelSwitcher(
                    value: nivel,
                    onChanged: onNivelChanged,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const _SectionTitle('Estado del alumno'),
            const SizedBox(height: 10),
            _EstadoSwitcher(
              value: estado,
              onChanged: onEstadoChanged,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Activo = normal • Pendiente = por revisar • Bloqueado = sin acceso',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),

            const SizedBox(height: 12),

            if (!hasGrados)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withOpacity(0.25)),
                ),
                child: const Text(
                  'No hay grados creados para este nivel. Pulsa "Crear grado".',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),

            const SizedBox(height: 12),
            const _SectionTitle('Foto del alumno'),
            const SizedBox(height: 10),

            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: _blue.withOpacity(0.08),
                  backgroundImage:
                      (photoBytes != null) ? MemoryImage(photoBytes!) : null,
                  child: (photoBytes == null)
                      ? const Icon(Icons.person, size: 34, color: _blue)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sube una foto (opcional). Se guardará en Storage y quedará vinculada al alumno.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Elegir foto',
                  onPressed: saving ? null : onPickPhoto,
                  icon: const Icon(Icons.photo_library, color: _orange),
                ),
                IconButton(
                  tooltip: 'Quitar foto',
                  onPressed: (saving || !photoPicked) ? null : onRemovePhoto,
                  icon: Icon(Icons.delete_outline, color: Colors.grey.shade700),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Datos del alumno'),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: nombresCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombres',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizeName(v);
                      nombresCtrl.value = nombresCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                    validator: (v) {
                      final s = normalizeName(v ?? '');
                      if (s.isEmpty) return 'Escribe los nombres';
                      if (s.length < 2) return 'Muy corto';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: apellidosCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Apellidos',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizeName(v);
                      apellidosCtrl.value = apellidosCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                    validator: (v) {
                      final s = normalizeName(v ?? '');
                      if (s.isEmpty) return 'Escribe los apellidos';
                      if (s.length < 2) return 'Muy corto';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: matriculaCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula o Número',
                      hintText: 'Ej: 12',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Escribe el número';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: tandaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Tanda',
                      border: OutlineInputBorder(),
                    ),
                    items: tandas
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: onTandaChanged,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Selecciona la tanda' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: hasGrados ? gradoSeleccionado : null,
                    decoration: InputDecoration(
                      labelText: 'Grado ($nTxt)',
                      border: const OutlineInputBorder(),
                    ),
                    items: gradesNivel
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: hasGrados ? onGradoChanged : null,
                    validator: (v) {
                      if (!hasGrados) return 'Crea grados primero';
                      return (v == null || v.trim().isEmpty)
                          ? 'Selecciona grado'
                          : null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCrearGrado,
                icon: const Icon(Icons.add, color: _orange),
                label: const Text('Crear grado'),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: fechaCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: onPickFecha,
                        icon: const Icon(Icons.calendar_month),
                      ),
                    ),
                    onTap: onPickFecha,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: edadCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Edad (automática)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: direccionCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Dirección (opcional)',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 2,
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Información de padres / tutores'),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: tutorNombreCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del tutor',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizeName(v);
                      tutorNombreCtrl.value = tutorNombreCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                    validator: (v) {
                      final s = normalizeName(v ?? '');
                      if (s.isEmpty) return 'Escribe el tutor';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: tutorParentescoCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Parentesco',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: tutorTelefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (contacto principal)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizePhone(v);
                      tutorTelefonoCtrl.value = tutorTelefonoCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                    validator: (v) {
                      final s = normalizePhone(v ?? '');
                      if (s.isEmpty) return 'Teléfono requerido';
                      if (s.length < 8) return 'Teléfono muy corto';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: tutorWhatsappCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizePhone(v);
                      tutorWhatsappCtrl.value =
                          tutorWhatsappCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: tutorEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email del tutor (opcional)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Correos con acceso (Google)'),
            const SizedBox(height: 8),
            Text(
              'Aquí agregas los correos (docente, padres o quien tú decidas) que podrán acceder al alumno cuando activemos el login con Google.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),

            Column(
              children: [
                for (int i = 0; i < accessEntries.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: accessEntries[i].emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Correo #${i + 1}',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final lower = v.trim().toLowerCase();
                            if (lower != v) {
                              accessEntries[i].emailCtrl.value =
                                  accessEntries[i].emailCtrl.value.copyWith(
                                text: lower,
                                selection: TextSelection.collapsed(
                                    offset: lower.length),
                              );
                            }
                          },
                          validator: (_) {
                            final email =
                                accessEntries[i].emailCtrl.text.trim();
                            final user = accessEntries[i].userCtrl.text.trim();
                            if (email.isEmpty && user.isEmpty) return null;
                            if (email.isEmpty) return 'Email requerido';
                            if (!isValidEmail(email)) return 'Email inválido';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: accessEntries[i].userCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Usuario',
                            border: OutlineInputBorder(),
                          ),
                          validator: (_) {
                            final email =
                                accessEntries[i].emailCtrl.text.trim();
                            final user = accessEntries[i].userCtrl.text.trim();
                            if (email.isEmpty && user.isEmpty) return null;
                            if (user.isEmpty) return 'Usuario requerido';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Quitar',
                        onPressed: (saving || accessEntries.length <= 1)
                            ? null
                            : () => onRemoveAccess(i),
                        icon: const Icon(Icons.close, color: _orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: saving ? null : onAddAccess,
                    icon: const Icon(Icons.add, color: _orange),
                    label: const Text('Agregar correo'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Contacto de emergencia'),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: emergNombreCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizeName(v);
                      emergNombreCtrl.value = emergNombreCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: emergTelefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final n = normalizePhone(v);
                      emergTelefonoCtrl.value =
                          emergTelefonoCtrl.value.copyWith(
                        text: n,
                        selection: TextSelection.collapsed(offset: n.length),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Notas'),
            const SizedBox(height: 10),

            TextFormField(
              controller: observCtrl,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),

            const SizedBox(height: 10),
            Text(
              permitirFotoAlumno
                  ? 'Foto del alumno: el alumno podrá cambiarla (según tu configuración actual).'
                  : 'Foto del alumno: está bloqueada para alumnos (solo administración).',
              style: TextStyle(color: Colors.grey.shade700),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (saving || !hasGrados) ? null : onGuardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  saving
                      ? 'Guardando...'
                      : (!hasGrados ? 'Crea grados primero' : 'Registrar alumno'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListPanel extends StatelessWidget {
  final String schoolId;
  final NivelAcademico nivel;

  final List<String> gradesNivel;
  final String? gradoSeleccionadoLista;
  final ValueChanged<String?> onGradoChanged;

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;

  final String search;

  const _ListPanel({
    required this.schoolId,
    required this.nivel,
    required this.gradesNivel,
    required this.gradoSeleccionadoLista,
    required this.onGradoChanged,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.search,
  });

  CollectionReference<Map<String, dynamic>> get _alumnosCol =>
      FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('alumnos');

  @override
  Widget build(BuildContext context) {
    final nTxt = nivelLabel(nivel);
    final hasGrados = gradesNivel.isNotEmpty;
    final nivelDb = nivelToDb(nivel);

    return _CardShell(
      title: 'Alumnos por grado • $nTxt',
      subtitle: 'Aquí solo trabajas con grados filtrados por este nivel.',
      icon: const Icon(Icons.school, color: _orange),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: hasGrados ? gradoSeleccionadoLista : null,
            decoration: const InputDecoration(
              labelText: 'Grado',
              border: OutlineInputBorder(),
            ),
            items: gradesNivel
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: hasGrados ? onGradoChanged : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar (nombre, apellido, número)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          if (!hasGrados)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No hay grados para este nivel. Crea grados primero.'),
            )
          else if (gradoSeleccionadoLista == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Selecciona un grado para ver alumnos.'),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _alumnosCol
                  .where('grado', isEqualTo: gradoSeleccionadoLista)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Text('Error: ${snap.error}');
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snap.data!.docs;

                final rows = docs
                    .map((d) {
                      final data = d.data();

                      // ✅ filtro extra en memoria: evita mezclar niveles sin crear índices nuevos
                      final n = (data['nivel'] ?? '').toString().trim().toLowerCase();
                      if (n.isNotEmpty && n != nivelDb) return null;

                      final nombres = (data['nombres'] ?? '').toString();
                      final apellidos = (data['apellidos'] ?? '').toString();
                      final numero = (data['matricula'] ?? '').toString();
                      final grado = (data['grado'] ?? '').toString();
                      final edad = (data['edad'] ?? '').toString();
                      final status = (data['status'] ?? 'activo').toString();

                      final key = ('$nombres $apellidos $numero').toLowerCase();
                      return {
                        'id': d.id,
                        'nombres': nombres,
                        'apellidos': apellidos,
                        'numero': numero,
                        'grado': grado,
                        'edad': edad,
                        'status': status,
                        'key': key,
                      };
                    })
                    .where((x) => x != null)
                    .cast<Map<String, dynamic>>()
                    .toList();

                final q = search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? rows
                    : rows.where((r) => (r['key'] as String).contains(q)).toList();

                filtered.sort((a, b) {
                  final aa = '${a['apellidos']} ${a['nombres']}'.toLowerCase();
                  final bb = '${b['apellidos']} ${b['nombres']}'.toLowerCase();
                  return aa.compareTo(bb);
                });

                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No hay alumnos para mostrar.'),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _blue.withOpacity(0.06),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Total: ${filtered.length}',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.people, color: _orange),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final title = '${r['apellidos']}, ${r['nombres']}';

                          final st = estadoFromDb((r['status'] ?? 'activo').toString());
                          final stColor = estadoColor(st);

                          final sub = [
                            'Estado: ${estadoLabel(st)}',
                            if ((r['numero'] as String).isNotEmpty)
                              'Número: ${r['numero']}',
                            if ((r['edad'] as String).isNotEmpty)
                              'Edad: ${r['edad']}',
                            if ((r['grado'] as String).isNotEmpty)
                              'Grado: ${r['grado']}',
                          ].join(' • ');

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: stColor.withOpacity(0.15),
                              child: Icon(estadoIcon(st), color: stColor),
                            ),
                            title: Text(title, overflow: TextOverflow.ellipsis),
                            subtitle: Text(sub, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: 'Editar (próximo paso)',
                              icon: const Icon(Icons.edit, color: _orange),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Edición rápida: la hacemos en el próximo paso.'),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _NoGradosBanner extends StatelessWidget {
  final String nivelTxt;
  final VoidCallback onCrearGrado;

  const _NoGradosBanner({
    required this.nivelTxt,
    required this.onCrearGrado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No hay grados para $nivelTxt. Crea los grados para que aparezcan en el selector.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: onCrearGrado,
            child: const Text('Crear grado'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Small UI helpers ----------------

class _CardShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final Widget child;
  final Color background;

  const _CardShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style:
                      const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _orange,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _NivelSwitcher extends StatelessWidget {
  final NivelAcademico value;
  final ValueChanged<NivelAcademico> onChanged;

  const _NivelSwitcher({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(NivelAcademico n) {
      final selected = n == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(n),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? _blue : Colors.grey.shade300),
              color: selected ? _blue.withOpacity(0.08) : Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(nivelIcon(n),
                    size: 18, color: selected ? _blue : Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  nivelLabel(n),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? _blue : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(NivelAcademico.inicial),
        const SizedBox(width: 8),
        chip(NivelAcademico.primaria),
        const SizedBox(width: 8),
        chip(NivelAcademico.secundaria),
      ],
    );
  }
}

class _EstadoSwitcher extends StatelessWidget {
  final EstadoAlumno value;
  final ValueChanged<EstadoAlumno> onChanged;

  const _EstadoSwitcher({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(EstadoAlumno e) {
      final selected = e == value;
      final c = estadoColor(e);

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(e),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? c : Colors.grey.shade300,
                width: selected ? 1.5 : 1,
              ),
              color: selected ? c.withOpacity(0.12) : Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(estadoIcon(e),
                    size: 18, color: selected ? c : Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  estadoLabel(e),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? c : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(EstadoAlumno.activo),
        const SizedBox(width: 8),
        chip(EstadoAlumno.pendiente),
        const SizedBox(width: 8),
        chip(EstadoAlumno.bloqueado),
      ],
    );
  }
}
