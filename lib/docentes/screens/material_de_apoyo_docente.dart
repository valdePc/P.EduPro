import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';

import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart';

class MaterialDeApoyoDocenteScreen extends StatefulWidget {
  final Escuela escuela;

  const MaterialDeApoyoDocenteScreen({
    super.key,
    required this.escuela,
  });

  @override
  State<MaterialDeApoyoDocenteScreen> createState() =>
      _MaterialDeApoyoDocenteScreenState();
}

class _MaterialDeApoyoDocenteScreenState
    extends State<MaterialDeApoyoDocenteScreen> {
  static const Color _bg = Color(0xFFF3F5FB);
  static const Color _card = Colors.white;
  static const Color _blue = Color(0xFF0D47A1);
  static const Color _blue2 = Color(0xFF1E5BC6);
  static const Color _orange = Color(0xFFFFA000);

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  late final String _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _teacherDocId = '';
  List<_SupportSubject> _subjects = const [];
  List<_SupportGrade> _grades = const [];

  CollectionReference<Map<String, dynamic>> get _resourcesCol => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('material_apoyo_docente');

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  List<String> _asList(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _norm(String value) {
    final input = value.trim().toLowerCase();
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var out = input;
    accents.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    out = out.replaceAll(RegExp(r'_+'), '_');
    return out.replaceAll(RegExp(r'^_|_$'), '');
  }

  DateTime _readDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _safeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'archivo' : cleaned;
  }

  String _inferMimeType(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.doc')) return 'application/msword';
    if (name.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (name.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (name.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (name.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (name.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('No hay una sesión activa.');
      }

      final uidSnap = await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('teachers_uid')
          .doc(uid)
          .get();
      final memSnap = await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('members')
          .doc(uid)
          .get();

      final teacherDocId = (uidSnap.data()?['teacherDocId'] ??
              memSnap.data()?['teacherDocId'] ??
              '')
          .toString()
          .trim();
      if (teacherDocId.isEmpty) {
        throw Exception('No se encontró el docente vinculado a esta escuela.');
      }

      final teacherSnap = await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('teachers')
          .doc(teacherDocId)
          .get();
      final teacher = teacherSnap.data() ?? <String, dynamic>{};

      final subjectIds = <String>{
        ..._asList(teacher['subjectIds']),
        ..._asList(teacher['subjectsIds']),
        ..._asList(teacher['asignaturaIds']),
        ..._asList(teacher['asignaturasIds']),
        ..._asList(teacher['materiaIds']),
        ..._asList(teacher['materiasIds']),
      };

      final subjectLabels = <String>{
        ..._asList(teacher['subjects']),
        ..._asList(teacher['asignaturas']),
        ..._asList(teacher['materias']),
      };
      final gradeIds = <String>{
        ..._asList(teacher['gradeIds']),
        ..._asList(teacher['gradoIds']),
        ..._asList(teacher['gradosIds']),
        ..._asList(teacher['gradesIds']),
        ..._asList(teacher['gradoKeys']),
        ..._asList(teacher['gradosKeys']),
      };

      final catalog = <String, String>{};
      for (final col in const ['subjects', 'asignaturas', 'materias']) {
        final snap = await _db
            .collection('schools')
            .doc(_schoolId)
            .collection(col)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final label = (data['name'] ??
                  data['nombre'] ??
                  data['title'] ??
                  data['titulo'] ??
                  doc.id)
              .toString()
              .trim();
          if (label.isNotEmpty) {
            catalog[doc.id] = label;
            catalog.putIfAbsent(_norm(label), () => label);
          }
        }
      }
      final gradeCatalog = <String, String>{};
      final gradeSnap = await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('grados')
          .get();
      for (final doc in gradeSnap.docs) {
        final data = doc.data();
        final label = (data['name'] ??
                data['grado'] ??
                data['gradeName'] ??
                data['gradoName'] ??
                doc.id)
            .toString()
            .trim();
        if (label.isNotEmpty) {
          gradeCatalog[doc.id] = label;
          gradeCatalog.putIfAbsent(_norm(label), () => label);
        }
      }

      final subjects = <_SupportSubject>[];
      for (final id in subjectIds) {
        final label = catalog[id] ?? catalog[_norm(id)] ?? id;
        subjects.add(_SupportSubject(id: id, label: label));
      }

      for (final label in subjectLabels) {
        final normalized = _norm(label);
        final match = catalog.entries
            .where((e) => _norm(e.value) == normalized)
            .map((e) => e.key)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
        subjects.add(_SupportSubject(id: match ?? normalized, label: label));
      }

      final merged = <String, _SupportSubject>{};
      for (final s in subjects) {
        merged[s.id] = s;
      }
      final finalSubjects = merged.values.toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      final grades = <_SupportGrade>[];
      for (final id in gradeIds) {
        final label = gradeCatalog[id] ?? gradeCatalog[_norm(id)] ?? id;
        grades.add(_SupportGrade(id: id, label: label));
      }
      final gradeMerged = <String, _SupportGrade>{};
      for (final g in grades) {
        gradeMerged[g.id] = g;
      }
      final finalGrades = gradeMerged.values.toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _teacherDocId = teacherDocId;
        _subjects = finalSubjects;
        _grades = finalGrades;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openUri(String raw) async {
    final uri = safeExternalDocumentUri(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _deleteResource(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final storagePath = (data['storagePath'] ?? '').toString().trim();
    try {
      if (storagePath.isNotEmpty) {
        await _storage.ref(storagePath).delete();
      }
    } catch (_) {}
    await doc.reference.delete();
  }

  Future<void> _createResource({
    required _SupportSubject subject,
    required String type,
    required String title,
    required String description,
    required bool visibleToStudents,
    required List<_SupportGrade> selectedGrades,
    String url = '',
    PlatformFile? pickedFile,
  }) async {
    setState(() => _saving = true);
    try {
      var mediaUrl = '';
      var storagePath = '';
      var fileName = '';
      var mimeType = '';
      var fileSize = 0;

      if (type == 'file') {
        if (pickedFile == null || pickedFile.bytes == null) {
          throw Exception('Selecciona un archivo antes de guardar.');
        }
        fileName = _safeFileName(pickedFile.name);
        mimeType = _inferMimeType(fileName);
        fileSize = pickedFile.size;
        storagePath =
            'schools/$_schoolId/material_apoyo/$_teacherDocId/${subject.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        final ref = _storage.ref(storagePath);
        await ref.putData(
          pickedFile.bytes!,
          SettableMetadata(contentType: mimeType),
        );
        mediaUrl = await ref.getDownloadURL();
      }

      await _resourcesCol.add({
        'schoolId': _schoolId,
        'teacherDocId': _teacherDocId,
        'createdByUid': _auth.currentUser?.uid,
        'subjectId': subject.id,
        'subjectName': subject.label,
        'title': title.trim(),
        'description': description.trim(),
        'type': type,
        'url': type == 'link' ? url.trim() : mediaUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'storagePath': storagePath,
        'visibleToStudents': visibleToStudents,
        'gradeIds': selectedGrades.map((g) => g.id).toList(),
        'gradeNames': selectedGrades.map((g) => g.label).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recurso guardado.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAddSheet(_SupportSubject subject) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var type = 'link';
    var visibleToStudents = true;
    PlatformFile? pickedFile;
    final selectedGradeIds = <String>{
      if (_grades.length == 1) _grades.first.id,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                withData: true,
                allowMultiple: false,
              );
              if (result == null || result.files.isEmpty) return;
              setModalState(() => pickedFile = result.files.single);
            }

            Future<void> save() async {
              final title = titleCtrl.text.trim();
              final description = descCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (title.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El título es obligatorio.')),
                );
                return;
              }
              if (type == 'link' && url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Debes colocar un enlace.')),
                );
                return;
              }
              if (type == 'file' && pickedFile == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Debes seleccionar un archivo.')),
                );
                return;
              }
              if (visibleToStudents && selectedGradeIds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Selecciona al menos un grado para compartir con estudiantes.',
                    ),
                  ),
                );
                return;
              }
              final selectedGrades = _grades
                  .where((g) => selectedGradeIds.contains(g.id))
                  .toList();

              Navigator.of(context).pop();
              await _createResource(
                subject: subject,
                type: type,
                title: title,
                description: description,
                visibleToStudents: visibleToStudents,
                selectedGrades: selectedGrades,
                url: url,
                pickedFile: pickedFile,
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nuevo recurso para ${subject.label}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _typeChip(
                            label: 'Enlace',
                            selected: type == 'link',
                            icon: Icons.link_rounded,
                            onTap: () => setModalState(() => type = 'link'),
                          ),
                          _typeChip(
                            label: 'Archivo',
                            selected: type == 'file',
                            icon: Icons.attach_file_rounded,
                            onTap: () => setModalState(() => type = 'file'),
                          ),
                          _typeChip(
                            label: 'Nota',
                            selected: type == 'note',
                            icon: Icons.sticky_note_2_rounded,
                            onTap: () => setModalState(() => type = 'note'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Título',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: type == 'note'
                              ? 'Contenido'
                              : 'Descripción breve',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (type == 'link') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: urlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Enlace',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (type == 'file') ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: pickFile,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: Text(
                            pickedFile == null
                                ? 'Seleccionar archivo'
                                : pickedFile!.name,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        value: visibleToStudents,
                        onChanged: (v) =>
                            setModalState(() => visibleToStudents = v),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Visible para estudiantes'),
                        subtitle: const Text(
                          'Si lo desactivas, queda como apoyo interno del docente.',
                        ),
                      ),
                      if (_grades.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Grados que verán este recurso',
                          style: TextStyle(
                            color: Colors.grey.shade900,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _grades.map((grade) {
                            final selected = selectedGradeIds.contains(grade.id);
                            return FilterChip(
                              label: Text(grade.label),
                              selected: selected,
                              onSelected: (value) {
                                setModalState(() {
                                  if (value) {
                                    selectedGradeIds.add(grade.id);
                                  } else {
                                    selectedGradeIds.remove(grade.id);
                                  }
                                });
                              },
                              selectedColor: const Color(0x14FFA000),
                              checkmarkColor: _orange,
                              side: BorderSide(
                                color: selected ? _orange : Colors.grey.shade300,
                              ),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: selected ? Colors.black : Colors.grey.shade800,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          visibleToStudents
                              ? 'Obligatorio si el recurso estará visible para estudiantes.'
                              : 'Opcional para recursos internos del docente.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: save,
                            style: FilledButton.styleFrom(
                              backgroundColor: _orange,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _typeChip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? _blue.withAlpha(26) : const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? _blue : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? _blue : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, _blue2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(36),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Material de apoyo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Organiza recursos por asignatura, publica enlaces y sube archivos para que tus estudiantes accedan desde un mismo lugar.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(224),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MiniInfoBox(
                      icon: Icons.menu_book_rounded,
                      text: '${_subjects.length} asignaturas',
                    ),
                    const _MiniInfoBox(
                      icon: Icons.link_rounded,
                      text: 'Enlaces, notas y archivos',
                    ),
                    const _MiniInfoBox(
                      icon: Icons.visibility_rounded,
                      text: 'Control de visibilidad',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resourceCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final type = (d['type'] ?? 'link').toString();
    final title = (d['title'] ?? '').toString();
    final description = (d['description'] ?? '').toString();
    final url = (d['url'] ?? '').toString();
    final fileName = (d['fileName'] ?? '').toString();
    final visible = d['visibleToStudents'] == true;
    final gradeNames = _asList(d['gradeNames']);
    final updatedAt = _readDate(d['updatedAt'] ?? d['createdAt']);

    final chipText = switch (type) {
      'file' => 'Archivo',
      'note' => 'Nota',
      _ => 'Enlace',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(chipText, _blue.withAlpha(26), _blue),
                        _pill(
                          visible ? 'Visible alumnos' : 'Solo docente',
                          visible ? Colors.green.withAlpha(30) : Colors.grey.shade200,
                          visible ? Colors.green.shade800 : Colors.grey.shade800,
                        ),
                        ...gradeNames.map(
                          (name) => _pill(
                            name,
                            const Color(0x14FFA000),
                            _orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${updatedAt.day}/${updatedAt.month}/${updatedAt.year}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'open' && url.isNotEmpty) {
                    await _openUri(url);
                  } else if (value == 'delete') {
                    await _deleteResource(doc);
                  }
                },
                itemBuilder: (context) => [
                  if (url.isNotEmpty)
                    const PopupMenuItem(
                      value: 'open',
                      child: Text('Abrir'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar'),
                  ),
                ],
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
          ],
          if (type == 'link' && url.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _openUri(url),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FD),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: _blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (type == 'file' && url.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _openUri(url),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, color: _orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fileName.isEmpty ? 'Abrir archivo' : fileName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _subjectSection(_SupportSubject subject) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _resourcesCol.where('subjectId', isEqualTo: subject.id).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs.toList() ?? const [];
        docs.sort(
          (a, b) => _readDate(b.data()['updatedAt'] ?? b.data()['createdAt'])
              .compareTo(_readDate(a.data()['updatedAt'] ?? a.data()['createdAt'])),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.label,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          docs.isEmpty
                              ? 'Todavía no hay material cargado en esta asignatura.'
                              : '${docs.length} recurso${docs.length == 1 ? '' : 's'} disponibles.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _showAddSheet(subject),
                    style: FilledButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (docs.isEmpty)
                const _EmptyBox(
                  title: 'Sin material todavía',
                  subtitle: 'Agrega el primer enlace, archivo o nota para esta asignatura.',
                )
              else
                ...docs.map(_resourceCard),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: buildDocenteBackAppBar(context),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _ErrorBox(
                        title: 'No se pudo cargar Material de apoyo',
                        subtitle: _error!,
                        onRetry: _loadContext,
                      ),
                    ),
                  )
                : _subjects.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _ErrorBox(
                            title: 'Sin asignaturas vinculadas',
                            subtitle:
                                'Este docente todavía no tiene asignaturas asignadas en la escuela. Primero asigna materias y luego vuelve a entrar.',
                            onRetry: _loadContext,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          _headerCard(),
                          const SizedBox(height: 18),
                          if (_saving)
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Guardando recurso. No cierres esta pantalla todavía.',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ..._subjects.map(_subjectSection),
                        ],
                      ),
      ),
    );
  }
}

class _SupportSubject {
  final String id;
  final String label;

  const _SupportSubject({
    required this.id,
    required this.label,
  });
}

class _SupportGrade {
  final String id;
  final String label;

  const _SupportGrade({
    required this.id,
    required this.label,
  });
}

class _ErrorBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyBox({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.inbox_outlined, size: 28),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _MiniInfoBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniInfoBox({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
