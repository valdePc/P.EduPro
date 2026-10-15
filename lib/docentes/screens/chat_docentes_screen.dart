// lib/docentes/screens/chat_docentes_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/chat/utils/chat_grade_subject.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ChatDocentesScreen extends StatefulWidget {
  final Escuela escuela;

  /// Opcional: si luego tienes el nombre real del docente logueado.
  final String? docenteNombre;

  const ChatDocentesScreen({
    super.key,
    required this.escuela,
    this.docenteNombre,
  });

  @override
  State<ChatDocentesScreen> createState() => _ChatDocentesScreenState();
}

enum DocenteChatMode { porGrado, recientes, buscar }

class _ChatDocentesScreenState extends State<ChatDocentesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ Tu raíz real
  static const String _root = 'schools';

  // ✅ Colecciones CHAT v2
  static const String _colChatsAdmin = 'chats_admin';
  static const String _colChatGrados = 'chat_grados';

  // ✅ Threads CHAT v2 (Admin/Docentes)
  static const String _threadAllTeachers = 'all_teachers';

  late final String _schoolId;

  DocenteChatMode _mode = DocenteChatMode.porGrado;

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // Vinculación docente (v2): teachers_uid/{authUid} -> teacherDocId
  String? _teacherDocId;
  String _teacherName = 'Docente';
  String? _teacherErr;

  // Refs
  DocumentReference<Map<String, dynamic>>? _teacherDocRef;
  final Map<String, String> _subjectNameById = <String, String>{};
  final Map<String, String> _subjectIdByName = <String, String>{};

  CollectionReference<Map<String, dynamic>> get _teacherUidCol =>
      _db.collection(_root).doc(_schoolId).collection('teachers_uid');

  CollectionReference<Map<String, dynamic>> get _teachersCol =>
      _db.collection(_root).doc(_schoolId).collection('teachers');

  CollectionReference<Map<String, dynamic>> get _chatsAdminCol =>
      _db.collection(_root).doc(_schoolId).collection(_colChatsAdmin);

  CollectionReference<Map<String, dynamic>> get _chatGradosCol =>
      _db.collection(_root).doc(_schoolId).collection(_colChatGrados);

  @override
  void initState() {
    super.initState();

    // ✅ MISMO "clean" que usas en el login (evita mismatch de schoolId)
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = raw.trim().replaceAll('/', '_');

    _bootTeacherContext();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  void _logD(String msg) {
  }

  Future<void> _bootTeacherContext() async {
    await _loadSubjectCatalog();
    await _bindTeacherByTeachersUid();
  }

  // ---------------- WhatsApp-like helpers ----------------
  Timestamp? _asTimestamp(dynamic v) => v is Timestamp ? v : null;
  DateTime? _asDateTime(dynamic v) => _asTimestamp(v)?.toDate().toLocal();

  String _fmtTimeShort(DateTime? dt) {
    if (dt == null) return '';
    final h24 = dt.hour;
    final h = (h24 % 12 == 0) ? 12 : (h24 % 12);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _unreadDot() {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
    );
  }

  bool _isUnread({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) {
    if (myUid.isEmpty) return false;
    if (lastMessage.trim().isEmpty) return false;
    if (threadUpdatedAt == null) return false;
    if (lastSenderUid.isNotEmpty && lastSenderUid == myUid) return false;
    if (lastReadAt == null) return true;
    return threadUpdatedAt.isAfter(lastReadAt);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _readsStream({
    required String myUid,
    required String collection,
  }) {
    // Trae TODOS los reads de este usuario, para ESTE schoolId y esa colección
    return _db
       .collectionGroup('reads')
.where('uid', isEqualTo: myUid)
        .where('schoolId', isEqualTo: _schoolId)
        .where('collection', isEqualTo: collection)
        .snapshots();
  }

  Map<String, DateTime> _buildReadMap(QuerySnapshot<Map<String, dynamic>> snap) {
    // key: threadId  value: lastReadAt
    final out = <String, DateTime>{};
    for (final d in snap.docs) {
      final data = d.data();
      final threadId = (data['threadId'] ?? '').toString().trim();
      final lastReadAt = _asDateTime(data['lastReadAt']);
      if (threadId.isNotEmpty && lastReadAt != null) {
        out[threadId] = lastReadAt;
      }
    }
    return out;
  }

  // ---------------- Teacher binding (v2 correcto: teachers_uid) ----------------
  Future<void> _bindTeacherByTeachersUid() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        setState(() => _teacherErr = 'No hay sesión activa del docente.');
        return;
      }

      final uid = u.uid;

      _logD('AUTH uid=$uid schoolId=$_schoolId');

      // ✅ 1) teachers_uid/{uid} -> teacherDocId
      final linkSnap = await _teacherUidCol.doc(uid).get();
      _logD(
          'teachers_uid exists=${linkSnap.exists} path=${_teacherUidCol.doc(uid).path}');
      if (linkSnap.exists) _logD('teachers_uid data=${linkSnap.data()}');

      if (!linkSnap.exists) {
        setState(() {
          _teacherErr =
              'Este docente no está vinculado en teachers_uid.\n'
              'Necesitas crear schools/$_schoolId/teachers_uid/$uid con teacherDocId.';
        });
        return;
      }

      final link = linkSnap.data() ?? {};
      final tDocId = (link['teacherDocId'] ?? '').toString().trim();
      if (tDocId.isEmpty) {
        setState(() {
          _teacherErr = 'teachers_uid existe pero teacherDocId está vacío.';
        });
        return;
      }

      _teacherDocId = tDocId;

      // ✅ 2) teachers/{teacherDocId} (doc real)
      _teacherDocRef = _teachersCol.doc(tDocId);

      final tSnap = await _teacherDocRef!.get();
      _logD('teachers doc exists=${tSnap.exists} path=${_teacherDocRef!.path}');
      final t = tSnap.data() ?? {};
      _logD('teacher keys=${t.keys.toList()}');
      _logD(
          'teacher.authUid=${t['authUid']} enabled=${t['enabled']} active=${t['active']}');
      _logD('teacher.gradeIds=${t['gradeIds']}  teacher.grades=${t['grades']}');

      final tData = tSnap.data() ?? const <String, dynamic>{};
      _teacherName = _pickTeacherName(tData, fallback: widget.docenteNombre);

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _teacherErr = 'Error cargando docente: $e');
    }
  }

  String _pickTeacherName(Map<String, dynamic> m, {String? fallback}) {
    final f = (fallback ?? '').trim();
    final a =
        (m['displayName'] ?? m['name'] ?? m['nombre'] ?? m['nombres'] ?? '')
            .toString()
            .trim();
    if (a.isNotEmpty) return a;
    if (f.isNotEmpty) return f;
    return 'Docente';
  }

  String _normText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _loadSubjectCatalog() async {
    final byId = <String, String>{};
    final byName = <String, String>{};

    for (final col in const ['subjects', 'asignaturas', 'materias']) {
      try {
        final snap = await _db.collection(_root).doc(_schoolId).collection(col).get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final label = (data['name'] ?? data['nombre'] ?? data['title'] ?? doc.id)
              .toString()
              .trim();
          if (label.isEmpty) continue;
          byId[doc.id] = label;
          byName.putIfAbsent(_normText(label), () => doc.id);
        }
      } catch (_) {
        // Best-effort: si una colección no existe, seguimos con las demás.
      }
    }

    if (!mounted) return;
    setState(() {
      _subjectNameById
        ..clear()
        ..addAll(byId);
      _subjectIdByName
        ..clear()
        ..addAll(byName);
    });
  }

  // ✅ Extrae IDs y nombres DESDE teachers/{teacherDocId}
  List<_GradeItem> _extractGradeItems(Map<String, dynamic> m) {
    final rawIds = m['gradeIds'] ??
        m['gradesIds'] ??
        m['gradoIds'] ??
        m['gradosIds'] ??
        m['gradeId'] ??
        m['gradoId'];

    final rawNames =
        m['grades'] ?? m['gradeNames'] ?? m['grados'] ?? m['gradoNames'];

    final ids = <String>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final v = e.toString().trim();
        if (v.isNotEmpty) ids.add(v);
      }
    } else if (rawIds is String) {
      final v = rawIds.trim();
      if (v.isNotEmpty) ids.add(v);
    }

    final names = <String>[];
    if (rawNames is List) {
      for (final e in rawNames) {
        final v = e.toString().trim();
        if (v.isNotEmpty) names.add(v);
      }
    } else if (rawNames is String) {
      final v = rawNames.trim();
      if (v.isNotEmpty) names.add(v);
    }

    final out = <_GradeItem>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final name = (i < names.length ? names[i] : '').trim();
      out.add(_GradeItem(id: id, name: name.isEmpty ? id : name));
    }

    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  List<_SubjectItem> _extractSubjectItems(Map<String, dynamic> m) {
    final rawIds = m['subjectIds'] ??
        m['subjectsIds'] ??
        m['asignaturaIds'] ??
        m['asignaturasIds'] ??
        m['materiaIds'] ??
        m['materiasIds'] ??
        m['subjectId'] ??
        m['asignaturaId'] ??
        m['materiaId'];

    final rawNames = m['subjects'] ??
        m['subjectNames'] ??
        m['subjectsNames'] ??
        m['asignaturas'] ??
        m['asignaturasNames'] ??
        m['materias'] ??
        m['materiasNames'];

    final ids = <String>{};
    if (rawIds is List) {
      for (final e in rawIds) {
        final v = e.toString().trim();
        if (v.isNotEmpty) ids.add(v);
      }
    } else {
      final v = rawIds?.toString().trim() ?? '';
      if (v.isNotEmpty) ids.add(v);
    }

    final names = <String>{};
    if (rawNames is List) {
      for (final e in rawNames) {
        final v = e.toString().trim();
        if (v.isNotEmpty) names.add(v);
      }
    } else {
      final v = rawNames?.toString().trim() ?? '';
      if (v.isNotEmpty) names.add(v);
    }

    final out = <_SubjectItem>[];
    final seen = <String>{};

    for (final id in ids) {
      if (!seen.add(id)) continue;
      out.add(_SubjectItem(id: id, name: (_subjectNameById[id] ?? id).trim()));
    }

    for (final name in names) {
      final mappedId = _subjectIdByName[_normText(name)];
      if (mappedId == null || mappedId.isEmpty || !seen.add(mappedId)) continue;
      out.add(
        _SubjectItem(
          id: mappedId,
          name: (_subjectNameById[mappedId] ?? name).trim(),
        ),
      );
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  List<ChatGradeSubjectTarget> _buildGradeSubjectTargets({
    required List<_GradeItem> grades,
    required List<_SubjectItem> subjects,
  }) {
    final out = <ChatGradeSubjectTarget>[];
    for (final grade in grades) {
      for (final subject in subjects) {
        if (grade.id.trim().isEmpty || subject.id.trim().isEmpty) continue;
        out.add(
          ChatGradeSubjectTarget(
            gradeId: grade.id,
            gradeName: grade.name,
            subjectId: subject.id,
            subjectName: subject.name,
          ),
        );
      }
    }
    out.sort((a, b) {
      final gradeCmp = a.gradeName.toLowerCase().compareTo(b.gradeName.toLowerCase());
      if (gradeCmp != 0) return gradeCmp;
      return a.subjectName.toLowerCase().compareTo(b.subjectName.toLowerCase());
    });
    return out;
  }

  // ---------------- Open threads ----------------
  String _directThreadIdForTeacher() {
    final tid = (_teacherDocId ?? '').trim();
    return tid.isEmpty ? '' : 'direct_$tid';
  }

  void _openAllTeachersThread() {
    _openChatThread(
      collection: _colChatsAdmin,
      threadId: _threadAllTeachers,
      title: 'Todos los docentes',
      kind: _ChatThreadKind.adminTeachers,
    );
  }

  void _openDirectWithAdminThread() {
    final tid = _directThreadIdForTeacher();
    if (tid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No se encontró teacherDocId para abrir el chat privado.')),
      );
      return;
    }

    _openChatThread(
      collection: _colChatsAdmin,
      threadId: tid,
      title: 'Administración escolar',
      kind: _ChatThreadKind.adminDirect,
      teacherDocId: _teacherDocId,
    );
  }

  void _openGradeSubjectThread({
    required ChatGradeSubjectTarget target,
    required Set<String> allowedGradeIds,
    required Set<String> allowedSubjectIds,
  }) {
    if (!allowedGradeIds.contains(target.gradeId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para ese grado.')),
      );
      return;
    }

    if (allowedSubjectIds.isNotEmpty &&
        !allowedSubjectIds.contains(target.subjectId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para esa asignatura.')),
      );
      return;
    }

    _openChatThread(
      collection: _colChatGrados,
      threadId: target.threadId,
      title: target.title,
      kind: _ChatThreadKind.grade,
      gradeId: target.gradeId,
      gradeName: target.gradeName,
      subjectId: target.subjectId,
      subjectName: target.subjectName,
    );
  }

  void _openChatThread({
    required String collection,
    required String threadId,
    required String title,
    required _ChatThreadKind kind,
    String? teacherDocId,
    String? gradeId,
    String? gradeName,
    String? subjectId,
    String? subjectName,
  }) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _logD(
        'OPEN chat => authUid=$authUid schoolId=$_schoolId collection=$collection threadId=$threadId title="$title" teacherDocId=${teacherDocId ?? _teacherDocId} gradeId=$gradeId subjectId=$subjectId');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatThreadScreen(
          escuela: widget.escuela,
          rootCollection: _root,
          schoolId: _schoolId,
          collectionName: collection,
          threadId: threadId,
          title: title,
          kind: kind,
          teacherDocId: teacherDocId,
          gradeId: gradeId,
          gradeName: gradeName,
          subjectId: subjectId,
          subjectName: subjectName,
          displaySenderName: _teacherName,
          senderRole: 'docente',
        ),
      ),
    );
  }

  // ---------------- UI helpers ----------------
  Widget _modeButton({
    required DocenteChatMode mode,
    required IconData icon,
    required String text,
  }) {
    final selected = _mode == mode;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _mode = mode),
        icon: Icon(icon, size: 18, color: selected ? Colors.white : _blue),
        label: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : _blue,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? _blue : Colors.white,
          side: BorderSide(color: selected ? _blue : Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (widget.escuela.nombre ?? 'Escuela').trim();
    final teacherRef = _teacherDocRef;

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.transparent,
          fontSize: 0,
          height: 0,
        ),
        title:
            Text('Chat docente • $nombreEscuela', overflow: TextOverflow.ellipsis),
      ),
      body: (teacherRef == null)
          ? _buildContent(
              myUid: myUid,
              readsAdmin: const <String, DateTime>{},
              readsGrades: const <String, DateTime>{},
              allowedGradeIds: const <String>{},
              allowedSubjectIds: const <String>{},
              gradeItems: const <_GradeItem>[],
              chatTargets: const <ChatGradeSubjectTarget>[],
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: teacherRef.snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final gradeItems = _extractGradeItems(data);
                final allowedGradeIds = gradeItems.map((e) => e.id).toSet();
                final subjectItems = _extractSubjectItems(data);
                final allowedSubjectIds = subjectItems.map((e) => e.id).toSet();
                final chatTargets = _buildGradeSubjectTargets(
                  grades: gradeItems,
                  subjects: subjectItems,
                );

                final possibleName =
                    _pickTeacherName(data, fallback: widget.docenteNombre);
                if (possibleName.trim().isNotEmpty &&
                    possibleName != _teacherName) {
                  _teacherName = possibleName;
                }

                if (myUid.isEmpty) {
                  return _buildContent(
                      myUid: myUid,
                      readsAdmin: const <String, DateTime>{},
                      readsGrades: const <String, DateTime>{},
                      allowedGradeIds: allowedGradeIds,
                      allowedSubjectIds: allowedSubjectIds,
                      gradeItems: gradeItems,
                      chatTargets: chatTargets,
                    );
                  }

                // reads for admin threads
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _readsStream(myUid: myUid, collection: _colChatsAdmin),
                  builder: (context, rAdminSnap) {
                    final readsAdmin =
                        rAdminSnap.hasData ? _buildReadMap(rAdminSnap.data!) : <String, DateTime>{};

                    // reads for grade threads
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _readsStream(myUid: myUid, collection: _colChatGrados),
                      builder: (context, rGradeSnap) {
                        final readsGrades =
                            rGradeSnap.hasData ? _buildReadMap(rGradeSnap.data!) : <String, DateTime>{};

                        return _buildContent(
                          myUid: myUid,
                          readsAdmin: readsAdmin,
                          readsGrades: readsGrades,
                          allowedGradeIds: allowedGradeIds,
                          allowedSubjectIds: allowedSubjectIds,
                          gradeItems: gradeItems,
                          chatTargets: chatTargets,
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildContent({
    required String myUid,
    required Map<String, DateTime> readsAdmin,
    required Map<String, DateTime> readsGrades,
    required Set<String> allowedGradeIds,
    required Set<String> allowedSubjectIds,
    required List<_GradeItem> gradeItems,
    required List<ChatGradeSubjectTarget> chatTargets,
  }) {
    final noGrados = gradeItems.isEmpty;
    final noChats = chatTargets.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
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
                  CircleAvatar(
                    backgroundColor: _orange.withOpacity(0.15),
                    child: Icon(Icons.chat_bubble_outline, color: _orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chat de docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Docente: $_teacherName',
                  style: TextStyle(color: Colors.grey.shade700)),
              if (_teacherErr != null) ...[
                const SizedBox(height: 8),
                Text(
                  _teacherErr!,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w800),
                ),
              ],
              if (noGrados) ...[
                const SizedBox(height: 8),
                Text(
                  'No tienes grados asignados todavía. Habla con Admin escolar.',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700),
                ),
              ],
              if (!noGrados && noChats) ...[
                const SizedBox(height: 8),
                Text(
                  'No tienes asignaturas vinculadas todavía. Revisa teachers.subjectIds o la lista oficial de asignaturas.',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _modeButton(
                      mode: DocenteChatMode.porGrado,
                      icon: Icons.school,
                      text: 'Por grado'),
                  const SizedBox(width: 10),
                  _modeButton(
                      mode: DocenteChatMode.recientes,
                      icon: Icons.history,
                      text: 'Recientes'),
                  const SizedBox(width: 10),
                  _modeButton(
                      mode: DocenteChatMode.buscar,
                      icon: Icons.search,
                      text: 'Buscar'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Search (solo en modo buscar)
        if (_mode == DocenteChatMode.buscar)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar (mis grados y asignaturas)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),

        const SizedBox(height: 14),

        // Chats admin v2 siempre visibles arriba
        _AdminThreadsCard(
          blue: _blue,
          orange: _orange,
          onOpenAllTeachers: _openAllTeachersThread,
          onOpenDirect: _openDirectWithAdminThread,
          chatsAdminCol: _chatsAdminCol,
          directThreadId: _directThreadIdForTeacher(),
          myUid: myUid,
          readsAdmin: readsAdmin,
          fmtTime: _fmtTimeShort,
          unreadDot: _unreadDot,
          isUnread: _isUnread,
          asDateTime: _asDateTime,
        ),

        const SizedBox(height: 14),

        if (_mode == DocenteChatMode.recientes)
          _RecentGradeSubjectThreadsList(
            chatTargets: chatTargets,
            chatGradosCol: _chatGradosCol,
            blue: _blue,
            orange: _orange,
            onOpen: (target) => _openGradeSubjectThread(
              target: target,
              allowedGradeIds: allowedGradeIds,
              allowedSubjectIds: allowedSubjectIds,
            ),
            myUid: myUid,
            readsGrades: readsGrades,
            fmtTime: _fmtTimeShort,
            unreadDot: _unreadDot,
            isUnread: _isUnread,
            asDateTime: _asDateTime,
          )
        else
          _GradeSubjectThreadsList(
            chatTargets: chatTargets,
            blue: _blue,
            orange: _orange,
            search: _mode == DocenteChatMode.buscar ? _search : '',
            onOpen: (target) => _openGradeSubjectThread(
              target: target,
              allowedGradeIds: allowedGradeIds,
              allowedSubjectIds: allowedSubjectIds,
            ),
            chatGradosCol: _chatGradosCol,
            myUid: myUid,
            readsGrades: readsGrades,
            fmtTime: _fmtTimeShort,
            unreadDot: _unreadDot,
            isUnread: _isUnread,
            asDateTime: _asDateTime,
          ),
      ],
    );
  }
}

// ===================== Models =====================
class _GradeItem {
  final String id;
  final String name;
  const _GradeItem({required this.id, required this.name});
}

class _SubjectItem {
  final String id;
  final String name;
  const _SubjectItem({required this.id, required this.name});
}

class _GradeSubjectThreadsList extends StatelessWidget {
  final List<ChatGradeSubjectTarget> chatTargets;
  final Color blue;
  final Color orange;
  final String search;
  final void Function(ChatGradeSubjectTarget target) onOpen;
  final CollectionReference<Map<String, dynamic>> chatGradosCol;
  final String myUid;
  final Map<String, DateTime> readsGrades;
  final String Function(DateTime?) fmtTime;
  final Widget Function() unreadDot;
  final bool Function({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) isUnread;
  final DateTime? Function(dynamic v) asDateTime;

  const _GradeSubjectThreadsList({
    required this.chatTargets,
    required this.blue,
    required this.orange,
    required this.search,
    required this.onOpen,
    required this.chatGradosCol,
    required this.myUid,
    required this.readsGrades,
    required this.fmtTime,
    required this.unreadDot,
    required this.isUnread,
    required this.asDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = search.isEmpty
        ? chatTargets
        : chatTargets.where((x) {
            final q = search.toLowerCase();
            return x.gradeName.toLowerCase().contains(q) ||
                x.subjectName.toLowerCase().contains(q) ||
                x.title.toLowerCase().contains(q);
          }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chats por grado y asignatura',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No hay conversaciones asignadas para este docente.'),
            )
          else
            ListView.separated(
              itemCount: filtered.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = filtered[i];
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: chatGradosCol.doc(it.threadId).snapshots(),
                  builder: (_, ts) {
                    final td = ts.data?.data();
                    final last = (td?['lastMessage'] ?? '').toString().trim();
                    final who = (td?['lastSenderName'] ?? '').toString().trim();
                    final lastSenderUid =
                        (td?['lastSenderUid'] ?? '').toString().trim();
                    final updatedAt = asDateTime(td?['updatedAt']);
                    final timeTxt = fmtTime(updatedAt);

                    final lastReadAt = readsGrades[it.threadId];
                    final unread = isUnread(
                      threadUpdatedAt: updatedAt,
                      lastReadAt: lastReadAt,
                      lastSenderUid: lastSenderUid,
                      myUid: myUid,
                      lastMessage: last,
                    );

                    final preview = last.isEmpty
                        ? 'Chat de ${it.subjectName} para ${it.gradeName}'
                        : (who.isEmpty ? last : '$who: $last');

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: orange.withOpacity(0.12),
                        child: Icon(Icons.forum_outlined, color: orange),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              it.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeTxt.isNotEmpty)
                            Text(
                              timeTxt,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        preview,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unread) ...[
                            unreadDot(),
                            const SizedBox(width: 10),
                          ],
                          TextButton.icon(
                            onPressed: () => onOpen(it),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Abrir'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _RecentGradeSubjectThreadsList extends StatelessWidget {
  final List<ChatGradeSubjectTarget> chatTargets;
  final CollectionReference<Map<String, dynamic>> chatGradosCol;
  final Color blue;
  final Color orange;
  final void Function(ChatGradeSubjectTarget target) onOpen;
  final String myUid;
  final Map<String, DateTime> readsGrades;
  final String Function(DateTime?) fmtTime;
  final Widget Function() unreadDot;
  final bool Function({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) isUnread;
  final DateTime? Function(dynamic v) asDateTime;

  const _RecentGradeSubjectThreadsList({
    required this.chatTargets,
    required this.chatGradosCol,
    required this.blue,
    required this.orange,
    required this.onOpen,
    required this.myUid,
    required this.readsGrades,
    required this.fmtTime,
    required this.unreadDot,
    required this.isUnread,
    required this.asDateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: chatTargets.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Todavía no hay conversaciones recientes en tus grados y asignaturas.',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(chatTargets.length, (i) {
                final it = chatTargets[i];
                return Column(
                  children: [
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: chatGradosCol.doc(it.threadId).snapshots(),
                      builder: (_, ts) {
                        if (ts.hasError) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: blue.withOpacity(0.08),
                              child: Icon(Icons.history, color: blue),
                            ),
                            title: Text(it.title, overflow: TextOverflow.ellipsis),
                            subtitle: const Text('Sin acceso al hilo'),
                            trailing: TextButton.icon(
                              onPressed: () => onOpen(it),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('Abrir'),
                            ),
                          );
                        }

                        final td = ts.data?.data();
                        final last = (td?['lastMessage'] ?? '').toString().trim();
                        final who =
                            (td?['lastSenderName'] ?? '').toString().trim();
                        final lastSenderUid =
                            (td?['lastSenderUid'] ?? '').toString().trim();
                        final updatedAt = asDateTime(td?['updatedAt']);
                        final timeTxt = fmtTime(updatedAt);

                        final lastReadAt = readsGrades[it.threadId];
                        final unread = isUnread(
                          threadUpdatedAt: updatedAt,
                          lastReadAt: lastReadAt,
                          lastSenderUid: lastSenderUid,
                          myUid: myUid,
                          lastMessage: last,
                        );

                        final preview = last.isEmpty
                            ? 'Sin mensajes aún'
                            : (who.isEmpty ? last : '$who: $last');

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: blue.withOpacity(0.08),
                            child: Icon(Icons.history, color: blue),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(it.title, overflow: TextOverflow.ellipsis),
                              ),
                              if (timeTxt.isNotEmpty)
                                Text(
                                  timeTxt,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(preview, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (unread) ...[
                                unreadDot(),
                                const SizedBox(width: 10),
                              ],
                              TextButton.icon(
                                onPressed: () => onOpen(it),
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('Abrir'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (i != chatTargets.length - 1) const Divider(height: 1),
                  ],
                );
              }),
            ),
    );
  }
}

// ===================== UI: Admin threads card (v2) =====================
class _AdminThreadsCard extends StatelessWidget {
  final Color blue;
  final Color orange;

  final VoidCallback onOpenAllTeachers;
  final VoidCallback onOpenDirect;

  final CollectionReference<Map<String, dynamic>> chatsAdminCol;
  final String directThreadId;

  final String myUid;
  final Map<String, DateTime> readsAdmin;

  final String Function(DateTime?) fmtTime;
  final Widget Function() unreadDot;
  final bool Function({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) isUnread;
  final DateTime? Function(dynamic v) asDateTime;

  const _AdminThreadsCard({
    required this.blue,
    required this.orange,
    required this.onOpenAllTeachers,
    required this.onOpenDirect,
    required this.chatsAdminCol,
    required this.directThreadId,
    required this.myUid,
    required this.readsAdmin,
    required this.fmtTime,
    required this.unreadDot,
    required this.isUnread,
    required this.asDateTime,
  });

  @override
  Widget build(BuildContext context) {
    Widget tileFor({
      required String threadId,
      required IconData icon,
      required Color iconColor,
      required Color iconBg,
      required String title,
      required VoidCallback? onOpen,
    }) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: chatsAdminCol.doc(threadId).snapshots(),
        builder: (_, snap) {
          if (snap.hasError) return ListTile(title: Text(title), subtitle: const Text('Sin acceso'));

          final d = snap.data?.data();
          final last = (d?['lastMessage'] ?? '').toString().trim();
          final who = (d?['lastSenderName'] ?? '').toString().trim();
          final lastSenderUid = (d?['lastSenderUid'] ?? '').toString().trim();
          final updatedAt = asDateTime(d?['updatedAt']);
          final timeTxt = fmtTime(updatedAt);

          final lastReadAt = readsAdmin[threadId];
          final unread = isUnread(
            threadUpdatedAt: updatedAt,
            lastReadAt: lastReadAt,
            lastSenderUid: lastSenderUid,
            myUid: myUid,
            lastMessage: last,
          );

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: iconBg,
              child: Icon(icon, color: iconColor),
            ),
            title: Row(
              children: [
                Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
                if (timeTxt.isNotEmpty)
                  Text(
                    timeTxt,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
            subtitle: (last.isEmpty)
                ? const Text('Sin mensajes aún')
                : Text(who.isEmpty ? last : '$who: $last', overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread) ...[
                  unreadDot(),
                  const SizedBox(width: 10),
                ],
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir'),
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chats de docentes',
              style: TextStyle(
                  fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
          const SizedBox(height: 10),

          // all_teachers
          tileFor(
            threadId: 'all_teachers',
            icon: Icons.groups,
            iconColor: blue,
            iconBg: blue.withOpacity(0.10),
            title: 'Todos los docentes',
            onOpen: onOpenAllTeachers,
          ),
          const Divider(height: 1),

          // direct_{teacherDocId}
          tileFor(
            threadId: directThreadId,
            icon: Icons.admin_panel_settings,
            iconColor: orange,
            iconBg: orange.withOpacity(0.12),
            title: 'Administración escolar',
            onOpen: directThreadId.isEmpty ? null : onOpenDirect,
          ),
        ],
      ),
    );
  }
}

// ===================== UI: Grades list (con preview+hora+badge) =====================
class _GradesListV2 extends StatelessWidget {
  final List<_GradeItem> gradeItems;
  final Color blue;
  final Color orange;
  final String search;

  final void Function(String gradeId, String gradeName) onOpen;

  final CollectionReference<Map<String, dynamic>> chatGradosCol;
  final String myUid;
  final Map<String, DateTime> readsGrades;

  final String Function(DateTime?) fmtTime;
  final Widget Function() unreadDot;
  final bool Function({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) isUnread;
  final DateTime? Function(dynamic v) asDateTime;

  const _GradesListV2({
    required this.gradeItems,
    required this.blue,
    required this.orange,
    required this.search,
    required this.onOpen,
    required this.chatGradosCol,
    required this.myUid,
    required this.readsGrades,
    required this.fmtTime,
    required this.unreadDot,
    required this.isUnread,
    required this.asDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = search.isEmpty
        ? gradeItems
        : gradeItems.where((x) => x.name.toLowerCase().contains(search)).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chats por grado',
              style: TextStyle(
                  fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No hay grados asignados para este docente.'),
            )
          else
            ListView.separated(
              itemCount: filtered.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = filtered[i];

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: chatGradosCol.doc(it.id).snapshots(),
                  builder: (_, ts) {
                    final td = ts.data?.data();
                    final last = (td?['lastMessage'] ?? '').toString().trim();
                    final who = (td?['lastSenderName'] ?? '').toString().trim();
                    final lastSenderUid = (td?['lastSenderUid'] ?? '').toString().trim();
                    final updatedAt = asDateTime(td?['updatedAt']);
                    final timeTxt = fmtTime(updatedAt);

                    final lastReadAt = readsGrades[it.id];
                    final unread = isUnread(
                      threadUpdatedAt: updatedAt,
                      lastReadAt: lastReadAt,
                      lastSenderUid: lastSenderUid,
                      myUid: myUid,
                      lastMessage: last,
                    );

                    final preview = last.isEmpty ? 'Chat del aula (mi grado)' : (who.isEmpty ? last : '$who: $last');

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: orange.withOpacity(0.12),
                        child: Icon(Icons.school, color: orange),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(it.name, overflow: TextOverflow.ellipsis)),
                          if (timeTxt.isNotEmpty)
                            Text(
                              timeTxt,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(preview, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unread) ...[
                            unreadDot(),
                            const SizedBox(width: 10),
                          ],
                          TextButton.icon(
                            onPressed: () => onOpen(it.id, it.name),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Abrir'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ===================== UI: Recents list (con hora+badge) =====================
class _RecentThreadsListV2 extends StatelessWidget {
  final List<_GradeItem> gradeItems;
  final CollectionReference<Map<String, dynamic>> chatGradosCol;
  final Color blue;
  final Color orange;
  final void Function(String gradeId, String gradeName) onOpen;

  final String myUid;
  final Map<String, DateTime> readsGrades;

  final String Function(DateTime?) fmtTime;
  final Widget Function() unreadDot;
  final bool Function({
    required DateTime? threadUpdatedAt,
    required DateTime? lastReadAt,
    required String lastSenderUid,
    required String myUid,
    required String lastMessage,
  }) isUnread;
  final DateTime? Function(dynamic v) asDateTime;

  const _RecentThreadsListV2({
    required this.gradeItems,
    required this.chatGradosCol,
    required this.blue,
    required this.orange,
    required this.onOpen,
    required this.myUid,
    required this.readsGrades,
    required this.fmtTime,
    required this.unreadDot,
    required this.isUnread,
    required this.asDateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: gradeItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Todavía no hay conversaciones recientes en tus grados.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(gradeItems.length, (i) {
                final it = gradeItems[i];

                return Column(
                  children: [
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: chatGradosCol.doc(it.id).snapshots(),
                      builder: (_, ts) {
                        if (ts.hasError) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: blue.withOpacity(0.08),
                              child: Icon(Icons.history, color: blue),
                            ),
                            title: Text(it.name, overflow: TextOverflow.ellipsis),
                            subtitle: const Text('Sin acceso al hilo'),
                            trailing: TextButton.icon(
                              onPressed: () => onOpen(it.id, it.name),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('Abrir'),
                            ),
                          );
                        }

                        final td = ts.data?.data();
                        final last = (td?['lastMessage'] ?? '').toString().trim();
                        final who = (td?['lastSenderName'] ?? '').toString().trim();
                        final lastSenderUid = (td?['lastSenderUid'] ?? '').toString().trim();
                        final updatedAt = asDateTime(td?['updatedAt']);
                        final timeTxt = fmtTime(updatedAt);

                        final lastReadAt = readsGrades[it.id];
                        final unread = isUnread(
                          threadUpdatedAt: updatedAt,
                          lastReadAt: lastReadAt,
                          lastSenderUid: lastSenderUid,
                          myUid: myUid,
                          lastMessage: last,
                        );

                        final preview = last.isEmpty
                            ? 'Sin mensajes aún'
                            : (who.isEmpty ? last : '$who: $last');

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: blue.withOpacity(0.08),
                            child: Icon(Icons.history, color: blue),
                          ),
                          title: Row(
                            children: [
                              Expanded(child: Text(it.name, overflow: TextOverflow.ellipsis)),
                              if (timeTxt.isNotEmpty)
                                Text(
                                  timeTxt,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(preview, overflow: TextOverflow.ellipsis),

                          // ✅ Puntito EXACTO al lado del botón Abrir (izquierda del botón)
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (unread) ...[
                                unreadDot(),
                                const SizedBox(width: 10),
                              ],
                              TextButton.icon(
                                onPressed: () => onOpen(it.id, it.name),
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('Abrir'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (i != gradeItems.length - 1) const Divider(height: 1),
                  ],
                );
              }),
            ),
    );
  }
}
// ===================== Thread screen (sirve para chats_admin y chat_grados) =====================
enum _ChatThreadKind { adminTeachers, adminDirect, grade }

class _ChatThreadScreen extends StatefulWidget {
  final Escuela escuela;
  final String rootCollection;
  final String schoolId;

  final String collectionName; // chats_admin | chat_grados
  final String threadId;

  final String title;
  final _ChatThreadKind kind;

  // Para crear thread si no existe (v2)
  final String? teacherDocId; // solo direct
  final String? gradeId; // solo grado
  final String? gradeName; // solo grado
  final String? subjectId; // solo chat por grado+asignatura
  final String? subjectName; // solo chat por grado+asignatura

  final String displaySenderName;
  final String senderRole; // 'docente'

  const _ChatThreadScreen({
    required this.escuela,
    required this.rootCollection,
    required this.schoolId,
    required this.collectionName,
    required this.threadId,
    required this.title,
    required this.kind,
    this.teacherDocId,
    this.gradeId,
    this.gradeName,
    this.subjectId,
    this.subjectName,
    required this.displaySenderName,
    required this.senderRole,
  });

  @override
  State<_ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<_ChatThreadScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _msgCtrl = TextEditingController();

  bool _sending = false;

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  bool _didProbe = false;

  Timer? _readDebounce;

  void _logT(String msg) {
  }

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection(widget.rootCollection)
      .doc(widget.schoolId)
      .collection(widget.collectionName)
      .doc(widget.threadId);

  CollectionReference<Map<String, dynamic>> get _msgsCol =>
      _threadRef.collection('mensajes');

  DocumentReference<Map<String, dynamic>> _readRef(String uid) => _threadRef.collection('reads').doc(uid);

  Timestamp? _asTimestamp(dynamic v) => v is Timestamp ? v : null;

  String _fmtMsgTime(dynamic ts) {
    final t = _asTimestamp(ts);
    if (t == null) return '';
    final dt = t.toDate().toLocal();
    final h24 = dt.hour;
    final h = (h24 % 12 == 0) ? 12 : (h24 % 12);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  void _scheduleMarkRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 650), () async {
      try {
await _readRef(uid).set({
  'uid': uid, // ✅ NUEVO
  'lastReadAt': FieldValue.serverTimestamp(),
  'schoolId': widget.schoolId,
  'collection': widget.collectionName,
  'threadId': widget.threadId,
}, SetOptions(merge: true));
      } catch (_) {
        // silencioso
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _probePermissionsOnce();
    // marca leído al entrar
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleMarkRead());
  }

  Future<void> _probePermissionsOnce() async {
    if (_didProbe) return;
    _didProbe = true;

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _logT(
        'ENTER => authUid=$authUid schoolId=${widget.schoolId} col=${widget.collectionName} threadId=${widget.threadId}');
    _logT('PATH thread=${_threadRef.path} msgs=${_msgsCol.path}');

    // 1) thread GET
    try {
      final t = await _threadRef.get();
      _logT('PROBE thread GET OK exists=${t.exists}');
    } catch (e) {
      if (e is FirebaseException) {
        _logT('PROBE thread GET DENIED code=${e.code} msg=${e.message}');
      } else {
        _logT('PROBE thread GET DENIED => $e');
      }
    }

    // 2) mensajes LIST
    try {
      final q = await _msgsCol.limit(1).get();
      _logT('PROBE msgs LIST OK docs=${q.docs.length}');
    } catch (e) {
      if (e is FirebaseException) {
        _logT('PROBE msgs LIST DENIED code=${e.code} msg=${e.message}');
      } else {
        _logT('PROBE msgs LIST DENIED => $e');
      }
    }
  }

  @override
  void dispose() {
    _readDebounce?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureThreadExistsOnFirstMessage({
    required String lastText,
    required String senderUid,
    required String senderName,
    required String senderRole,
  }) async {
    final snap = await _threadRef.get();
    if (snap.exists) return;

    final now = FieldValue.serverTimestamp();

    // -------- chats_admin --------
    if (widget.collectionName == 'chats_admin') {
      final isAll = widget.threadId == 'all_teachers';

      final Map<String, dynamic> payload = {
        'title': widget.title,
        'type': isAll ? 'all_teachers' : 'direct_teacher',
        'createdAt': now,
        'updatedAt': now,
        'lastMessage': lastText,
        'lastSenderUid': senderUid,
        'lastSenderName': senderName,
        'lastSenderRole': senderRole,
      };

      if (!isAll) {
        final tdoc = (widget.teacherDocId ?? '').trim();
        if (tdoc.isEmpty) {
          throw Exception('No puedo crear thread direct sin teacherDocId.');
        }
        final expectedThreadId = 'direct_$tdoc';
        if (widget.threadId != expectedThreadId) {
          throw Exception('ThreadId inválido. Esperado: $expectedThreadId');
        }

        // ✅ IMPORTANTE: guardar teacherDocId (ayuda a admin y a índices)
        payload['teacherDocId'] = tdoc;
      }

      await _threadRef.set(payload, SetOptions(merge: false));
      return;
    }

    // -------- chat_grados --------
    final gradeId = (widget.gradeId ?? '').toString().trim();
    final gradeName = (widget.gradeName ?? widget.title).toString().trim();
    final subjectId = (widget.subjectId ?? '').toString().trim();
    final subjectName = (widget.subjectName ?? '').toString().trim();

    if (gradeId.isEmpty) {
      throw Exception('No puedo crear chat_grados: gradeId vacío.');
    }
    if (subjectId.isEmpty) {
      throw Exception('No puedo crear chat_grados: subjectId vacío.');
    }
    final expectedThreadId = buildChatGradeSubjectThreadId(gradeId, subjectId);
    if (widget.threadId != expectedThreadId) {
      throw Exception(
        'ThreadId inválido en chat_grados. Esperado: $expectedThreadId',
      );
    }

    final Map<String, dynamic> payload = {
      'gradeId': gradeId,
      'gradeName': gradeName.isEmpty ? gradeId : gradeName,
      'subjectId': subjectId,
      'subjectName': subjectName.isEmpty ? subjectId : subjectName,
      'createdAt': now,
      'updatedAt': now,
      'lastMessage': lastText,
      'lastSenderUid': senderUid,
      'lastSenderName': senderName,
      'lastSenderRole': senderRole,
    };

    await _threadRef.set(payload, SetOptions(merge: false));
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

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      if (uid.isEmpty) throw Exception('Sesión inválida: uid vacío.');

      final senderName = widget.displaySenderName.trim().isEmpty
          ? 'Docente'
          : widget.displaySenderName.trim();
      final senderRole = widget.senderRole;

      if (widget.collectionName == 'chats_admin' && widget.threadId != 'all_teachers') {
        final tdoc = (widget.teacherDocId ?? '').trim();
        final expectedThreadId = 'direct_$tdoc';
        if (tdoc.isEmpty || widget.threadId != expectedThreadId) {
          throw Exception('Thread inválido: falta teacherDocId o threadId no coincide.');
        }
      }

      if (widget.collectionName == 'chat_grados') {
        final gradeId = (widget.gradeId ?? '').trim();
        final subjectId = (widget.subjectId ?? '').trim();
        final expectedThreadId = buildChatGradeSubjectThreadId(gradeId, subjectId);
        if (gradeId.isEmpty || subjectId.isEmpty || widget.threadId != expectedThreadId) {
          throw Exception(
            'Thread inválido: faltan gradeId/subjectId o threadId no coincide.',
          );
        }
      }

      await _ensureThreadExistsOnFirstMessage(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

      await _msgsCol.add({
        'text': text,
        'senderRole': senderRole,
        'senderName': senderName,
        'senderUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _updateThreadMeta(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

      _msgCtrl.clear();

      // ✅ como yo envié, marco leído también
      _scheduleMarkRead();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final showHint = widget.kind == _ChatThreadKind.adminDirect
        ? 'Chat privado con administración'
        : widget.kind == _ChatThreadKind.adminTeachers
            ? 'Chat con todos los docentes'
            : 'Chat del grado y la asignatura';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  widget.kind == _ChatThreadKind.grade
                      ? Icons.school
                      : Icons.admin_panel_settings,
                  color: _orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    showHint,
                    style: TextStyle(
                        color: Colors.grey.shade800, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgsCol.orderBy('createdAt', descending: true).limit(80).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No hay mensajes aún. Escribe el primero.'));
                }

                // ✅ al ver mensajes, marca leído (debounce)
                _scheduleMarkRead();

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final text = (data['text'] ?? '').toString();
                    final sender = (data['senderName'] ?? '').toString();
                    final role = (data['senderRole'] ?? '').toString();
                    final senderUid = (data['senderUid'] ?? '').toString();
                    final timeTxt = _fmtMsgTime(data['createdAt']);

                    final isMe = senderUid.isNotEmpty && senderUid == myUid;

                    final bubbleColor = isMe ? _blue : Colors.white;
                    final textColor = isMe ? Colors.white : Colors.black87;
                    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;

                    return Align(
                      alignment: align,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe && sender.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  role == 'admin' ? 'Admin • $sender' : (role == 'admin_escolar' ? 'Admin • $sender' : sender),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: _orange,
                                  ),
                                ),
                              ),
                            Text(text, style: TextStyle(color: textColor)),
                            if (timeTxt.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  timeTxt,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
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
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
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
                        backgroundColor: _orange,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
      ),
    );
  }
}
