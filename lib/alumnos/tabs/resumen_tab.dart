import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../shared/alumno_common.dart';

class ResumenTab extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const ResumenTab({super.key, required this.estRef});

  @override
  State<ResumenTab> createState() => _ResumenTabState();
}

class _ResumenTabState extends State<ResumenTab> {
  bool _showBasics = true;

  String _pick(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final s = AlumnoCommon.s(data[k]).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _mergeGradoSeccion(String grado, String seccion) {
    final g = grado.trim();
    final s = seccion.trim();
    if (g.isEmpty) return s;
    if (s.isEmpty) return g;

    final gl = g.toLowerCase();
    final sl = s.toLowerCase();
    if (gl.contains(sl)) return g;

    // Si termina en número y la sección es 1 letra, pega: "1" + "A" => "1A"
    final endsWithDigit = RegExp(r'\d$').hasMatch(g);
    final oneLetter = RegExp(r'^[A-Za-z]$').hasMatch(s);

    return (endsWithDigit && oneLetter) ? '$g$s' : '$g $s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.estRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorBox('Error: ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final data = snap.data!.data() ?? {};

        // ✅ Nombre con fallbacks (para casos tipo: nombreK/apellidoK)
        final n = _pick(data, ['nombre', 'nombres', 'name', 'nombreK', 'nombresK']);
        final a = _pick(data, ['apellido', 'apellidos', 'lastName', 'apellidoK', 'apellidosK']);
        final nombre = ('$n $a').trim();

        // ✅ Grado + Sección (pero sin mostrar fila Sección)
        final gradoRaw = _pick(data, ['grado', 'aula', 'gradoSeleccionado', 'gradoK']);
        final seccion = _pick(data, ['seccion', 'sección']);
        final grado = _mergeGradoSeccion(gradoRaw, seccion);

        final dob = AlumnoCommon.toDate(data['fechaNacimiento']);
        final edad = AlumnoCommon.calcularEdad(dob);

        final matricula = _pick(data, ['matricula', 'matrícula', 'numeroLista', 'numero', 'nLista']);
        final tanda = _pick(data, ['tanda', 'turno', 'jornada']);
        final idGlobal = _pick(data, ['idGlobal', 'id_global', 'globalId', 'idglobal']);
        final nota = _pick(data, ['nota', 'notas', 'observacion', 'observaciones', 'comentario']);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            NiceCard(
              title: 'Datos básicos (solo lectura)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: _showBasics ? 'Ocultar' : 'Mostrar',
                      icon: Icon(_showBasics ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showBasics = !_showBasics),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState:
                        _showBasics ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                    firstChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Nombre', nombre.isEmpty ? '—' : nombre),
                        _kv('Grado', grado.isEmpty ? '—' : grado),
                        _kv('Tanda', tanda.isEmpty ? '—' : tanda),
                        _kv('Nacimiento', AlumnoCommon.fmtDate(dob)),
                        _kv('Edad', edad?.toString() ?? '—'),
                        _kv('Matrícula', matricula.isEmpty ? '—' : matricula),
                        _kv('ID Global', idGlobal.isEmpty ? '—' : idGlobal),
                        // ❌ Sección ya no se muestra como fila
                      ],
                    ),
                    secondChild: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            NiceCard(
              title: 'Notas',
              child: Text(
                nota.isNotEmpty
                    ? nota
                    : 'Aquí pondremos “logros”, “recomendaciones”, y comentarios del docente.\n'
                      'Luego lo conectamos a una subcolección: observaciones.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
