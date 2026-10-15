import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';

class DocumentosTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const DocumentosTab({
    super.key,
    required this.estRef,
  });

  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

  String get _schoolId => estRef.parent.parent!.id;

  DateTime _readDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _openUrl(String raw) async {
    final uri = safeExternalDocumentUri(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: estRef.snapshots(),
      builder: (context, studentSnap) {
        if (studentSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _StateCard(
                icon: Icons.error_outline_rounded,
                title: 'No se pudo cargar el perfil',
                subtitle: '${studentSnap.error}',
              ),
            ),
          );
        }
        if (!studentSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final student = studentSnap.data!.data() ?? const <String, dynamic>{};
        final gradeId = _readString(student, const [
          'gradoId',
          'gradeId',
          'gradoDocId',
          'gradoKey',
        ]);
        final gradeName = _readString(student, const [
          'gradoName',
          'gradeName',
          'grado',
          'grade',
        ]);

        if (gradeId.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: _StateCard(
                icon: Icons.rule_folder_outlined,
                title: 'No hay grado asignado',
                subtitle:
                    'Este alumno no tiene gradeId o gradoId configurado. No se puede filtrar el material correspondiente.',
              ),
            ),
          );
        }

        final resourcesStream = FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('material_apoyo_docente')
            .where('visibleToStudents', isEqualTo: true)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: resourcesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _StateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'No se pudo cargar el material',
                    subtitle: '${snapshot.error}',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final gradeIds = (data['gradeIds'] is Iterable)
                  ? (data['gradeIds'] as Iterable)
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList()
                  : const <String>[];
              return gradeIds.contains(gradeId);
            }).toList()
              ..sort(
                (a, b) => _readDate(b.data()['updatedAt'] ?? b.data()['createdAt'])
                    .compareTo(
                      _readDate(a.data()['updatedAt'] ?? a.data()['createdAt']),
                    ),
              );

            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _StateCard(
                    icon: Icons.folder_copy_outlined,
                    title: 'Sin recursos disponibles',
                    subtitle:
                        'No hay material de apoyo visible para ${gradeName.isEmpty ? 'tu grado' : gradeName}.',
                  ),
                ),
              );
            }

            final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
            for (final doc in docs) {
              final data = doc.data();
              final subject = (data['subjectName'] ?? data['subjectId'] ?? 'General')
                  .toString()
                  .trim();
              final key = subject.isEmpty ? 'General' : subject;
              grouped.putIfAbsent(key, () => []);
              grouped[key]!.add(doc);
            }

            final subjects = grouped.keys.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0x14FFA000),
                            child: Icon(Icons.folder_open_rounded, color: _orange),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Material de apoyo',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Recursos compartidos por tus docentes para estudiar, consultar o descargar.',
                                  style: TextStyle(height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaPill(
                            icon: Icons.school_rounded,
                            label: gradeName.isEmpty ? gradeId : gradeName,
                          ),
                          _MetaPill(
                            icon: Icons.layers_rounded,
                            label: '${docs.length} recurso${docs.length == 1 ? '' : 's'}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ...subjects.map(
                  (subject) => _SubjectSection(
                    subject: subject,
                    docs: grouped[subject]!,
                    readDate: _readDate,
                    openUrl: _openUrl,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: DocumentosTab._blue),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SubjectSection extends StatelessWidget {
  final String subject;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final DateTime Function(dynamic) readDate;
  final Future<void> Function(String) openUrl;

  const _SubjectSection({
    required this.subject,
    required this.docs,
    required this.readDate,
    required this.openUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${docs.length} recurso${docs.length == 1 ? '' : 's'} disponible${docs.length == 1 ? '' : 's'}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          ...docs.map(
            (doc) => _ResourceTile(
              data: doc.data(),
              date: readDate(doc.data()['updatedAt'] ?? doc.data()['createdAt']),
              openUrl: openUrl,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime date;
  final Future<void> Function(String) openUrl;

  const _ResourceTile({
    required this.data,
    required this.date,
    required this.openUrl,
  });

  @override
  Widget build(BuildContext context) {
    final type = (data['type'] ?? 'link').toString();
    final title = (data['title'] ?? 'Recurso').toString();
    final description = (data['description'] ?? '').toString().trim();
    final url = (data['url'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? '').toString().trim();

    final icon = switch (type) {
      'file' => Icons.attach_file_rounded,
      'note' => Icons.sticky_note_2_rounded,
      _ => Icons.link_rounded,
    };
    final tag = switch (type) {
      'file' => 'Archivo',
      'note' => 'Nota',
      _ => 'Enlace',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tag == 'Archivo'
                      ? const Color(0x14FFA000)
                      : const Color(0x140D47A1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: tag == 'Archivo'
                          ? DocumentosTab._orange
                          : DocumentosTab._blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tag,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tag == 'Archivo'
                            ? DocumentosTab._orange
                            : DocumentosTab._blue,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${date.day}/${date.month}/${date.year}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
          ],
          if (type == 'note' && description.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Este recurso no tiene contenido adicional.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
          if (type != 'note' && url.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => openUrl(url),
              icon: Icon(
                type == 'file' ? Icons.download_rounded : Icons.open_in_new_rounded,
              ),
              label: Text(
                type == 'file'
                    ? (fileName.isEmpty ? 'Descargar archivo' : fileName)
                    : 'Abrir enlace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.grey.shade700),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
        ],
      ),
    );
  }
}
