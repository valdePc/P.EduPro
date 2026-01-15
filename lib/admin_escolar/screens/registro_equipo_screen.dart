// lib/admin_escolar/screens/registro_equipo_screen.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// 👇 IMPORTA TU PANTALLA DE GRADOS
import 'A_grados.dart';

// ✅ Colores a nivel de archivo
const Color _blue = Color(0xFF0D47A1);
const Color _orange = Color(0xFFFFA000);

/// ✅ Niveles
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

/// ✅ Inferencia para registros viejos (sin campo "nivel")
/// - Si el grado dice "Inicial" => inicial
/// - Si dice "Secundaria" (o "secund") => secundaria
/// - Si dice "Primaria" => primaria
/// - Si no dice nada, por defecto: primaria (para no “perder” datos)
NivelAcademico inferNivelFromGradoName(String grado) {
  final s = grado.toLowerCase().trim();

  if (s.contains('inicial')) return NivelAcademico.inicial;
  if (s.contains('secund')) return NivelAcademico.secundaria;
  // algunos ponen "sec." o "sec"
  if (RegExp(r'\bsec\b').hasMatch(s)) return NivelAcademico.secundaria;

  if (s.contains('primar')) return NivelAcademico.primaria;

  return NivelAcademico.primaria;
}

/// ✅ Filtra lista de grados por nivel seleccionado
List<String> filtrarGradosPorNivel({
  required List<String> all,
  required List<String> fallbackRD,
  required NivelAcademico nivel,
}) {
  final filtered = all.where((g) => inferNivelFromGradoName(g) == nivel).toList();

  // Si la escuela tiene grados creados pero ninguno se reconoce para ese nivel,
  // usamos fallback por nivel (evita que el dropdown quede vacío).
  if (filtered.isEmpty) {
    final fb = fallbackRD.where((g) => inferNivelFromGradoName(g) == nivel).toList();
    return fb.isNotEmpty ? fb : all;
  }

  return filtered;
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
  NivelAcademico _nivelSel = NivelAcademico.primaria; // primaria por defecto

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

  // Datos tutor 1
  final _tutorNombreCtrl = TextEditingController();
  final _tutorParentescoCtrl = TextEditingController(text: 'Padre/Madre');
  final _tutorTelefonoCtrl = TextEditingController();
  final _tutorWhatsappCtrl = TextEditingController();
  final _tutorEmailCtrl = TextEditingController();

  // Emergencia
  final _emergNombreCtrl = TextEditingController();
  final _emergTelefonoCtrl = TextEditingController();

  // Credenciales del alumno (autogeneradas)
  String _passwordAlumno = '';

  // Fallback grados si no hay ninguno creado todavía
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
    _passwordAlumno = _genPassword(len: 10);

    // ✅ default tanda (mejor UX)
    _tandaSel ??= _tandas.first;
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

    super.dispose();
  }

  // ------------------ Helpers ------------------

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

  String _genPassword({int len = 10}) {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado al portapapeles')),
    );
  }

  // ------------------ Config (permiso foto) ------------------

  DocumentReference<Map<String, dynamic>> get _registroConfigRef => _db
      .collection('escuelas')
      .doc(_schoolId)
      .collection('config')
      .doc('registro');

  // ------------------ Grados (MISMO sitio que AGrados) ------------------
  // ✅ UNIFICADO: escuelas/{schoolId}/grados
  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      _db.collection('escuelas').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _estudiantesCol =>
      _db.collection('escuelas').doc(_schoolId).collection('estudiantes');

  // ✅ Colección GLOBAL para búsquedas globales / índice
  CollectionReference<Map<String, dynamic>> get _estudiantesGlobalCol =>
      _db.collection('estudiantes_global');

  Future<void> _irAGrados() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AGrados(escuela: widget.escuela),
      ),
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

  // ------------------ Guardar estudiante ------------------

  Future<bool> _yaExistePorNumeroEnGradoYTanda({
    required String numero,
    required String grado,
    required String tanda,
  }) async {
    final gradoKey = _nameKey(grado);
    final snap = await _estudiantesCol
        .where('matricula', isEqualTo: numero)
        .where('gradoKey', isEqualTo: gradoKey)
        .where('tanda', isEqualTo: tanda)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  Future<bool> _yaExistePorNombreDob({
    required String nombresKey,
    required String apellidosKey,
    required DateTime dob,
  }) async {
    final snap = await _estudiantesCol
        .where('nombresKey', isEqualTo: nombresKey)
        .where('apellidosKey', isEqualTo: apellidosKey)
        .limit(8)
        .get();

    for (final d in snap.docs) {
      final data = d.data();
      final ts = data['fechaNacimiento'];
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

    final numero = _matriculaCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final dup = await _yaExistePorNumeroEnGradoYTanda(
        numero: numero,
        grado: grado,
        tanda: tanda,
      );

      if (dup) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ese número ya existe en este grado y tanda')),
        );
        return;
      }

      // ✅ Evita duplicado por nombre+dob (seguro extra)
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

      // ✅ ID GLOBAL (se guarda dentro del estudiante + índice global)
      final studentRef = _estudiantesCol.doc(); // genera id aleatorio
      final idGlobal = studentRef.id;

      final batch = _db.batch();

      final nivelDb = nivelToDb(_nivelSel);
      final nivelTxt = nivelLabel(_nivelSel);

      // 1) Doc principal dentro de la escuela
      batch.set(studentRef, {
        // ✅ ID GLOBAL (dos nombres por compatibilidad)
        'idGlobal': idGlobal,
        'fx': idGlobal,

        // ✅ NIVEL (nuevo)
        'nivel': nivelDb,
        'nivelLabel': nivelTxt,

        // ✅ Útil para búsquedas / auditoría
        'schoolId': _schoolId,
        'schoolRef': 'escuelas/$_schoolId',

        'nombres': nombres,
        'apellidos': apellidos,
        'nombresKey': _nameKey(nombres),
        'apellidosKey': _nameKey(apellidos),

        // ✅ Se mantiene "matricula" para compatibilidad
        'matricula': numero,

        'grado': grado,
        'gradoKey': _nameKey(grado),

        // ✅ TANDA
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

        // ⚠️ MVP: esto es texto plano. Si luego lo usarás para login real,
        // mejor hash (backend) o Firebase Auth.
        'password': _passwordAlumno,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2) Índice global (para buscar estudiantes en TODO el sistema)
      final globalRef = _estudiantesGlobalCol.doc(idGlobal);
      batch.set(globalRef, {
        'idGlobal': idGlobal,
        'fx': idGlobal,
        'schoolId': _schoolId,
        'studentPath': studentRef.path,

        // ✅ NIVEL (nuevo)
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

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Limpieza
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

      // Nueva contraseña para el próximo alumno
      setState(() {
        _passwordAlumno = _genPassword(len: 10);
        // Para que la lista se quede viendo ese grado automáticamente
        _gradoSeleccionadoLista = grado;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estudiante registrado en $nivelTxt')),
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

  void _setNivel(NivelAcademico n, List<String> gradosDelNivel) {
    setState(() {
      _nivelSel = n;

      // Resetea grado si no pertenece al nivel nuevo
      if (_gradoSeleccionadoForm != null &&
          inferNivelFromGradoName(_gradoSeleccionadoForm!) != _nivelSel) {
        _gradoSeleccionadoForm = null;
      }
      if (_gradoSeleccionadoLista != null &&
          inferNivelFromGradoName(_gradoSeleccionadoLista!) != _nivelSel) {
        _gradoSeleccionadoLista = null;
      }

      // Defaults para el nivel
      if (gradosDelNivel.isNotEmpty) {
        _gradoSeleccionadoForm ??= gradosDelNivel.first;
        _gradoSeleccionadoLista ??= gradosDelNivel.first;
      }
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
              final gradesAll = gradeDocs
                  .map((d) => (d.data()['name'] ?? '').toString().trim())
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

              final baseAll = gradesAll.isNotEmpty ? gradesAll : _gradosFallbackRD;

              // ✅ Filtrado de grados por nivel
              final gradesNivel = filtrarGradosPorNivel(
                all: baseAll,
                fallbackRD: _gradosFallbackRD,
                nivel: _nivelSel,
              );

              // ✅ Mantener selections consistentes con el nivel actual
              if (_gradoSeleccionadoForm != null &&
                  !gradesNivel.contains(_gradoSeleccionadoForm)) {
                _gradoSeleccionadoForm = null;
              }
              if (_gradoSeleccionadoLista != null &&
                  !gradesNivel.contains(_gradoSeleccionadoLista)) {
                _gradoSeleccionadoLista = null;
              }

              // ✅ Defaults (solo si quedaron null)
              if (_gradoSeleccionadoForm == null && gradesNivel.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _gradoSeleccionadoForm = gradesNivel.first;
                    _gradoSeleccionadoLista ??= gradesNivel.first;
                  });
                });
              }

              final isWide = MediaQuery.of(context).size.width >= 980;

              final formPanel = _FormPanel(
                nivel: _nivelSel,
                onNivelChanged: (n) => _setNivel(n, gradesNivel),

                permitirFotoAlumno: _permitirFotoAlumno,
                gradesNivel: gradesNivel,
                saving: _saving,
                formKey: _formKey,
                nombresCtrl: _nombresCtrl,
                apellidosCtrl: _apellidosCtrl,
                matriculaCtrl: _matriculaCtrl,
                direccionCtrl: _direccionCtrl,
                observCtrl: _observCtrl,
                fechaCtrl: _fechaCtrl,
                edadCtrl: _edadCtrl,
                gradoSeleccionado: _gradoSeleccionadoForm,
                onGradoChanged: (v) => setState(() {
                  _gradoSeleccionadoForm = v;
                  if (v != null && v.trim().isNotEmpty) {
                    _gradoSeleccionadoLista = v;
                  }
                }),

                // ✅ TANDA
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
                passwordAlumno: _passwordAlumno,
                onCopyPassword: () => _copy(_passwordAlumno),
                onRegenerarPassword: () => setState(() {
                  _passwordAlumno = _genPassword(len: 10);
                }),
                onCrearGrado: _irAGrados,
                onGuardar: _guardar,
                normalizeName: _normalizeName,
                normalizePhone: _normalizePhone,
              );

              final listPanel = _ListPanel(
                nivel: _nivelSel,
                gradesNivel: gradesNivel,
                gradoSeleccionadoLista: _gradoSeleccionadoLista,
                onGradoChanged: (v) =>
                    setState(() => _gradoSeleccionadoLista = v),
                searchCtrl: _searchListCtrl,
                onSearchChanged: (v) =>
                    setState(() => _searchList = v.trim().toLowerCase()),
                schoolId: _schoolId,
                search: _searchList,
              );

              if (!isWide) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                      children: [formPanel],
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

  // ✅ TANDA (props)
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

  final String passwordAlumno;
  final VoidCallback onCopyPassword;
  final VoidCallback onRegenerarPassword;

  final VoidCallback onCrearGrado;
  final VoidCallback onGuardar;

  final String Function(String) normalizeName;
  final String Function(String) normalizePhone;

  const _FormPanel({
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
    required this.passwordAlumno,
    required this.onCopyPassword,
    required this.onRegenerarPassword,
    required this.onCrearGrado,
    required this.onGuardar,
    required this.normalizeName,
    required this.normalizePhone,
  });

  @override
  Widget build(BuildContext context) {
    final nTxt = nivelLabel(nivel);

    final title = 'Formulario de inscripción • $nTxt';
    final subtitle = (nivel == NivelAcademico.inicial)
        ? 'Inicial: registro con estilo más infantil para identificarlo rápido.'
        : 'Registra estudiantes con datos completos + tutor(es). Los nombres se corrigen automáticamente para evitar errores.';

    final icon = Icon(nivelIcon(nivel), color: _orange);

    final softBg = (nivel == NivelAcademico.inicial)
        ? _orange.withOpacity(0.06)
        : Colors.white;

    return _CardShell(
      title: title,
      subtitle: subtitle,
      icon: icon,
      background: softBg,
      child: Form(
        key: formKey,
        child: Column(
          children: [
            // ✅ Selector rápido de nivel dentro del formulario también
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

            const _SectionTitle('Datos del estudiante'),
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

            // ✅ Matrícula + Tanda + Grado (misma fila)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: matriculaCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula o Número',
                      hintText: 'Ej: 12 (número de lista) o código interno',
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
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: onTandaChanged,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Selecciona la tanda' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: gradoSeleccionado,
                    decoration: InputDecoration(
                      labelText: 'Grado ($nTxt)',
                      border: const OutlineInputBorder(),
                    ),
                    items: gradesNivel
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: onGradoChanged,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Selecciona grado'
                        : null,
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
                labelText: 'Email (opcional)',
                border: OutlineInputBorder(),
              ),
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

            const SizedBox(height: 14),
            const _SectionTitle('Credenciales del alumno (MVP)'),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Contraseña: $passwordAlumno',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar',
                    onPressed: onCopyPassword,
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: 'Regenerar',
                    onPressed: onRegenerarPassword,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

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
                onPressed: saving ? null : onGuardar,
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
                label: Text(saving ? 'Guardando...' : 'Registrar estudiante'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListPanel extends StatelessWidget {
  final NivelAcademico nivel;

  final List<String> gradesNivel;
  final String? gradoSeleccionadoLista;
  final ValueChanged<String?> onGradoChanged;

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;

  final String schoolId;
  final String search;

  const _ListPanel({
    required this.nivel,
    required this.gradesNivel,
    required this.gradoSeleccionadoLista,
    required this.onGradoChanged,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.schoolId,
    required this.search,
  });

  CollectionReference<Map<String, dynamic>> get _estudiantesCol =>
      FirebaseFirestore.instance
          .collection('escuelas')
          .doc(schoolId)
          .collection('estudiantes');

  @override
  Widget build(BuildContext context) {
    final nTxt = nivelLabel(nivel);

    return _CardShell(
      title: 'Estudiantes por grado • $nTxt',
      subtitle:
          'Selecciona un grado y verás los estudiantes de este nivel. El sistema reconoce registros viejos sin "nivel" por el nombre del grado.',
      icon: const Icon(Icons.school, color: _orange),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: gradoSeleccionadoLista,
            decoration: const InputDecoration(
              labelText: 'Grado',
              border: OutlineInputBorder(),
            ),
            items: gradesNivel
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: onGradoChanged,
          ),
          const SizedBox(height: 10),
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
          if (gradoSeleccionadoLista == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Selecciona un grado para ver estudiantes.'),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _estudiantesCol
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

                final rows = docs.map((d) {
                  final data = d.data();
                  final nombres = (data['nombres'] ?? '').toString();
                  final apellidos = (data['apellidos'] ?? '').toString();
                  final numero = (data['matricula'] ?? '').toString();
                  final grado = (data['grado'] ?? '').toString();
                  final edad = (data['edad'] ?? '').toString();

                  // ✅ Nivel real si existe, si no, inferido por grado
                  final nivelDb = (data['nivel'] ?? '').toString().trim();
                  final nivelDoc = nivelDb.isNotEmpty
                      ? (nivelDb == 'inicial'
                          ? NivelAcademico.inicial
                          : (nivelDb == 'secundaria'
                              ? NivelAcademico.secundaria
                              : NivelAcademico.primaria))
                      : inferNivelFromGradoName(grado);

                  final key = ('$nombres $apellidos $numero').toLowerCase();
                  return {
                    'id': d.id,
                    'nombres': nombres,
                    'apellidos': apellidos,
                    'numero': numero,
                    'grado': grado,
                    'edad': edad,
                    'nivel': nivelDoc,
                    'key': key,
                  };
                }).toList();

                // ✅ Filtra por nivel (client-side para no perder datos viejos)
                final rowsNivel = rows
                    .where((r) => (r['nivel'] as NivelAcademico) == nivel)
                    .toList();

                final q = search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? rowsNivel
                    : rowsNivel
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
                    child: Text('No hay estudiantes para mostrar.'),
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.person, color: _orange),
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

                          final sub = [
                            if ((r['numero'] as String).isNotEmpty)
                              'Número: ${r['numero']}',
                            if ((r['edad'] as String).isNotEmpty)
                              'Edad: ${r['edad']}',
                            if ((r['grado'] as String).isNotEmpty)
                              'Grado: ${r['grado']}',
                          ].join(' • ');

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _orange.withOpacity(0.12),
                              child: const Icon(Icons.person, color: _orange),
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                Icon(nivelIcon(n), size: 18, color: selected ? _blue : Colors.grey.shade700),
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
