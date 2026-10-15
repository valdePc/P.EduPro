import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:typed_data';

import 'package:edupro/chat/utils/chat_grade_subject.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ChatGradoScreen extends StatefulWidget {
  final Escuela escuela;

  /// Opcional: si quieres forzar un alumno específico desde otra pantalla.
  final String? initialAlumnoId;

  const ChatGradoScreen({
    super.key,
    required this.escuela,
    this.initialAlumnoId,
  });

  @override
  State<ChatGradoScreen> createState() => _ChatGradoScreenState();
}

class _ChatGradoScreenState extends State<ChatGradoScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  static const String _root = 'schools';

  late final String _schoolId;
  String? _emailLower;

  // alumnos_login
  DocumentReference<Map<String, dynamic>>? _loginRef;

  // selección
  String? _selectedAlumnoId;
  String? _gradeId;
  String _gradeName = 'Chat del grado';
  String? _subjectId;
  String _subjectName = '';
  List<_ChatSubjectItem> _subjects = const [];

  String? _err;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
  final raw = normalizeSchoolIdFromEscuela(widget.escuela);
_schoolId = raw.trim();
    _bootstrap();
  }


  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

void _dlog(String msg) {
  if (!kDebugMode) return;
  debugPrint('[CHAT_GRADO] $msg');
}

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final u = _auth.currentUser;
      if (u == null) {
        setState(() {
          _err = 'No hay sesión activa.';
          _loading = false;
        });
        return;
      }

      final email = (u.email ?? '').trim().toLowerCase();
      if (email.isEmpty) {
        setState(() {
          _err = 'Tu sesión no tiene email. No puedo resolver alumnos_login.';
          _loading = false;
        });
        return;
      }

      _emailLower = email;
      _loginRef = _db.collection(_root).doc(_schoolId).collection('alumnos_login').doc(email);

      // 1) cargar alumnos_login
      final loginSnap = await _loginRef!.get();
      if (!loginSnap.exists) {
        setState(() {
          _err = 'No existe alumnos_login para $email en esta escuela.';
          _loading = false;
        });
        return;
      }

      final login = loginSnap.data() ?? {};

      

      _dlog('--- LOGIN SNAP ---');
_dlog('login keys: ${login.keys.toList()}');
_dlog('login.active: ${login['active']}  login.enabled: ${login['enabled']}  login.schoolId: ${login['schoolId']}');
_dlog('login.selectedAlumnoId(raw): ${login['selectedAlumnoId']}');
_dlog('login.studentIds(raw): ${login['studentIds']}');
_dlog('-------------------');

      // 2) decidir alumnoId efectivo
// 2) decidir alumnoId efectivo
final forced = (widget.initialAlumnoId ?? '').trim();
final selectedFromDoc = (login['selectedAlumnoId'] ?? '').toString().trim();

final studentIds = (login['studentIds'] is List)
    ? (login['studentIds'] as List)
        .map((e) => e.toString().trim())
        .where((x) => x.isNotEmpty)
        .toList()
    : <String>[];

// ✅ Solo aceptar selectedFromDoc si pertenece a studentIds
final selectedValid = selectedFromDoc.isNotEmpty && studentIds.contains(selectedFromDoc);

// Logs claves (estos son los que necesito ver)
_dlog('LOGIN selectedAlumnoId: "$selectedFromDoc"');
_dlog('LOGIN studentIds: $studentIds');
_dlog('LOGIN contains(selected): ${studentIds.contains(selectedFromDoc)}');

String effectiveAlumnoId = '';

if (forced.isNotEmpty && studentIds.contains(forced)) {
  effectiveAlumnoId = forced;
} else if (selectedValid) {
  effectiveAlumnoId = selectedFromDoc;
} else if (studentIds.length == 1) {
  effectiveAlumnoId = studentIds.first;
} else if (studentIds.isNotEmpty) {
  final picked = await _pickAlumnoDialog(studentIds);
  if (picked == null || picked.trim().isEmpty) {
    setState(() {
      _err = 'Debes seleccionar un alumno para abrir el chat.';
      _loading = false;
    });
    return;
  }
  effectiveAlumnoId = picked.trim();

  await _loginRef!.update({
    'selectedAlumnoId': effectiveAlumnoId,
    'updatedAt': FieldValue.serverTimestamp(),
  });
} else {
  setState(() {
    _err = 'No se pudo resolver un alumno (studentIds vacío).';
    _loading = false;
  });
  return;
}

