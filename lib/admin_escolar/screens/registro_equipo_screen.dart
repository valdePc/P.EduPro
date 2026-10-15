// lib/admin_escolar/screens/registro_equipo_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/admin_escolar/services/school_registration_session.dart';
import 'package:edupro/admin_escolar/utils/registration_error_message.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/admin_escolar/widgets/registro_equipo_widgets.dart';

import 'admin_login_escolar.dart';

// ✅ Colores a nivel de archivo
const Color _blue = Color(0xFF1A237E);
const Color _orange = RegistroEquipoColors.amberInk;

/// ✅
enum EstadoAlumno { activo, pendiente, bloqueado }

enum NivelAcademico { inicial, primaria, secundaria }

enum SexoAlumno { nina, nino }

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

String sexoToDb(SexoAlumno s) {
  switch (s) {
    case SexoAlumno.nina:
      return 'femenino';
    case SexoAlumno.nino:
      return 'masculino';
  }
}

String sexoLabel(SexoAlumno s) {
  switch (s) {
    case SexoAlumno.nina:
      return 'Niña';
    case SexoAlumno.nino:
      return 'Niño';
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
      return const Color(0xFF1B7A42);
    case EstadoAlumno.pendiente:
      return RegistroEquipoColors.amberInk;
    case EstadoAlumno.bloqueado:
      return const Color(0xFFB42318);
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
  final SchoolRegistrationSession registrationSession;
  final String? schoolIdOverride; // ✅ NUEVO
  final bool permitirFotoAlumno;
  final bool permitirEditarEstudiantes;

  const RegistroEquipoScreen({
    super.key,
    required this.escuela,
    required this.registrationSession,
    this.schoolIdOverride, // ✅ NUEVO
    this.permitirFotoAlumno = true,
    this.permitirEditarEstudiantes = true,
  });

  @override
  State<RegistroEquipoScreen> createState() => _RegistroEquipoScreenState();
}

class _RegistroEquipoScreenState extends State<RegistroEquipoScreen> {
  FirebaseFirestore get _db => widget.registrationSession.firestore;
  final Map<String, String> _gradeIdsByName = {};
  String? _pendingStudentId;
  String? _uploadedPhotoPath;
  bool _renewing = false;

  // ✅ NIVEL (STATE REAL)
  NivelAcademico _nivelSel = NivelAcademico.primaria;

  // ✅ ESTADO (por defecto: ACTIVO)
  EstadoAlumno _estadoSel = EstadoAlumno.activo;
  SexoAlumno _sexoSel = SexoAlumno.nina;

  void _setEstado(EstadoAlumno e) {
    if (e == _estadoSel) return;
    setState(() {
      _estadoSel = e;
      _selectionDirty = true;
    });
  }

  // ✅ TANDA (STATE REAL)
  String? _tandaSel;
  static const List<String> _tandas = ['Mañana', 'Tarde', 'Nocturna'];

  late final String _schoolId;

  // ----- UI State -----
  bool _saving = false;
  bool _selectionDirty = false;

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
  bool _photoPicked = false;

  @override
  void initState() {
    super.initState();

    final override = (widget.schoolIdOverride ?? '').trim();

    final raw =
        override.isNotEmpty
            ? override
            : normalizeSchoolIdFromEscuela(widget.escuela);

    _schoolId = raw; // ✅ SOLO AQUÍ

    _tandaSel ??= _tandas.first;
    _accessEntries.add(_AccessEmailEntry());
    _permitirFotoAlumno = widget.permitirFotoAlumno;
  }

  @override
  void dispose() {
    unawaited(widget.registrationSession.close());
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
    final cleaned = _onlyLettersSpaces(
      input,
    ).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '';
    return cleaned
        .split(' ')
        .map(
          (w) =>
              w.isEmpty
                  ? ''
                  : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
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
    final hadBirthday =
        (now.month > dob.month) ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age < 0 ? 0 : age;
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  // ------------------ Firestore paths ------------------

  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      _db.collection('schools').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _alumnosCol =>
      _db.collection('schools').doc(_schoolId).collection('alumnos');

  Future<void> _irAGrados() async {
    if (_saving || _renewing) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RegistroEquipoGradeDialog(level: nivelLabel(_nivelSel)),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.registrationSession.createGrade(
        name: name.trim(),
        nivel: nivelToDb(_nivelSel),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grado creado. Ya puedes seleccionarlo.')),
      );
    } catch (error) {
      _showRegistrationError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showRegistrationError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(registrationErrorMessage(error)),
        duration: const Duration(seconds: 10),
        action:
            registrationNeedsRenewal(error)
                ? SnackBarAction(
                  label: 'Renovar acceso',
                  onPressed: _renewAccess,
                )
                : null,
      ),
    );
  }

  Future<void> _renewAccess() async {
    if (_saving || _renewing) return;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const RegistroEquipoCodeDialog(),
    );
    if (code == null || !mounted) return;
    setState(() => _renewing = true);
    try {
      await widget.registrationSession.renew(code);
      if (!mounted) return;
      setState(
        () =>
            _permitirFotoAlumno = widget.registrationSession.permitirFotoAlumno,
      );
      if (!_permitirFotoAlumno && _photoPicked) {
        _showPhotoNotAllowed();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso renovado. Puedes volver a registrar.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo renovar el acceso. Comprueba la clave con el administrador e inténtalo de nuevo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  // ------------------ Foto alumno ------------------

  void _showPhotoNotAllowed() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _photoPicked
              ? 'La escuela desactivó la carga de fotos. Retira la foto para completar el registro; los demás datos se conservarán.'
              : 'La escuela desactivó la carga de fotos para el equipo de registro.',
        ),
        duration: const Duration(seconds: 10),
        action:
            _photoPicked
                ? SnackBarAction(
                  label: 'Retirar foto',
                  onPressed: _removeFotoAlumno,
                )
                : null,
      ),
    );
  }

  Future<void> _pickFotoAlumno() async {
    if (_saving || _renewing) return;
    if (!_permitirFotoAlumno) {
      _showPhotoNotAllowed();
      return;
    }
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      if (!mounted) return;
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
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024 || (!png && !jpeg)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La foto debe ser JPG o PNG y pesar como máximo 5 MB.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _photoBytes = bytes;
        _uploadedPhotoPath = null;
        _photoPicked = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo seleccionar la foto. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  void _removeFotoAlumno() {
    if (_saving) return;
    setState(() {
      _photoBytes = null;
      _uploadedPhotoPath = null;
      _photoPicked = false;
    });
  }

  Future<String?> _uploadFotoIfAny(String alumnoId) async {
    if (_photoBytes == null || !_photoPicked) return null;
    return _uploadedPhotoPath ??= await widget.registrationSession.uploadPhoto(
      alumnoId,
      _photoBytes!,
    );
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

  // ------------------ Accesos ------------------

  void _addAccessRow() {
    if (_accessEntries.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Puedes autorizar hasta 10 cuentas por estudiante.'),
        ),
      );
      return;
    }
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

      list.add({'email': email, 'emailLower': emailLower, 'usuario': user});
    }

    return list;
  }

  // ------------------ Guardar alumno ------------------

  Future<void> _guardar() async {
    if (_saving || _renewing) return;
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
    final grado = (_gradoSeleccionadoForm ?? '').trim();
    final gradoId = _gradeIdsByName[grado];
    final tanda = (_tandaSel ?? '').trim();
    if (_fechaNacimiento == null || gradoId == null || tanda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona la fecha de nacimiento, el grado y la tanda.',
          ),
        ),
      );
      return;
    }
    List<Map<String, dynamic>> accesos;
    try {
      accesos = _buildAccesosOrThrow();
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (accesos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un correo autorizado con su usuario.'),
        ),
      );
      return;
    }
    if (_photoPicked && !_permitirFotoAlumno) {
      _showPhotoNotAllowed();
      return;
    }
    setState(() => _saving = true);
    try {
      widget.registrationSession.ensureActive();
      // Keep the ID on uncertain network results: the server prevents duplicates.
      final studentId = _pendingStudentId ??= _alumnosCol.doc().id;
      final photoPath = await _uploadFotoIfAny(studentId);
      final dob = _fechaNacimiento!;
      await widget.registrationSession.register(studentId, {
        'nombres': nombres,
        'apellidos': apellidos,
        'matricula': _matriculaCtrl.text.trim(),
        'nivel': nivelToDb(_nivelSel),
        'gradoId': gradoId,
        'tanda': tanda,
        'fechaNacimientoMillis': dob.millisecondsSinceEpoch,
        'sexo': sexoToDb(_sexoSel),
        'status': estadoToDb(_estadoSel),
        'direccion': _direccionCtrl.text.trim(),
        'observaciones': _observCtrl.text.trim(),
        'tutor': {
          'nombre': tutorNombre,
          'parentesco': _tutorParentescoCtrl.text.trim(),
          'telefono': tutorTel,
          'whatsapp': tutorWa,
          'email': _tutorEmailCtrl.text.trim(),
        },
        'emergencia': {
          'nombre': _normalizeName(_emergNombreCtrl.text),
          'telefono': _normalizePhone(_emergTelefonoCtrl.text),
        },
        'accesos': [
          for (final access in accesos)
            {'email': access['email'], 'usuario': access['usuario']},
        ],
        if (photoPath != null) 'photoPath': photoPath,
      });
      if (!mounted) return;
      for (final controller in [
        _nombresCtrl,
        _apellidosCtrl,
        _matriculaCtrl,
        _direccionCtrl,
        _observCtrl,
        _fechaCtrl,
        _edadCtrl,
        _tutorNombreCtrl,
        _tutorTelefonoCtrl,
        _tutorWhatsappCtrl,
        _tutorEmailCtrl,
        _emergNombreCtrl,
        _emergTelefonoCtrl,
      ]) {
        controller.clear();
      }
      for (final entry in _accessEntries) {
        entry.emailCtrl.clear();
        entry.userCtrl.clear();
      }
      while (_accessEntries.length > 1) {
        _accessEntries.removeLast().dispose();
      }
      setState(() {
        _pendingStudentId = null;
        _uploadedPhotoPath = null;
        _fechaNacimiento = null;
        _photoBytes = null;
        _photoPicked = false;
        _gradoSeleccionadoLista = grado;
        _estadoSel = EstadoAlumno.activo;
        _sexoSel = SexoAlumno.nina;
        _selectionDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alumno registrado en ${nivelLabel(_nivelSel)}'),
        ),
      );
    } catch (error) {
      _showRegistrationError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------ Nivel selector ------------------

  void _setNivel(NivelAcademico n) {
    if (n == _nivelSel) return;
    setState(() {
      _nivelSel = n;
      _selectionDirty = true;
      _gradoSeleccionadoForm = null;
      _gradoSeleccionadoLista = null;

      // ✅ IMPORTANTÍSIMO: la foto NO se “queda pegada” entre niveles
      _photoBytes = null;
      _uploadedPhotoPath = null;
      _photoPicked = false;
    });
  }

  bool get _hasUnsavedInput {
    final fields = [
      _nombresCtrl,
      _apellidosCtrl,
      _matriculaCtrl,
      _direccionCtrl,
      _observCtrl,
      _fechaCtrl,
      _tutorNombreCtrl,
      _tutorTelefonoCtrl,
      _tutorWhatsappCtrl,
      _tutorEmailCtrl,
      _emergNombreCtrl,
      _emergTelefonoCtrl,
    ];
    return _selectionDirty ||
        _photoPicked ||
        fields.any((field) => field.text.trim().isNotEmpty) ||
        _tutorParentescoCtrl.text.trim() != 'Padre/Madre' ||
        _accessEntries.any(
          (entry) =>
              entry.emailCtrl.text.trim().isNotEmpty ||
              entry.userCtrl.text.trim().isNotEmpty,
        );
  }

  Future<void> _salirDelRegistro() async {
    if (_saving || _renewing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Espera a que termine el registro antes de salir.'),
        ),
      );
      return;
    }
    if (_hasUnsavedInput) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (_) => const RegistroEquipoExitDialog(),
      );
      if (leave != true) return;
    }
    if (!mounted) return;
    await widget.registrationSession.close();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AdminLoginEscolarScreen(escuela: widget.escuela),
      ),
    );
  }

  // ------------------ Build ------------------

  @override
  Widget build(BuildContext context) {
    final nombreEscuela =
        widget.escuela.nombre.trim().isEmpty
            ? '—'
            : widget.escuela.nombre.trim();

    final nivelTxt = nivelLabel(_nivelSel);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _salirDelRegistro();
      },
      child: Scaffold(
        backgroundColor: RegistroEquipoColors.page,
        appBar: AppBar(
          leading: AdminBackButton(onBack: _salirDelRegistro),
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          title: Text(
            MediaQuery.sizeOf(context).width < 480
                ? 'Registro'
                : 'Registro de estudiantes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Renovar acceso de registro',
              onPressed: _saving || _renewing ? null : _renewAccess,
              icon:
                  _renewing
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.refresh_rounded),
            ),
            RegistroEquipoExitAction(
              compact: MediaQuery.sizeOf(context).width < 520,
              onPressed: _salirDelRegistro,
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFFF8F9FC),
                labelStyle: const TextStyle(
                  color: RegistroEquipoColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                hintStyle: const TextStyle(
                  color: RegistroEquipoColors.muted,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: RegistroEquipoColors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _blue, width: 1.6),
                ),
              ),
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _gradosCol.orderBy('name').snapshots(),
              builder: (context, snapGrades) {
                if (snapGrades.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No se pudieron cargar los grados. Comprueba tu acceso o conexión.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: RegistroEquipoColors.ink,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapGrades.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final gradeDocs = snapGrades.data?.docs ?? [];
                final nivelDb = nivelToDb(_nivelSel);

                final hasNivelField = gradeDocs.any((d) {
                  final v = (d.data()['nivel'] ?? '').toString().trim();
                  return v.isNotEmpty;
                });

                final gradesFinal =
                    gradeDocs
                        .map((d) => d.data())
                        .where((m) {
                          final name = (m['name'] ?? '').toString().trim();
                          if (name.isEmpty) return false;

                          if (hasNivelField) {
                            final v =
                                (m['nivel'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            if (v == nivelDb) return true;
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

                _gradeIdsByName
                  ..clear()
                  ..addEntries(
                    gradeDocs
                        .where(
                          (d) => gradesFinal.contains(
                            (d.data()['name'] ?? '').toString().trim(),
                          ),
                        )
                        .map(
                          (d) => MapEntry(
                            (d.data()['name'] as String).trim(),
                            d.id,
                          ),
                        ),
                  );
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

                final formPanel = AbsorbPointer(
                  absorbing: _saving || _renewing,
                  child: _FormPanel(
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
                    sexoSeleccionado: _sexoSel,
                    onSexoChanged:
                        (v) => setState(() {
                          if (v != _sexoSel) _selectionDirty = true;
                          _sexoSel = v;
                        }),
                    gradoSeleccionado: _gradoSeleccionadoForm,
                    onGradoChanged:
                        (v) => setState(() {
                          if (v != _gradoSeleccionadoForm) {
                            _selectionDirty = true;
                          }
                          _gradoSeleccionadoForm = v;
                          if (v != null && v.trim().isNotEmpty) {
                            _gradoSeleccionadoLista = v;
                          }
                        }),
                    tandaSeleccionada: _tandaSel,
                    tandas: _tandas,
                    onTandaChanged:
                        (v) => setState(() {
                          if (v != _tandaSel) _selectionDirty = true;
                          _tandaSel = v;
                        }),
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
                  ),
                );

                final listPanel = _ListPanel(
                  schoolId: _schoolId,
                  firestore: _db,
                  nivel: _nivelSel,
                  gradesNivel: gradesFinal,
                  gradoSeleccionadoLista: _gradoSeleccionadoLista,
                  onGradoChanged:
                      (v) => setState(() => _gradoSeleccionadoLista = v),
                  searchCtrl: _searchListCtrl,
                  onSearchChanged:
                      (v) =>
                          setState(() => _searchList = v.trim().toLowerCase()),
                  search: _searchList,
                );

                if (!isWide) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      RegistroEquipoHero(
                        schoolName: nombreEscuela,
                        level: nivelTxt,
                      ),
                      const SizedBox(height: 16),
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

                return RegistroEquipoDesktopLayout(
                  header: RegistroEquipoHero(
                    schoolName: nombreEscuela,
                    level: nivelTxt,
                  ),
                  banner:
                      !hasGrados
                          ? _NoGradosBanner(
                            nivelTxt: nivelTxt,
                            onCrearGrado: _irAGrados,
                          )
                          : null,
                  form: formPanel,
                  list: listPanel,
                );
              },
            ),
          ),
        ),
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
  final SexoAlumno sexoSeleccionado;
  final ValueChanged<SexoAlumno> onSexoChanged;

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
    required this.sexoSeleccionado,
    required this.onSexoChanged,
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
          'Información del estudiante, su familia y contactos autorizados.',
      icon: Icon(nivelIcon(nivel), color: _blue),
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
            _EstadoSwitcher(value: estado, onChanged: onEstadoChanged),
            const SizedBox(height: 20),

            if (!hasGrados)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4DF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFECD49B)),
                ),
                child: const Text(
                  'No hay grados creados para este nivel. Pulsa "Crear grado".',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),

            const SizedBox(height: 12),
            const _SectionTitle('Foto del alumno'),
            const SizedBox(height: 10),

            RegistroEquipoPhotoField(
              canUpload: permitirFotoAlumno,
              saving: saving,
              photoPicked: photoPicked,
              bytes: photoBytes,
              onPick: onPickPhoto,
              onRemove: onRemovePhoto,
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Datos del alumno'),
            const SizedBox(height: 10),

            RegistroEquipoFieldRow(
              fields: [
                TextFormField(
                  controller: nombresCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
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
                TextFormField(
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
              ],
            ),
            const SizedBox(height: 12),

            RegistroEquipoFieldRow(
              minWidthPerField: 190,
              fields: [
                TextFormField(
                  controller: matriculaCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula o Número (opcional)',
                    hintText: 'Ej: 12',
                    border: OutlineInputBorder(),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: tandaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Tanda',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      tandas
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                  onChanged: onTandaChanged,
                  validator:
                      (v) =>
                          (v == null || v.isEmpty)
                              ? 'Selecciona la tanda'
                              : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: hasGrados ? gradoSeleccionado : null,
                  decoration: InputDecoration(
                    labelText: 'Grado ($nTxt)',
                    border: const OutlineInputBorder(),
                  ),
                  items:
                      gradesNivel
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                  onChanged: hasGrados ? onGradoChanged : null,
                  validator: (v) {
                    if (!hasGrados) return 'Crea grados primero';
                    return (v == null || v.trim().isEmpty)
                        ? 'Selecciona grado'
                        : null;
                  },
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

            RegistroEquipoFieldRow(
              fields: [
                TextFormField(
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
                TextFormField(
                  controller: edadCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Edad (automática)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            RegistroEquipoFieldRow(
              fields: [
                DropdownButtonFormField<SexoAlumno>(
                  initialValue: sexoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Sexo',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      SexoAlumno.values
                          .map(
                            (s) => DropdownMenuItem<SexoAlumno>(
                              value: s,
                              child: Text(sexoLabel(s)),
                            ),
                          )
                          .toList(),
                  onChanged:
                      saving
                          ? null
                          : (v) {
                            if (v != null) onSexoChanged(v);
                          },
                ),
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
              ],
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Información de padres / tutores'),
            const SizedBox(height: 10),

            RegistroEquipoFieldRow(
              fields: [
                TextFormField(
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
                TextFormField(
                  controller: tutorParentescoCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Parentesco',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            RegistroEquipoFieldRow(
              fields: [
                TextFormField(
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
                TextFormField(
                  controller: tutorWhatsappCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final n = normalizePhone(v);
                    tutorWhatsappCtrl.value = tutorWhatsappCtrl.value.copyWith(
                      text: n,
                      selection: TextSelection.collapsed(offset: n.length),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: tutorEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo del tutor (opcional)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 14),
            const _SectionTitle('Correos con acceso (Google)'),
            const SizedBox(height: 8),
            Text(
              'Añade las cuentas autorizadas para acceder.',
              style: const TextStyle(
                color: RegistroEquipoColors.muted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),

            Column(
              children: [
                for (int i = 0; i < accessEntries.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Acceso ${i + 1}',
                          style: const TextStyle(
                            color: RegistroEquipoColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar acceso ${i + 1}',
                        onPressed:
                            (saving || accessEntries.length <= 1)
                                ? null
                                : () => onRemoveAccess(i),
                        icon: const Icon(
                          Icons.close,
                          color: RegistroEquipoColors.muted,
                        ),
                      ),
                    ],
                  ),
                  RegistroEquipoFieldRow(
                    fields: [
                      TextFormField(
                        controller: accessEntries[i].emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Correo #${i + 1}',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final lower = v.trim().toLowerCase();
                          if (lower != v) {
                            accessEntries[i].emailCtrl.value = accessEntries[i]
                                .emailCtrl
                                .value
                                .copyWith(
                                  text: lower,
                                  selection: TextSelection.collapsed(
                                    offset: lower.length,
                                  ),
                                );
                          }
                        },
                        validator: (_) {
                          final email = accessEntries[i].emailCtrl.text.trim();
                          final user = accessEntries[i].userCtrl.text.trim();
                          if (email.isEmpty && user.isEmpty) return null;
                          if (email.isEmpty) return 'Email requerido';
                          if (!isValidEmail(email)) return 'Email inválido';
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: accessEntries[i].userCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          border: OutlineInputBorder(),
                        ),
                        validator: (_) {
                          final email = accessEntries[i].emailCtrl.text.trim();
                          final user = accessEntries[i].userCtrl.text.trim();
                          if (email.isEmpty && user.isEmpty) return null;
                          if (user.isEmpty) return 'Usuario requerido';
                          return null;
                        },
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

            RegistroEquipoFieldRow(
              fields: [
                TextFormField(
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
                TextFormField(
                  controller: emergTelefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final n = normalizePhone(v);
                    emergTelefonoCtrl.value = emergTelefonoCtrl.value.copyWith(
                      text: n,
                      selection: TextSelection.collapsed(offset: n.length),
                    );
                  },
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
            if (!permitirFotoAlumno)
              const Text(
                'La foto solo puede agregarla la administración.',
                style: TextStyle(
                  color: RegistroEquipoColors.muted,
                  fontSize: 13,
                ),
              ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (saving || !hasGrados) ? null : onGuardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon:
                    saving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.save),
                label: Text(
                  saving
                      ? 'Guardando...'
                      : (!hasGrados
                          ? 'Crea grados primero'
                          : 'Registrar alumno'),
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

  final FirebaseFirestore firestore;

  const _ListPanel({
    required this.schoolId,
    required this.firestore,
    required this.nivel,
    required this.gradesNivel,
    required this.gradoSeleccionadoLista,
    required this.onGradoChanged,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.search,
  });

  CollectionReference<Map<String, dynamic>> get _alumnosCol =>
      firestore.collection('schools').doc(schoolId).collection('alumnos');

  @override
  Widget build(BuildContext context) {
    final nTxt = nivelLabel(nivel);
    final hasGrados = gradesNivel.isNotEmpty;
    final nivelDb = nivelToDb(nivel);

    return _CardShell(
      title: 'Alumnos por grado • $nTxt',
      subtitle: 'Consulta los estudiantes registrados en cada grado.',
      icon: const Icon(Icons.school_outlined, color: _blue),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: hasGrados ? gradoSeleccionadoLista : null,
            decoration: const InputDecoration(
              labelText: 'Grado',
              border: OutlineInputBorder(),
            ),
            items:
                gradesNivel
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
            onChanged: hasGrados ? onGradoChanged : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar estudiante',
              hintText: 'Nombre, apellido o matrícula',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          if (!hasGrados)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No hay grados para este nivel. Crea grados primero.',
              ),
            )
          else if (gradoSeleccionadoLista == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Selecciona un grado para ver alumnos.'),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _alumnosCol
                      .where('grado', isEqualTo: gradoSeleccionadoLista)
                      .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No se pudieron cargar los estudiantes. Comprueba tu acceso o conexión.',
                      style: TextStyle(
                        color: RegistroEquipoColors.ink,
                        fontSize: 14,
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snap.data!.docs;

                final rows =
                    docs
                        .map((d) {
                          final data = d.data();

                          // ✅ filtro extra en memoria: evita mezclar niveles sin crear índices nuevos
                          final n =
                              (data['nivel'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                          if (n.isNotEmpty && n != nivelDb) return null;

                          final nombres = (data['nombres'] ?? '').toString();
                          final apellidos =
                              (data['apellidos'] ?? '').toString();
                          final numero = (data['matricula'] ?? '').toString();
                          final grado = (data['grado'] ?? '').toString();
                          final edad = (data['edad'] ?? '').toString();
                          final status =
                              (data['status'] ?? 'activo').toString();

                          final key =
                              ('$nombres $apellidos $numero').toLowerCase();
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
                final filtered =
                    q.isEmpty
                        ? rows
                        : rows
                            .where((r) => (r['key'] as String).contains(q))
                            .toList();

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
                    border: Border.all(color: RegistroEquipoColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2FF),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Total de alumnos para el grado seleccionado: ${filtered.length}',
                                style: const TextStyle(
                                  color: RegistroEquipoColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Icon(Icons.people_outline, color: _blue),
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

                          final st = estadoFromDb(
                            (r['status'] ?? 'activo').toString(),
                          );
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
                              backgroundColor: stColor.withValues(alpha: 0.15),
                              child: Icon(estadoIcon(st), color: stColor),
                            ),
                            title: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RegistroEquipoColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              sub,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RegistroEquipoColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Editar (próximo paso)',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: _blue,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Edición rápida: la hacemos en el próximo paso.',
                                    ),
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

  const _NoGradosBanner({required this.nivelTxt, required this.onCrearGrado});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECD49B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _orange),
          const SizedBox(height: 8),
          Text(
            'No hay grados para $nivelTxt. Crea los grados para que aparezcan en el selector.',
            style: const TextStyle(
              color: RegistroEquipoColors.ink,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onCrearGrado, child: const Text('Crear grado')),
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
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RegistroEquipoColors.border),
        color: background,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEFFF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: RegistroEquipoColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: RegistroEquipoColors.muted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 20),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: _orange,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: RegistroEquipoColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NivelSwitcher extends StatelessWidget {
  final NivelAcademico value;
  final ValueChanged<NivelAcademico> onChanged;

  const _NivelSwitcher({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RegistroEquipoChoiceWrap(
      choices: [
        for (final n in NivelAcademico.values)
          RegistroEquipoChoiceTile(
            label: nivelLabel(n),
            icon: nivelIcon(n),
            selected: n == value,
            accent: _blue,
            onTap: () => onChanged(n),
          ),
      ],
    );
  }
}

class _EstadoSwitcher extends StatelessWidget {
  final EstadoAlumno value;
  final ValueChanged<EstadoAlumno> onChanged;

  const _EstadoSwitcher({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RegistroEquipoChoiceWrap(
      choices: [
        for (final e in EstadoAlumno.values)
          RegistroEquipoChoiceTile(
            label: estadoLabel(e),
            icon: estadoIcon(e),
            selected: e == value,
            accent: estadoColor(e),
            onTap: () => onChanged(e),
          ),
      ],
    );
  }
}
