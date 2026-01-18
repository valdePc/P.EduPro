// lib/admin_escolar/screens/crear_cuenta_docente.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show sharedSubjectsService;
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef OnCreateRequest = Future<void> Function(Map<String, dynamic> request);

class CrearCuentaDocentesScreen extends StatefulWidget {
  final Escuela escuela;
  final List<String> nombresDisponibles;
  final List<String> asignaturasDisponibles;
  final OnCreateRequest? onRequestCreate;

  const CrearCuentaDocentesScreen({
    Key? key,
    required this.escuela,
    this.nombresDisponibles = const [],
    this.asignaturasDisponibles = const [],
    this.onRequestCreate,
  }) : super(key: key);

  @override
  State<CrearCuentaDocentesScreen> createState() =>
      _CrearCuentaDocentesScreenState();
}

class _CrearCuentaDocentesScreenState extends State<CrearCuentaDocentesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;

  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _buscadorAsignaturaCtrl = TextEditingController();

  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();

  static const List<String> _dialCodes = [
    '+1',
    '+34',
    '+57',
    '+52',
    '+51',
    '+56',
    '+54'
  ];
  String _dialCode = '+1';
  final TextEditingController _phoneLocalCtrl = TextEditingController();

  final List<String> _asignaturasSeleccionadas = [];
  List<String> _availableSubjects = [];

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _confirmSavedPassword = false;

  // Intentos de rutas “típicas” donde podrías tener asignaturas
  static const List<String> _subjectCollectionsCandidates = [
    'subjects',
    'asignaturas',
    'materias',
    'catalog_subjects',
    'subjects_catalog',
    'catalogo_asignaturas',
  ];

  @override
  void initState() {
    super.initState();

    // Cargar lo más pronto posible.
    // Si el widget trae asignaturasDisponibles, también se usa,
    // pero refrescar siempre ayuda cuando el service no coincide con la escuela.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSubjects();
    });
  }

  @override
  void didUpdateWidget(covariant CrearCuentaDocentesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asignaturasDisponibles != widget.asignaturasDisponibles) {
      // Si vienen desde arriba, actualiza y retén selección válida
      setState(() {
        _availableSubjects = List<String>.from(widget.asignaturasDisponibles)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _asignaturasSeleccionadas
            .retainWhere((s) => _availableSubjects.contains(s));
      });
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _buscadorAsignaturaCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _phoneLocalCtrl.dispose();
    super.dispose();
  }

  // ----------------------------
  // Helpers
  // ----------------------------
  String _stripAccents(String s) {
    const from = 'ÁÀÂÄÃáàâäãÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕóòôöõÚÙÛÜúùûüÑñ';
    const to = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNn';
    for (int i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  String _normalizeTeacherLoginKey(String name) {
    final cleaned = _stripAccents(name).trim().toLowerCase();
    return cleaned
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'\.+'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
  }

  String _phoneDigitsForHash(String phone) => phone.replaceAll(RegExp(r'\D'), '');
  String _sha1Hex(String s) => sha1.convert(utf8.encode(s)).toString();

  String _buildTeacherAuthEmail({
    required String teacherId,
    required String schoolId,
  }) {
    return 'teacher_${teacherId}_$schoolId@edupro.app';
  }

  Future<FirebaseAuth> _secondaryAuth() async {
    const name = 'teacherSelfSignup';
    try {
      final app = Firebase.app(name);
      return FirebaseAuth.instanceFor(app: app);
    } catch (_) {
      final app = await Firebase.initializeApp(
        name: name,
        options: Firebase.app().options,
      );
      return FirebaseAuth.instanceFor(app: app);
    }
  }

  Future<String> _makeUniqueLoginKey({
    required String schoolId,
    required String base,
  }) async {
    var candidate = base;
    for (int i = 0; i < 20; i++) {
      final snap = await _db
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .where('loginKey', isEqualTo: candidate)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return candidate;
      final n = (DateTime.now().millisecondsSinceEpoch % 90) + 10; // 10..99
      candidate = '$base.$n';
    }
    return '${base}.${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  int _passwordStrengthScore(String pwd) {
    var score = 0;
    if (pwd.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score++;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)) score++;
    return score; // 0..4
  }

  String _passwordStrengthLabel(String pwd) {
    final s = _passwordStrengthScore(pwd);
    switch (s) {
      case 0:
      case 1:
        return 'Débil';
      case 2:
        return 'Aceptable';
      case 3:
        return 'Buena';
      case 4:
        return 'Fuerte';
      default:
        return '';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _refreshSubjects() async {
    if (_loading) return;

    setState(() => _loading = true);
    try {
      // 1) Si el widget trae lista, úsala primero
      if (widget.asignaturasDisponibles.isNotEmpty) {
        final names = List<String>.from(widget.asignaturasDisponibles)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        if (!mounted) return;
        setState(() {
          _availableSubjects = names;
          _asignaturasSeleccionadas
              .retainWhere((s) => _availableSubjects.contains(s));
        });
        _snack('Asignaturas cargadas (${names.length}).');
        return;
      }

      // 2) Intento por servicio compartido (si existe y funciona)
      try {
        final list = await sharedSubjectsService.getSubjects();
        final names = list
            .map((s) => s.name.toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        if (names.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _availableSubjects = names;
            _asignaturasSeleccionadas
                .retainWhere((s) => _availableSubjects.contains(s));
          });
          _snack('Asignaturas actualizadas (${names.length}).');
          return;
        }
      } catch (_) {
        // seguimos al fallback
      }

      // 3) Fallback directo a Firestore (por escuela)
      final schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
      final out = <String>{};

      // 3A) Campos array dentro de schools/{schoolId}
      try {
        final doc = await _db.collection('schools').doc(schoolId).get();
        final data = doc.data() ?? {};
        final a = (data['subjects'] is List) ? List.from(data['subjects']) : const [];
        final b =
            (data['asignaturas'] is List) ? List.from(data['asignaturas']) : const [];
        final c = (data['materias'] is List) ? List.from(data['materias']) : const [];

        for (final x in [...a, ...b, ...c]) {
          final s = x.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      } catch (_) {}

      // 3B) Subcolecciones posibles dentro de schools/{schoolId}/...
      for (final col in _subjectCollectionsCandidates) {
        try {
          final snap = await _db
              .collection('schools')
              .doc(schoolId)
              .collection(col)
              .limit(300)
              .get();

          for (final d in snap.docs) {
            final m = d.data();
            final name = (m['name'] ??
                    m['title'] ??
                    m['nombre'] ??
                    m['asignatura'] ??
                    m['materia'] ??
                    d.id)
                .toString()
                .trim();
            if (name.isNotEmpty) out.add(name);
          }
        } catch (_) {}
      }

      final names = out.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _availableSubjects = names;
        _asignaturasSeleccionadas
            .retainWhere((s) => _availableSubjects.contains(s));
      });

      if (names.isEmpty) {
        _snack('No se encontraron asignaturas en este colegio.');
      } else {
        _snack('Asignaturas actualizadas (${names.length}).');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ✅ FIX: selector de asignaturas realmente “selecciona”
  Future<void> _openSeleccionAsignaturas() async {
    final List<String> all = List<String>.from(_availableSubjects);
    all.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final selectedLocal = <String>{..._asignaturasSeleccionadas};
    String filter = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) {
          final filtered = filter.trim().isEmpty
              ? all
              : all
                  .where((s) =>
                      s.toLowerCase().contains(filter.trim().toLowerCase()))
                  .toList();

          void toggleLocal(String s) {
            setModalState(() {
              if (selectedLocal.contains(s)) {
                selectedLocal.remove(s);
              } else {
                selectedLocal.add(s);
              }
            });
          }

          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.80,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (_, controller) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buscadorAsignaturaCtrl,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Buscar asignatura...',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setModalState(() => filter = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: all.isEmpty
                              ? null
                              : () => setModalState(() {
                                    selectedLocal
                                      ..clear()
                                      ..addAll(all);
                                  }),
                          child: const Text('Todas'),
                        ),
                        TextButton(
                          onPressed: selectedLocal.isEmpty
                              ? null
                              : () => setModalState(() {
                                    selectedLocal.clear();
                                  }),
                          child: const Text('Ninguna'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                all.isEmpty
                                    ? 'No hay asignaturas disponibles. Pulsa “Refrescar” o contacta a la administración.'
                                    : 'No se encontraron coincidencias.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: controller,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              final selected = selectedLocal.contains(s);

                              return CheckboxListTile(
                                value: selected,
                                title: Text(s),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: _loading ? null : (_) => toggleLocal(s),
                                secondary: selected
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green)
                                    : null,
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _asignaturasSeleccionadas
                                  ..clear()
                                  ..addAll(selectedLocal.toList()
                                    ..sort((a, b) => a
                                        .toLowerCase()
                                        .compareTo(b.toLowerCase())));
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Guardar selección'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    _buscadorAsignaturaCtrl.clear();
  }

  // ----------------------------
  // SUBMIT
  // ----------------------------
Future<void> _submit() async {
  if (_loading) return;
  if (!_formKey.currentState!.validate()) return;

  if (_asignaturasSeleccionadas.isEmpty) {
    _snack('Selecciona al menos una asignatura');
    return;
  }

  final rawSchoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  final schoolId = rawSchoolId.trim().replaceAll('/', '_'); // ✅ mismo criterio que login

  final name = _nombreCtrl.text.trim();
  final emailLower = _emailCtrl.text.trim().toLowerCase();

  final phoneLocal = _phoneLocalCtrl.text.trim();
  final phoneFull = phoneLocal.isEmpty ? '' : '$_dialCode$phoneLocal';
  final phoneHash = phoneFull.isEmpty ? '' : _sha1Hex(_phoneDigitsForHash(phoneFull));

  setState(() => _loading = true);

  try {
    // ✅ Anti-duplicados: revisa teachers y teacher_directory
    final dup1 = await _db
        .collection('schools').doc(schoolId)
        .collection('teachers')
        .where('emailLower', isEqualTo: emailLower)
        .limit(1).get();

    final dup2 = await _db
        .collection('schools').doc(schoolId)
        .collection('teacher_directory')
        .where('emailLower', isEqualTo: emailLower)
        .limit(1).get();

    if (dup1.docs.isNotEmpty || dup2.docs.isNotEmpty) {
      _snack('Ya existe una solicitud o cuenta con ese correo.');
      setState(() => _loading = false);
      return;
    }

    if (phoneHash.isNotEmpty) {
      final dupP1 = await _db
          .collection('schools').doc(schoolId)
          .collection('teachers')
          .where('phoneHash', isEqualTo: phoneHash)
          .limit(1).get();

      final dupP2 = await _db
          .collection('schools').doc(schoolId)
          .collection('teacher_directory')
          .where('phoneHash', isEqualTo: phoneHash)
          .limit(1).get();

      if (dupP1.docs.isNotEmpty || dupP2.docs.isNotEmpty) {
        _snack('Ya existe una solicitud o cuenta con ese teléfono.');
        setState(() => _loading = false);
        return;
      }
    }

    // loginKey único
    final baseLoginKey = _normalizeTeacherLoginKey(name);
    final loginKey = await _makeUniqueLoginKey(schoolId: schoolId, base: baseLoginKey);

    // ✅ mismo teacherId para teachers y teacher_directory
    final teacherRef = _db.collection('schools').doc(schoolId).collection('teachers').doc();
    final teacherId = teacherRef.id;

    final now = FieldValue.serverTimestamp();

    // teachers (privado / completo)
    await teacherRef.set({
      'teacherId': teacherId,
      'schoolId': schoolId,
      'name': name,
      'loginKey': loginKey,

      'emailLower': emailLower,
      'email': emailLower,

      'phone': phoneFull,
      'phoneDialCode': _dialCode,
      'phoneLocal': phoneLocal,
      if (phoneHash.isNotEmpty) 'phoneHash': phoneHash,

      'subjects': List<String>.from(_asignaturasSeleccionadas),

      'status': 'blocked',
      'statusLower': 'blocked',
      'statusLabel': 'Bloqueado',

      'createdFrom': 'self_signup_google',
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // teacher_directory (lo que usa el login)
    await _db
        .collection('schools')
        .doc(schoolId)
        .collection('teacher_directory')
        .doc(teacherId)
        .set({
      'teacherId': teacherId,
      'schoolId': schoolId,
      'loginKey': loginKey,
      'name': name,

      'emailLower': emailLower,
      if (phoneHash.isNotEmpty) 'phoneHash': phoneHash,

      'status': 'blocked',
      'statusLower': 'blocked',
      'statusLabel': 'Bloqueado',

      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));

    // limpiar UI
    _asignaturasSeleccionadas.clear();
    _nombreCtrl.clear();
    _emailCtrl.clear();
    _phoneLocalCtrl.clear();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Solicitud enviada'),
        content: const Text(
          'Tu solicitud fue enviada y está bloqueada hasta aprobación.\n'
          'Cuando la administración la active, podrás entrar con “Iniciar con Google”.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    setState(() => _loading = false);
  } catch (e) {
    if (!mounted) return;
    setState(() => _loading = false);
    _snack('Error al crear la solicitud: $e');
  }
}

  // ----------------------------
  // UI
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);

    final pwd = _passwordCtrl.text;
    final pwdScore = _passwordStrengthScore(pwd);
    final pwdLabel = _passwordStrengthLabel(pwd);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta - Docente'),
        backgroundColor: Colors.blue,
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Refrescar asignaturas',
            onPressed: _loading ? null : _refreshSubjects,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.escuela.nombre ?? 'Escuela',
                          style: headerStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Solicita la creación de tu cuenta. La administración aprobará y activará el acceso.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),

                      Autocomplete<String>(
                        optionsBuilder: (textEditingValue) {
                          final q = textEditingValue.text.toLowerCase();
                          return widget.nombresDisponibles
                              .where((n) => n.toLowerCase().contains(q))
                              .toList();
                        },
                        onSelected: (sel) => _nombreCtrl.text = sel,
                        fieldViewBuilder: (context, controller, focusNode, _) {
                          controller.text = _nombreCtrl.text;
                          controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: controller.text.length),
                          );

                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Tu nombre (búscalo en la lista)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Indica tu nombre'
                                : null,
                            onChanged: (v) => _nombreCtrl.text = v,
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo (para referencia)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                          hintText: 'Ej: profe@gmail.com',
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim().toLowerCase();
                          final ok =
                              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
                          if (!ok) return 'Escribe un correo válido';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              value: _dialCode,
                              items: _dialCodes
                                  .map((dc) => DropdownMenuItem(
                                      value: dc, child: Text(dc)))
                                  .toList(),
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(
                                      () => _dialCode = v ?? _dialCode),
                              decoration: const InputDecoration(
                                labelText: 'Código',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneLocalCtrl,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(15),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Teléfono (opcional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.phone),
                                hintText: 'Ej: 8091234567',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: _loading
                                ? null
                                : () => setState(
                                    () => _showPassword = !_showPassword),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.length < 8) {
                            return 'La contraseña debe tener al menos 8 caracteres';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: pwd.isEmpty ? 0 : (pwdScore / 4),
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              color: pwdScore <= 1
                                  ? Colors.redAccent
                                  : (pwdScore == 2
                                      ? Colors.orange
                                      : Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(pwd.isEmpty ? '' : pwdLabel,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: !_showConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar contraseña',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_showConfirm
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: _loading
                                ? null
                                : () => setState(
                                    () => _showConfirm = !_showConfirm),
                          ),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Confirma tu contraseña';
                          if (s != _passwordCtrl.text.trim()) {
                            return 'Las contraseñas no coinciden';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      CheckboxListTile(
                        value: _confirmSavedPassword,
                        onChanged: _loading
                            ? null
                            : (v) => setState(
                                () => _confirmSavedPassword = v ?? false),
                        title: const Text('He guardado mi contraseña'),
                        subtitle: const Text(
                          'No se guarda en Firestore. Si la pierdes, tendrás que pedir soporte.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Text('Asignaturas',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _loading ? null : _refreshSubjects,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Refrescar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _asignaturasSeleccionadas)
                            InputChip(
                              label: Text(s),
                              onDeleted: _loading
                                  ? null
                                  : () => setState(() {
                                        _asignaturasSeleccionadas.remove(s);
                                      }),
                              selected: true,
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: Text(_asignaturasSeleccionadas.isEmpty
                                ? 'Seleccionar asignaturas'
                                : 'Agregar / editar'),
                            onPressed: _loading ? null : _openSeleccionAsignaturas,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: const Text(
                          'La administración aprobará la cuenta. Mientras esté bloqueada, no podrás iniciar sesión.',
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange),
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  'Solicitar creación de cuenta',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('¿Necesitas ayuda?'),
                                    content: const Text(
                                      'La administración mantiene la lista oficial de docentes y asignaturas. '
                                      'Si tu nombre o asignaturas no aparecen, solicita al administrador que te agregue.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cerrar'),
                                      )
                                    ],
                                  ),
                                );
                              },
                        child: const Text('¿Por qué debo solicitar mi cuenta?'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
