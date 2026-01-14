// lib/admin_escolar/screens/A_usuarios.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;
import 'package:flutter/material.dart';

import 'A_usuario_detalle.dart';

class AUsuarios extends StatefulWidget {
  final Escuela escuela;
  const AUsuarios({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AUsuarios> createState() => _AUsuariosState();
}

class _AUsuariosState extends State<AUsuarios> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _search = '';
  String _rol = 'Todos'; // Todos | Docente | Estudiante
  String? _grado; // solo estudiantes
  int? _edad; // solo estudiantes

  String get _schoolId => normalizeSchoolIdFromEscuela(widget.escuela);

  Stream<QuerySnapshot<Map<String, dynamic>>> _docentesStream() {
    return _db
        .collection('escuelas')
        .doc(_schoolId)
        .collection('docentes')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _estudiantesStream() {
    return _db
        .collection('escuelas')
        .doc(_schoolId)
        .collection('estudiantes')
        .snapshots();
  }

  // -------- Helpers de lectura flexible de campos --------
  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  // ✅ arma nombre aunque venga como Nombres/Apellidos
  String _nombre(Map<String, dynamic> data) {
    final full = _pickString(data, [
      'nombreCompleto',
      'nombre',
      'name',
      'fullName',
      'nombreAlumno',
      'alumno',
      'NombreCompleto',
      'Nombre',
    ]);
    if (full.isNotEmpty) return full;

    final nombres = _pickString(data, [
      'nombres',
      'Nombres',
      'primerNombre',
      'PrimerNombre',
      'nombre1',
    ]);
    final apellidos = _pickString(data, [
      'apellidos',
      'Apellidos',
      'apellido',
      'Apellido',
      'segundoApellido',
    ]);

    final armado = ('$nombres $apellidos')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (armado.isNotEmpty) return armado;

    if (apellidos.isNotEmpty) return apellidos;
    return 'Sin nombre';
  }

  String _gradoAlumno(Map<String, dynamic> data) =>
      _pickString(data, ['grado', 'curso', 'nivel', 'grade', 'Grado']);

  DateTime? _fechaNacimiento(Map<String, dynamic> data) {
    final v = data['fechaNacimiento'] ??
        data['nacimiento'] ??
        data['dob'] ??
        data['birthDate'] ??
        data['FechaNacimiento'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  int? _calcularEdad(DateTime? dob) {
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthdayThisYear =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age--;
    if (age < 0 || age > 120) return null;
    return age;
  }

  // -------- UI Helpers --------
  Widget _rolChip(String label) {
    final selected = _rol == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _rol = label;
          if (_rol == 'Docente') {
            _grado = null;
            _edad = null;
          }
        });
      },
    );
  }

