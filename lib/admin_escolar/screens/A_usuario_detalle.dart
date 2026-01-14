import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;
import 'package:flutter/material.dart';

class AUsuarioDetalle extends StatelessWidget {
  final Escuela escuela;
  final String rol; // 'Estudiante' | 'Docente'
  final String userId;

  const AUsuarioDetalle({
    super.key,
    required this.escuela,
    required this.rol,
    required this.userId,
  });

  String get _schoolId => normalizeSchoolIdFromEscuela(escuela);

  DocumentReference<Map<String, dynamic>> _ref(FirebaseFirestore db) {
    final col = rol == 'Docente' ? 'docentes' : 'estudiantes';
    return db.collection('escuelas').doc(_schoolId).collection(col).doc(userId);
  }

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _nombre(Map<String, dynamic> data) {
    final full = _pickString(data, [
      'nombreCompleto','nombre','fullName','name','nombreAlumno','NombreCompleto','Nombre'
    ]);
    if (full.isNotEmpty) return full;

    final nombres = _pickString(data, ['nombres','Nombres','primerNombre','PrimerNombre']);
    final apellidos = _pickString(data, ['apellidos','Apellidos','apellido','Apellido']);
    final armado = ('$nombres $apellidos').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (armado.isNotEmpty) return armado;

    if (apellidos.isNotEmpty) return apellidos;
    return 'Sin nombre';
  }

  String _grado(Map<String, dynamic> data) =>
      _pickString(data, ['grado','Grado','curso','nivel','grade']);

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
    }
    if (v is List) {
      final s = v.map((e) => e?.toString() ?? '').where((x) => x.trim().isNotEmpty).join(', ');
      return s.isEmpty ? '—' : s;
    }
    if (v is Map) {
      if (v.isEmpty) return '—';
      return v.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
    }
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  bool _isTechKey(String k) {
    final lk = k.toLowerCase();
    return lk.endsWith('key') ||
        lk.endsWith('id') ||
        lk.contains('token') ||
        lk.contains('nombrekey') ||
        lk.contains('apellidoskey') ||
        lk.contains('grado key') ||
        lk.contains('aulaid') ||
        lk.contains('createdat');
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final azul = Colors.blue.shade900;
    final naranja = Colors.orange;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: azul,
        foregroundColor: Colors.white,
        title: Text('Detalle $rol'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref(db).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red)));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('No encontrado.'));
          }

          final data = snap.data!.data() ?? {};
          final nombre = _nombre(data);
          final grado = _grado(data);
          final edad = _fmt(data['edad']);
          final aulaNombre = _pickString(data, ['aulaNombre','aula','seccion','AulaNombre']);
          final direccion = _pickString(data, ['direccion','Direccion','address']);

          // secciones (tú puedes ampliar llaves cuando quieras)
          final identidad = <String, dynamic>{
            'Nombre': nombre,
            if (_pickString(data, ['apellidos','Apellidos']).isNotEmpty) 'Apellidos': _pickString(data, ['apellidos','Apellidos']),
            if (_pickString(data, ['nombres','Nombres']).isNotEmpty) 'Nombres': _pickString(data, ['nombres','Nombres']),
            'Fecha Nacimiento': data['fechaNacimiento'] ?? data['FechaNacimiento'] ?? data['nacimiento'] ?? data['dob'],
            'Edad': data['edad'],
          };

          final escolar = <String, dynamic>{
            'Grado': data['grado'] ?? data['Grado'],
            'Aula': aulaNombre,
            'Turno': data['turno'] ?? data['Turno'],
            'Matrícula': data['matricula'] ?? data['Matricula'],
          };

          final contacto = <String, dynamic>{
            'Dirección': direccion,
            'Teléfono': data['telefono'] ?? data['Telefono'],
            'Correo': data['correo'] ?? data['email'] ?? data['Correo'],
          };

          final tutores = <String, dynamic>{
            'Madre': data['madreNombre'] ?? data['MadreNombre'],
            'Teléfono madre': data['madreTelefono'] ?? data['MadreTelefono'],
            'Padre': data['padreNombre'] ?? data['PadreNombre'],
            'Teléfono padre': data['padreTelefono'] ?? data['PadreTelefono'],
            'Tutor': data['tutorNombre'] ?? data['TutorNombre'],
            'Teléfono tutor': data['tutorTelefono'] ?? data['TutorTelefono'],
          };

          final emergencia = <String, dynamic>{
            'Emergencia': data['emergencia'] ?? data['Emergencia'],
          };

          final notas = <String, dynamic>{
            'Observaciones': data['observaciones'] ?? data['Observaciones'] ?? data['nota'] ?? data['Nota'],
          };

          // campos técnicos que NO quieres arriba
          final tech = <String, dynamic>{};
          for (final k in data.keys) {
            if (_isTechKey(k)) tech[k] = data[k];
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // HEADER PRO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(colors: [azul, Colors.blue.shade700]),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 14, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Colors.white, naranja.withOpacity(.95)]),
                      ),
                      child: Center(
                        child: Text(
                          nombre.isNotEmpty ? nombre.trim()[0].toUpperCase() : '?',
                          style: TextStyle(color: azul, fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip('Grado', grado.isEmpty ? '—' : grado, Colors.white),
                              _chip('Edad', edad == '—' ? '—' : edad, Colors.white),
                              if (aulaNombre.isNotEmpty) _chip('Aula', aulaNombre, Colors.white),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _section('Identidad', Icons.badge, azul, naranja, identidad),
              _section('Escolar', Icons.school, azul, naranja, escolar),
              _section('Contacto', Icons.home, azul, naranja, contacto),
              if (rol == 'Estudiante') _section('Padres / Tutores', Icons.family_restroom, azul, naranja, tutores),
              _section('Emergencia', Icons.emergency, azul, naranja, emergencia),
              _section('Notas', Icons.sticky_note_2, azul, naranja, notas),

              if (tech.isNotEmpty) ...[
                const SizedBox(height: 6),
                _section('Sistema', Icons.settings, azul, naranja, tech, isTech: true),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.18)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    Color azul,
    Color naranja,
    Map<String, dynamic> fields, {
    bool isTech = false,
  }) {
    // elimina los vacíos
    final entries = fields.entries
        .where((e) => _fmt(e.value) != '—')
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [azul.withOpacity(.12), naranja.withOpacity(.12)]),
                  ),
                  child: Icon(icon, color: azul),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: azul),
                  ),
                ),
                if (isTech)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.grey.shade100,
                    ),
                    child: Text('técnico', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => _kv(e.key, _fmt(e.value), azul)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, Color azul) {
    String cleanKey(String key) {
      final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
      return spaced.replaceAll('_', ' ').trim();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              cleanKey(k),
              style: TextStyle(fontWeight: FontWeight.w900, color: azul),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
