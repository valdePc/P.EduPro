import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AlumnoCommon {
  static String s(dynamic v) => (v ?? '').toString().trim();

  static DateTime? toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static int? calcularEdad(DateTime? dob) {
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthdayThisYear =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age--;
    if (age < 0 || age > 120) return null;
    return age;
  }

  static String fmtDate(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class AlumnoHeader extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  final String fallbackNombre;
  final String fallbackGrado;
  final VoidCallback onMensajes;
  final VoidCallback onAvisos;

  /// Config escuela:
  /// escuelas/{schoolId}/config/alumnos  => allowStudentPhoto: true/false
  final DocumentReference<Map<String, dynamic>> configRef;

  const AlumnoHeader({
    super.key,
    required this.estRef,
    required this.configRef,
    required this.fallbackNombre,
    required this.fallbackGrado,
    required this.onMensajes,
    required this.onAvisos,
  });

  Future<void> _cambiarFotoUrl(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Foto de perfil'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Pega un link (URL) de la foto',
            hintText: 'https://...',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true) {
      await estRef.set({'fotoUrl': ctrl.text.trim()}, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto actualizada')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final azul = Colors.blue.shade900;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: estRef.snapshots(),
      builder: (context, estSnap) {
        final data = estSnap.data?.data() ?? {};

        final nombre = (AlumnoCommon.s(data['nombre']) + ' ' + AlumnoCommon.s(data['apellido']))
            .trim();
        final nombreShow = nombre.isNotEmpty ? nombre : fallbackNombre;

        final grado = AlumnoCommon.s(data['grado']);
        final gradoShow = grado.isNotEmpty ? grado : fallbackGrado;

        final dob = AlumnoCommon.toDate(data['fechaNacimiento']);
        final edad = AlumnoCommon.calcularEdad(dob);

        final matricula = AlumnoCommon.s(data['matricula']);
        final seccion = AlumnoCommon.s(data['seccion']);
        final tanda = AlumnoCommon.s(data['tanda']);
        final idGlobal = AlumnoCommon.s(data['idGlobal']);

        final fotoUrl = AlumnoCommon.s(data['fotoUrl']);
        final fotoBloqueada = (data['fotoBloqueada'] == true);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: configRef.snapshots(),
          builder: (context, cfgSnap) {
            final cfg = cfgSnap.data?.data() ?? {};
            final allowStudentPhoto = (cfg['allowStudentPhoto'] != false); // default true
            final canEditPhoto = allowStudentPhoto && !fotoBloqueada;

            return Container(
              padding: const  EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(colors: [azul, Colors.blue.shade700]),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.white,
                            backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
                            child: fotoUrl.isEmpty
                                ? Icon(Icons.person, size: 34, color: Colors.grey.shade700)
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Material(
                              color: canEditPhoto ? Colors.orange : Colors.grey,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: canEditPhoto
                                    ? () => _cambiarFotoUrl(context, fotoUrl)
                                    : () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              allowStudentPhoto
                                                  ? 'La escuela bloqueó tu foto'
                                                  : 'La escuela desactivó fotos para estudiantes',
                                            ),
                                          ),
                                        );
                                      },
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombreShow,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              gradoShow,
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _pill('Matrícula: ${matricula.isEmpty ? '—' : matricula}'),
                                _pill('Sección: ${seccion.isEmpty ? '—' : seccion}'),
                                _pill('Tanda: ${tanda.isEmpty ? '—' : tanda}'),
                                _pill('ID: ${idGlobal.isEmpty ? '—' : idGlobal}'),
                                _pill('Nac: ${AlumnoCommon.fmtDate(dob)}'),
                                _pill('Edad: ${edad?.toString() ?? '—'}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          IconButton(
                            tooltip: 'Mensajes',
                            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                            onPressed: onMensajes,
                          ),
                          IconButton(
                            tooltip: 'Avisos',
                            icon: const Icon(Icons.campaign_outlined, color: Colors.white),
                            onPressed: onAvisos,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _pill(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class MiniCounter extends StatelessWidget {
  final String label;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  const MiniCounter({super.key, required this.label, required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
        );
      },
    );
  }
}

class NiceCard extends StatelessWidget {
  final String title;
  final Widget child;
  const NiceCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String msg;
  const ErrorBox(this.msg, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(msg, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
    );
  }
}

class EmptyBox extends StatelessWidget {
  final String msg;
  const EmptyBox(this.msg, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 64),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