  void _openDetalle(_UsuarioRow u) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AUsuarioDetalle(
          escuela: widget.escuela,
          rol: u.rol,
          userId: u.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final azul = Colors.blue.shade900;
    final naranja = Colors.orange;

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        automaticallyImplyLeading: true,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usuarios',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Buscador
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar por nombre...',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 10),

            // Chips de rol
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _rolChip('Todos'),
                _rolChip('Docente'),
                _rolChip('Estudiante'),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _docentesStream(),
                builder: (context, docentesSnap) {
                  if (docentesSnap.hasError) {
                    return _errorBox('Error cargando docentes: ${docentesSnap.error}');
                  }
                  if (docentesSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _estudiantesStream(),
                    builder: (context, estSnap) {
                      if (estSnap.hasError) {
                        return _errorBox('Error cargando estudiantes: ${estSnap.error}');
                      }
                      if (estSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docentesDocs = docentesSnap.data?.docs ?? [];
                      final estDocs = estSnap.data?.docs ?? [];

                      final all = <_UsuarioRow>[
                        ...docentesDocs.map((d) => _UsuarioRow(
                              id: d.id,
                              rol: 'Docente',
                              data: d.data(),
                              nombre: _nombre(d.data()),
                              grado: null,
                              edad: null,
                            )),
                        ...estDocs.map((s) {
                          final data = s.data();
                          final dob = _fechaNacimiento(data);
                          final edad = _calcularEdad(dob) ??
                              (data['edad'] is int ? data['edad'] as int : null);

                          final g = _gradoAlumno(data);
                          return _UsuarioRow(
                            id: s.id,
                            rol: 'Estudiante',
                            data: data,
                            nombre: _nombre(data),
                            grado: g.isEmpty ? null : g,
                            edad: edad,
                          );
                        }),
                      ];

                      // Opciones dinámicas para filtros de estudiantes
                      final gradosDisponibles = all
                          .where((u) =>
                              u.rol == 'Estudiante' &&
                              (u.grado ?? '').trim().isNotEmpty)
                          .map((u) => u.grado!)
                          .toSet()
                          .toList()
                        ..sort();

                      final edadesDisponibles = all
                          .where((u) => u.rol == 'Estudiante' && u.edad != null)
                          .map((u) => u.edad!)
                          .toSet()
                          .toList()
                        ..sort();

                      final q = _search.trim().toLowerCase();

                      final filtered = all.where((u) {
                        if (_rol != 'Todos' && u.rol != _rol) return false;
                        if (q.isNotEmpty && !u.nombre.toLowerCase().contains(q)) {
                          return false;
                        }
                        if (u.rol == 'Estudiante') {
                          if (_grado != null && u.grado != _grado) return false;
                          if (_edad != null && u.edad != _edad) return false;
                        }
                        return true;
                      }).toList()
                        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_rol != 'Docente') ...[
                            Row(
                              children: [
                                Expanded(child: _dropdownGrado(gradosDisponibles)),
                                const SizedBox(width: 10),
                                Expanded(child: _dropdownEdad(edadesDisponibles)),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],

                          Row(
                            children: [
                              Text(
                                'Coincidencias: ${filtered.length}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                'Docentes: ${docentesDocs.length} • Estudiantes: ${estDocs.length}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Expanded(
                            child: filtered.isEmpty
                                ? _emptyBox()
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, i) {
                                      final u = filtered[i];
                                      final nombre = u.nombre.isEmpty ? 'Sin nombre' : u.nombre;

                                      final initial = nombre.isNotEmpty
                                          ? nombre.trim()[0].toUpperCase()
                                          : '?';

                                      final resumen = (u.rol == 'Estudiante')
                                          ? 'Grado: ${u.grado ?? '—'} • Edad: ${u.edad?.toString() ?? '—'}'
                                          : 'Docente';

                                      // ✅ Tarjeta EduPro
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () => _openDetalle(u),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white,
                                                Colors.blue.withOpacity(.03)
                                              ],
                                            ),
                                            border: Border.all(
                                                color: Colors.grey.shade200),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(.05),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              )
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      azul.withOpacity(.92),
                                                      naranja.withOpacity(.92),
                                                    ],
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    initial,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            nombre,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight.w900,
                                                              fontSize: 15.5,
                                                              color: azul,
                                                            ),
                                                            overflow:
                                                                TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        _rolBadge(u.rol),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      resumen,
                                                      style: TextStyle(
                                                        color: Colors.grey.shade700,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(Icons.chevron_right,
                                                  color: azul.withOpacity(.6)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownGrado(List<String> grados) {
    return DropdownButtonFormField<String>(
      value: _grado,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Grado',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos')),
        ...grados.map((g) => DropdownMenuItem(value: g, child: Text(g))),
      ],
      onChanged: (_rol == 'Docente') ? null : (v) => setState(() => _grado = v),
    );
  }

  Widget _dropdownEdad(List<int> edades) {
    return DropdownButtonFormField<int>(
      value: _edad,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Edad',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todas')),
        ...edades.map((e) => DropdownMenuItem(value: e, child: Text('$e'))),
      ],
      onChanged: (_rol == 'Docente') ? null : (v) => setState(() => _edad = v),
    );
  }

  Widget _rolBadge(String rol) {
    final isDoc = rol == 'Docente';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isDoc ? Colors.blue.withOpacity(0.12) : Colors.green.withOpacity(0.12),
      ),
      child: Text(
        rol,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDoc ? Colors.blue : Colors.green,
        ),
      ),
    );
  }

  Widget _emptyBox() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.person_outline, size: 64),
          SizedBox(height: 12),
          Text('No hay usuarios que coincidan con el filtro'),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Center(
      child: Text(
        msg,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _UsuarioRow {
  final String id;
  final String rol; // Docente / Estudiante
  final Map<String, dynamic> data;
  final String nombre;
  final String? grado;
  final int? edad;

  const _UsuarioRow({
    required this.id,
    required this.rol,
    required this.data,
    required this.nombre,
    required this.grado,
    required this.edad,
  });
}