// ✅ Si había selectedAlumnoId inválido, lo limpiamos para no quedar “enganchados”
if (selectedFromDoc.isNotEmpty && !selectedValid) {
  await _loginRef!.update({
    'selectedAlumnoId': '',
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

_selectedAlumnoId = effectiveAlumnoId;

// ✅ SIEMPRE persistir selectedAlumnoId para que las reglas lo vean
try {
  await _loginRef!.update({
    'selectedAlumnoId': effectiveAlumnoId,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  _dlog('selectedAlumnoId fijado en alumnos_login: $effectiveAlumnoId');
} catch (e) {
  _dlog('ERROR fijando selectedAlumnoId: $e');
}

_dlog('studentIds.contains(effective): ${studentIds.contains(effectiveAlumnoId)}');

      _dlog('--- ALUMNO EFECTIVO ---');
_dlog('forced: "$forced"  selectedFromDoc: "$selectedFromDoc"');
_dlog('studentIds.len: ${studentIds.length}');
_dlog('effectiveAlumnoId: "$effectiveAlumnoId"');
_dlog('studentIds.contains(effective): ${studentIds.contains(effectiveAlumnoId)}');
_dlog('-----------------------');

      // 3) leer alumno para sacar gradeId
      final alumnoRef = _db.collection(_root).doc(_schoolId).collection('alumnos').doc(effectiveAlumnoId);
      final alumnoSnap = await alumnoRef.get();
      if (!alumnoSnap.exists) {
        setState(() {
          _err = 'El alumno seleccionado no existe en alumnos/$effectiveAlumnoId.';
          _loading = false;
        });
        return;
      }

      final alumno = alumnoSnap.data() ?? {};
      _dlog('--- ALUMNO DOC ---');
_dlog('alumnoId: $effectiveAlumnoId');
_dlog('alumno.active: ${alumno['active']}  alumno.enabled: ${alumno['enabled']}');
_dlog('alumno.gradeId: ${alumno['gradeId']}  alumno.gradoKey: ${alumno['gradoKey']}');
_dlog('------------------');
      final gradeId = (alumno['gradeId'] ?? '').toString().trim();
      if (gradeId.isEmpty) {
        setState(() {
          _err = 'El alumno no tiene gradeId. No se puede abrir chat por grado.';
          _loading = false;
        });
        return;
      }

      _gradeId = gradeId;
      _subjects = await _loadSubjectsForGrade(gradeId);
      if (_subjects.isEmpty) {
        setState(() {
          _err =
              'No hay asignaturas configuradas para este grado. No se puede abrir el chat por asignatura.';
          _loading = false;
        });
        return;
      }
      _subjectId = _subjects.first.id;
      _subjectName = _subjects.first.name;

      _dlog('--- CHAT CONTEXTO FINAL ---');
_dlog('auth.uid: ${_auth.currentUser?.uid}');
_dlog('auth.email: ${_auth.currentUser?.email}');
_dlog('_schoolId: $_schoolId');
_dlog('_loginRef.path: ${_loginRef?.path}');
_dlog('_selectedAlumnoId: $_selectedAlumnoId');
_dlog('_gradeId: $_gradeId');
_dlog('_subjectId: $_subjectId');
_dlog('_threadRef.path: ${_threadRef.path}');
_dlog('_msgsCol.path: ${_msgsCol.path}');
_dlog('---------------------------');
      // 4) (opcional) nombre del grado desde /grados/{gradeId}
      try {
        final gradoRef = _db.collection(_root).doc(_schoolId).collection('grados').doc(gradeId);
        final gradoSnap = await gradoRef.get();
        final g = gradoSnap.data() ?? {};
        final name = (g['name'] ?? g['gradoName'] ?? '').toString().trim();
        _gradeName = name.isEmpty ? 'Chat del grado' : name;
      } catch (_) {
        // si falla, no bloqueamos
        _gradeName = 'Chat del grado';
      }

assert(() {
  return true;
}());

try {
  final tid = _auth.currentUser?.uid ?? '';
  final tSnap = await _db
      .collection(_root)
      .doc(_schoolId)
      .collection('teachers_uid')
      .doc(tid)
      .get();
  _dlog('teachers_uid/$tid exists: ${tSnap.exists}');
  if (tSnap.exists) _dlog('teachers_uid data keys: ${(tSnap.data() ?? {}).keys.toList()}');
} catch (e) {
  _dlog('teachers_uid check error: $e');
}
      setState(() => _loading = false);
    } on FirebaseException catch (e) {
      _dlog('ERROR bootstrap FirebaseException code=${e.code} message=${e.message}');
      setState(() {
        _err = 'Error inicializando chat: ${e.code}';
        _loading = false;
      });
    } catch (e) {
      _dlog('ERROR bootstrap generic: $e');
      setState(() {
        _err = 'Error inicializando chat: $e';
        _loading = false;
      });
    }
  }


  Future<String?> _pickAlumnoDialog(List<String> alumnoIds) async {
    // intenta traer nombres de alumnos para mostrar bonito
    final items = <_AlumnoPickItem>[];
    for (final id in alumnoIds.take(30)) {
      try {
        final snap = await _db.collection(_root).doc(_schoolId).collection('alumnos').doc(id).get();
        final d = snap.data() ?? {};
        final name = (d['name'] ?? d['nombre'] ?? d['displayName'] ?? '').toString().trim();
        items.add(_AlumnoPickItem(id: id, name: name.isEmpty ? id : name));
      } catch (_) {
        items.add(_AlumnoPickItem(id: id, name: id));
      }
    }

    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Selecciona el alumno'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                return ListTile(
                  title: Text(it.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(it.id, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, it.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  String _normText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _subjectMatchesGrade(Map<String, dynamic> data, String gradeId) {
    final ids = <String>{};
    for (final key in const [
      'gradeIds',
      'gradesIds',
      'gradoIds',
      'gradosIds',
      'gradeKeys',
      'gradoKeys',
      'gradosKeys',
    ]) {
      final raw = data[key];
      if (raw is List) {
        for (final e in raw) {
          final v = e.toString().trim();
          if (v.isNotEmpty) ids.add(v);
        }
      }
    }

    if (ids.isEmpty) return true;
    return ids.contains(gradeId);
  }

  Future<List<_ChatSubjectItem>> _loadSubjectsForGrade(String gradeId) async {
    final itemsById = <String, _ChatSubjectItem>{};

    for (final col in const ['subjects', 'asignaturas', 'materias']) {
      try {
        final snap = await _db.collection(_root).doc(_schoolId).collection(col).get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (!_subjectMatchesGrade(data, gradeId)) continue;

          final name = (data['name'] ?? data['nombre'] ?? data['title'] ?? doc.id)
              .toString()
              .trim();
          if (name.isEmpty) continue;

          itemsById[doc.id] = _ChatSubjectItem(id: doc.id, name: name);
        }
      } catch (_) {
        // Best-effort: una colección faltante no debe romper las demás.
      }
    }

    final items = itemsById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection(_root)
      .doc(_schoolId)
      .collection('chat_grados')
      .doc(_threadId);

  CollectionReference<Map<String, dynamic>> get _msgsCol => _threadRef.collection('mensajes');

  String get _threadId =>
      buildChatGradeSubjectThreadId(_gradeId ?? '', _subjectId ?? '');

  @override
  Widget build(BuildContext context) {
    final schoolName = (widget.escuela.nombre ?? 'Escuela').toString().trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(
          _loading
              ? 'Chat • $schoolName'
              : (_subjectName.isEmpty
                  ? '$_gradeName • $schoolName'
                  : '$_gradeName • $_subjectName • $schoolName'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_err != null)
              ? _ErrorBox(message: _err!, onRetry: _bootstrap)
              : (_gradeId == null || _subjectId == null)
                  ? _ErrorBox(
                      message: 'No hay grado o asignatura resueltos.',
                      onRetry: _bootstrap,
                    )
                  : Column(
                      children: [
                        _SubjectSelectorCard(
                          subjects: _subjects,
                          selectedSubjectId: _subjectId!,
                          onSelect: (subject) {
                            setState(() {
                              _subjectId = subject.id;
                              _subjectName = subject.name;
                            });
                          },
                        ),
                        Expanded(
                          child: _ChatBody(
                            msgsStream: _msgsCol
                                .orderBy('createdAt', descending: true)
                                .limit(80)
                                .snapshots(),
                            onSend: _sendMessage,
                            onSendImage: _sendImageMessage,
                            onSendFile: _sendFileMessage,
                            myUid: _auth.currentUser?.uid ?? '',
                            orange: _orange,
                            blue: _blue,
                          ),
                        ),
                      ],
                    ),
    );
  }

Future<void> _sendMessage(String text) async {
  final t = text.trim();
  if (t.isEmpty) return;

  final uid = _auth.currentUser?.uid ?? '';
  if (uid.isEmpty) throw Exception('UID vacío.');

  final senderName = 'Alumno';
  final senderRole = 'student';

try {
  // ✅ refresca token (evita denegaciones raras por claims desactualizados)
  await _auth.currentUser?.getIdToken(true);

  await _ensureThreadExistsOnFirstMessage(
    lastText: t,
    senderUid: uid,
    senderName: senderName,
    senderRole: senderRole,
  );
} catch (e) {
  rethrow;
}

 try {

  _dlog('Creando mensaje texto en: ${_msgsCol.path}');
  await _msgsCol.add({
    'text': t,
    'senderUid': uid,
    'senderRole': senderRole, // para alumno debe ser: "student"
    'senderName': senderName,
    'createdAt': FieldValue.serverTimestamp(),
  });

} on FirebaseException catch (e) {
  _dlog('ERROR add mensaje texto code=${e.code} message=${e.message} path=${_msgsCol.path}');
  rethrow;
} catch (e) {
  _dlog('ERROR add mensaje texto generic: $e');
  rethrow;
}

  try {
    // ✅ tus reglas no permiten update del thread por alumnos
if (senderRole == 'student') return;
    await _updateThreadMeta(
      lastText: t,
      senderUid: uid,
      senderName: senderName,
      senderRole: senderRole,
    );
  } catch (e) {
    rethrow;
  }
}

String _safeFileName(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

Future<void> _sendImageMessage() async {
  final picked = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
  );
  if (picked == null) return;
  final bytes = await picked.readAsBytes();
  final name = _safeFileName(picked.name.isEmpty ? 'imagen.jpg' : picked.name);
  final ext = name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
  await _sendMediaMessage(
    type: 'image',
    bytes: bytes,
    fileName: name,
    mimeType: mime,
    summaryText: 'Imagen',
  );
}

Future<void> _sendFileMessage() async {
  final result = await FilePicker.platform.pickFiles(withData: true);
  if (result == null || result.files.isEmpty) return;
  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null) throw Exception('No se pudo leer el archivo seleccionado.');
  final name = _safeFileName(file.name);
  final ext = (file.extension ?? '').trim().toLowerCase();
  final mime = ext == 'pdf'
      ? 'application/pdf'
      : (ext == 'doc'
          ? 'application/msword'
          : (ext == 'docx'
              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
              : 'application/octet-stream'));
  await _sendMediaMessage(
    type: 'file',
    bytes: bytes,
    fileName: name,
    mimeType: mime,
    summaryText: 'Archivo: $name',
  );
}

Future<void> _sendMediaMessage({
  required String type,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String summaryText,
}) async {
  final uid = _auth.currentUser?.uid ?? '';
  if (uid.isEmpty) throw Exception('UID vacío.');

  final senderName = 'Alumno';
  final senderRole = 'student';

  await _auth.currentUser?.getIdToken(true);

  final filePath =
      'schools/$_schoolId/chat_uploads/chat_grados/${_threadId.isEmpty ? (_gradeId ?? 'grado') : _threadId}/$uid/${DateTime.now().millisecondsSinceEpoch}_$fileName';
  final ref = _storage.ref().child(filePath);
  _dlog('Subiendo media a Storage: $filePath');
  await ref.putData(
    bytes,
    SettableMetadata(
      contentType: mimeType,
      customMetadata: {'senderUid': uid, 'threadId': _threadId, 'type': type},
    ),
  );
  final mediaUrl = await ref.getDownloadURL();

  await _ensureThreadExistsOnFirstMessage(
    lastText: summaryText,
    senderUid: uid,
    senderName: senderName,
    senderRole: senderRole,
  );

  _dlog('Creando mensaje media en: ${_msgsCol.path}');
  await _msgsCol.add({
    'type': type,
    'text': '',
    'senderUid': uid,
    'senderRole': senderRole,
    'senderName': senderName,
    'mediaUrl': mediaUrl,
    'fileName': fileName,
    'fileSize': bytes.length,
    'mimeType': mimeType,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
Future<void> _ensureThreadExistsOnFirstMessage({
  required String lastText,
  required String senderUid,
  required String senderName,
  required String senderRole,
}) async {
  _dlog('Leyendo thread: ${_threadRef.path}');
  final snap = await _threadRef.get();
  if (snap.exists) return;

  final now = FieldValue.serverTimestamp();

  _dlog('Creando thread: ${_threadRef.path}');
  await _threadRef.set({
    'gradeId': _gradeId,
    'gradeName': _gradeName,
    'subjectId': _subjectId,
    'subjectName': _subjectName.isEmpty ? _subjectId : _subjectName,
    'createdAt': now,
    'updatedAt': now,
    'lastMessage': lastText,
    'lastSenderUid': senderUid,
    'lastSenderName': senderName,
    'lastSenderRole': senderRole,
  }, SetOptions(merge: false));
}

Future<void> _updateThreadMeta({
  required String lastText,
  required String senderUid,
  required String senderName,
  required String senderRole,
}) async {
  await _threadRef.set({
    'updatedAt': FieldValue.serverTimestamp(),
    'lastMessage': lastText,
    'lastSenderUid': senderUid,
    'lastSenderName': senderName,
    'lastSenderRole': senderRole,
  }, SetOptions(merge: true));
}
} 

class _ChatSubjectItem {
  final String id;
  final String name;

  const _ChatSubjectItem({
    required this.id,
    required this.name,
  });
}

class _AlumnoPickItem {
  final String id;
  final String name;
  _AlumnoPickItem({required this.id, required this.name});
}

class _SubjectSelectorCard extends StatelessWidget {
  final List<_ChatSubjectItem> subjects;
  final String selectedSubjectId;
  final ValueChanged<_ChatSubjectItem> onSelect;

  const _SubjectSelectorCard({
    required this.subjects,
    required this.selectedSubjectId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selecciona la asignatura',
            style: TextStyle(
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: subjects.map((subject) {
              final selected = subject.id == selectedSubjectId;
              return ChoiceChip(
                label: Text(subject.name),
                selected: selected,
                onSelected: (_) => onSelect(subject),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBody extends StatefulWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> msgsStream;
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onSendImage;
  final Future<void> Function() onSendFile;
  final String myUid;
  final Color blue;
  final Color orange;

  const _ChatBody({
    required this.msgsStream,
    required this.onSend,
    required this.onSendImage,
    required this.onSendFile,
    required this.myUid,
    required this.blue,
    required this.orange,
  });

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;

    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _ctrl.clear();
    } catch (e) {
      if (e is FirebaseException) {
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSendImage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando imagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFile() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSendFile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando archivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = safeExternalDocumentUri(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  double _bubbleMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 600 ? width * 0.72 : 360;
  }

  double _imagePreviewSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 600 ? width * 0.46 : 240;
  }

  Widget _messageContent(BuildContext context, Map<String, dynamic> d, bool isMe, Color textColor) {
    final type = (d['type'] ?? 'text').toString().trim().toLowerCase();
    final text = (d['text'] ?? '').toString();
    final mediaUrl = (d['mediaUrl'] ?? '').toString().trim();
    final fileName = (d['fileName'] ?? '').toString().trim();
    final imageSize = _imagePreviewSize(context);

    if (type == 'image' && mediaUrl.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUrl(mediaUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                mediaUrl,
                semanticLabel: fileName.isEmpty ? 'Imagen adjunta' : 'Imagen adjunta: $fileName',
                width: imageSize,
                height: imageSize,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: imageSize,
                    height: imageSize,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : widget.orange,
                    ),
                  );
                },
                errorBuilder: (_, error, stackTrace) {
                  debugPrint('[CHAT_GRADO][IMG_ERROR] No se pudo cargar la imagen.');
                  return Container(
                    width: imageSize,
                    height: imageSize,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image_outlined),
                        const SizedBox(height: 8),
                        Text(
                          'No se pudo cargar',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (fileName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              fileName,
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    }

    if (type == 'file' && mediaUrl.isNotEmpty) {
      return InkWell(
        onTap: () => _openUrl(mediaUrl),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file_rounded, color: isMe ? Colors.white : widget.orange),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  fileName.isEmpty ? 'Archivo adjunto' : fileName,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Text(text, style: TextStyle(color: textColor));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.msgsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                debugPrint('[CHAT_GRADO][STREAM_ERROR] No se pudieron cargar los mensajes.');
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No hay mensajes aún.'));

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final text = (d['text'] ?? '').toString();
                  final name = (d['senderName'] ?? '').toString();
                  final uid = (d['senderUid'] ?? '').toString();

                  final isMe = uid.isNotEmpty && uid == widget.myUid;
                  final bubbleColor = isMe ? widget.blue : Colors.white;
                  final textColor = isMe ? Colors.white : Colors.black87;
                  final align = isMe ? Alignment.centerRight : Alignment.centerLeft;

                  return Align(
                    alignment: align,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      constraints: BoxConstraints(maxWidth: _bubbleMaxWidth(context)),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe && name.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: widget.orange,
                                ),
                              ),
                            ),
                          _messageContent(context, d, isMe, textColor),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Adjuntar',
                  onSelected: (value) async {
                    if (value == 'image') {
                      await _sendImage();
                    } else if (value == 'file') {
                      await _sendFile();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'image',
                      child: ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Imagen'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'file',
                      child: ListTile(
                        leading: Icon(Icons.attach_file_rounded),
                        title: Text('Archivo'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Icon(Icons.add_rounded, color: widget.blue),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.zero,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
