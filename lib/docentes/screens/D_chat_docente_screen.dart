// lib/docentes/screens/d_chat_docente_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class DChatDocenteScreen extends StatefulWidget {
  final Escuela escuela;

  /// Opcional: si luego tienes el nombre real del docente logueado.
  final String? docenteNombre;

  const DChatDocenteScreen({
    super.key,
    required this.escuela,
    this.docenteNombre,
  });

  @override
  State<DChatDocenteScreen> createState() => _DChatDocenteScreenState();
}

enum DocenteChatMode { porGrado, recientes, buscar }

class _DChatDocenteScreenState extends State<DChatDocenteScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  DocenteChatMode _mode = DocenteChatMode.porGrado;

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // ✅ Tu raíz real (según captura): schools
  static const String _root = 'schools';

  // ✅ Thread fijo para el chat con administración
  static const String _adminThreadId = 'admin_escolar';
  static const String _adminTitle = 'Admin escolar';

  DocumentReference<Map<String, dynamic>>? _teacherRef;
  String _teacherName = 'Docente';
  String? _teacherErr;

  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      _db.collection(_root).doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _threadsCol =>
      _db.collection(_root).doc(_schoolId).collection('chat_grados');

  CollectionReference<Map<String, dynamic>> get _teachersCol =>
      _db.collection(_root).doc(_schoolId).collection('teachers');

  CollectionReference<Map<String, dynamic>> get _teachersPublicCol =>
      _db.collection(_root).doc(_schoolId).collection('teachers_public');

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _ensureSchoolDocId(raw);
    _bindTeacherDoc();
  }

  String _ensureSchoolDocId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    return id.startsWith('eduproapp_admin_') ? id : 'eduproapp_admin_$id';
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  // ---------------- Teacher binding (encontrar doc del docente) ----------------
  Future<void> _bindTeacherDoc() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        setState(() => _teacherErr = 'No hay sesión activa del docente.');
        return;
      }

      final uid = u.uid;
      final emailLower = (u.email ?? '').toLowerCase().trim();

      // 1) docId == uid (ideal)
      final ref1 = _teachersCol.doc(uid);
      final s1 = await ref1.get();
      if (s1.exists) {
        _teacherRef = ref1;
        _teacherName = _pickTeacherName(s1.data() ?? {}, fallback: widget.docenteNombre);
        if (mounted) setState(() {});
        return;
      }

      // 2) buscar en teachers por campo uid
      final q2 = await _teachersCol.where('uid', isEqualTo: uid).limit(1).get();
      if (q2.docs.isNotEmpty) {
        _teacherRef = q2.docs.first.reference;
        _teacherName = _pickTeacherName(q2.docs.first.data(), fallback: widget.docenteNombre);
        if (mounted) setState(() {});
        return;
      }

      // 3) buscar por emailLower / email
      if (emailLower.isNotEmpty) {
        final q3a = await _teachersCol.where('emailLower', isEqualTo: emailLower).limit(1).get();
        if (q3a.docs.isNotEmpty) {
          _teacherRef = q3a.docs.first.reference;
          _teacherName = _pickTeacherName(q3a.docs.first.data(), fallback: widget.docenteNombre);
          if (mounted) setState(() {});
          return;
        }

        final q3b = await _teachersCol.where('email', isEqualTo: emailLower).limit(1).get();
        if (q3b.docs.isNotEmpty) {
          _teacherRef = q3b.docs.first.reference;
          _teacherName = _pickTeacherName(q3b.docs.first.data(), fallback: widget.docenteNombre);
          if (mounted) setState(() {});
          return;
        }
      }

      // 4) fallback: teachers_public
      final refP = _teachersPublicCol.doc(uid);
      final sp = await refP.get();
      if (sp.exists) {
        _teacherRef = refP;
        _teacherName = _pickTeacherName(sp.data() ?? {}, fallback: widget.docenteNombre);
        if (mounted) setState(() {});
        return;
      }

      // Si no se encontró doc del docente:
      _teacherName = (widget.docenteNombre ?? '').trim().isEmpty ? 'Docente' : widget.docenteNombre!.trim();
      setState(() {
        _teacherErr =
            'No se encontró el perfil del docente en teachers/teachers_public.\n'
            'Igual puedes hablar con Admin escolar para que te asignen grados.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _teacherErr = 'Error cargando docente: $e');
    }
  }

  String _pickTeacherName(Map<String, dynamic> m, {String? fallback}) {
    final f = (fallback ?? '').trim();
    final a = (m['displayName'] ?? m['name'] ?? m['nombre'] ?? m['nombres'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    if (f.isNotEmpty) return f;
    return 'Docente';
  }

  Set<String> _extractGradeIds(Map<String, dynamic> m) {
    dynamic raw = m['gradoIds'] ??
        m['gradosIds'] ??
        m['gradeIds'] ??
        m['gradesIds'] ??
        m['grados'] ??
        m['grades'] ??
        m['gradoId'] ??
        m['gradeId'];

    final out = <String>{};

    if (raw is String) {
      final v = raw.trim();
      if (v.isNotEmpty) out.add(v);
      return out;
    }

    if (raw is List) {
      for (final e in raw) {
        if (e == null) continue;

        if (e is String) {
          final v = e.trim();
          if (v.isNotEmpty) out.add(v);
        } else if (e is Map) {
          final id = (e['id'] ?? e['gradoId'] ?? e['gradeId'] ?? '').toString().trim();
          if (id.isNotEmpty) out.add(id);
        } else {
          final v = e.toString().trim();
          if (v.isNotEmpty) out.add(v);
        }
      }
    }

    return out;
  }

  void _openAdminThread() {
    _openThread(gradoId: _adminThreadId, gradoName: _adminTitle, isAdmin: true, allowedGradeIds: const <String>{});
  }

  void _openThread({
    required String gradoId,
    required String gradoName,
    required bool isAdmin,
    required Set<String> allowedGradeIds,
  }) {
    // ✅ seguridad UI: si no es admin, solo permitir si está asignado
    if (!isAdmin && !allowedGradeIds.contains(gradoId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para ese grado.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DChatGradoThreadScreen(
          escuela: widget.escuela,
          schoolId: _schoolId,
          gradoId: gradoId,
          gradoName: gradoName,
          docenteNombre: _teacherName,
          isAdminThread: isAdmin,
          rootCollection: _root,
        ),
      ),
    );
  }

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

    final teacherRef = _teacherRef;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text('Chat docente • $nombreEscuela', overflow: TextOverflow.ellipsis),
      ),
      body: (teacherRef == null)
          ? _buildContent(allowedGradeIds: const <String>{})
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: teacherRef.snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final allowedGradeIds = _extractGradeIds(data);

                // Si no hay grados asignados, igual mostramos Admin
                return _buildContent(allowedGradeIds: allowedGradeIds);
              },
            ),
    );
  }

  Widget _buildContent({required Set<String> allowedGradeIds}) {
    // Si no tiene grados, mostrar aviso (pero deja Admin disponible)
    final noGrados = allowedGradeIds.isEmpty;

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
              Text(
                'Docente: $_teacherName',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (_teacherErr != null) ...[
                const SizedBox(height: 8),
                Text(
                  _teacherErr!,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                ),
              ],
              if (noGrados) ...[
                const SizedBox(height: 8),
                Text(
                  'No tienes grados asignados todavía. Habla con Admin escolar.',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _modeButton(mode: DocenteChatMode.porGrado, icon: Icons.school, text: 'Por grado'),
                  const SizedBox(width: 10),
                  _modeButton(mode: DocenteChatMode.recientes, icon: Icons.history, text: 'Recientes'),
                  const SizedBox(width: 10),
                  _modeButton(mode: DocenteChatMode.buscar, icon: Icons.search, text: 'Buscar'),
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
                labelText: 'Buscar (solo mis grados)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),

        const SizedBox(height: 14),

        if (_mode == DocenteChatMode.recientes)
          _RecentThreadsList(
            threadsCol: _threadsCol,
            blue: _blue,
            orange: _orange,
            adminTitle: _adminTitle,
            onOpenAdmin: _openAdminThread,
            allowedGradeIds: allowedGradeIds,
            onOpen: (gradoId, gradoName) => _openThread(
              gradoId: gradoId,
              gradoName: gradoName,
              isAdmin: gradoId == _adminThreadId,
              allowedGradeIds: allowedGradeIds,
            ),
            adminThreadId: _adminThreadId,
          )
        else
          _GradesList(
            gradosCol: _gradosCol,
            blue: _blue,
            orange: _orange,
            search: _mode == DocenteChatMode.buscar ? _search : '',
            allowedGradeIds: allowedGradeIds,
            adminTitle: _adminTitle,
            onOpenAdmin: _openAdminThread,
            onOpen: (gradoId, gradoName) => _openThread(
              gradoId: gradoId,
              gradoName: gradoName,
              isAdmin: false,
              allowedGradeIds: allowedGradeIds,
            ),
          ),
      ],
    );
  }
}

class _GradesList extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> gradosCol;
  final Color blue;
  final Color orange;
  final String search;
  final Set<String> allowedGradeIds;
  final VoidCallback onOpenAdmin;
  final String adminTitle;
  final void Function(String gradoId, String gradoName) onOpen;

  const _GradesList({
    required this.gradosCol,
    required this.blue,
    required this.orange,
    required this.search,
    required this.allowedGradeIds,
    required this.onOpenAdmin,
    required this.onOpen,
    required this.adminTitle,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversaciones',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
          ),
          const SizedBox(height: 10),

          // ✅ Admin escolar SIEMPRE arriba
          ListTile(
            leading: CircleAvatar(
              backgroundColor: blue.withOpacity(0.10),
              child: Icon(Icons.admin_panel_settings, color: blue),
            ),
            title: Text(adminTitle, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Chat directo con la administración'),
            trailing: TextButton.icon(
              onPressed: onOpenAdmin,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Abrir'),
            ),
          ),
          const Divider(height: 1),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: gradosCol.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Text('Error: ${snap.error}');
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snap.data!.docs;

              // ✅ solo mis grados asignados
              final items = docs
                  .where((d) => allowedGradeIds.contains(d.id))
                  .map((d) {
                    final name = (d.data()['name'] ?? '').toString().trim();
                    return {'id': d.id, 'name': name.isEmpty ? d.id : name};
                  })
                  .toList();

              items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

              final filtered = search.isEmpty
                  ? items
                  : items.where((x) => (x['name'] as String).toLowerCase().contains(search)).toList();

              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No hay grados asignados para este docente (o no coinciden los IDs).'),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = filtered[i];
                  final gradoId = r['id'] as String;
                  final gradoName = r['name'] as String;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: orange.withOpacity(0.12),
                      child: Icon(Icons.school, color: orange),
                    ),
                    title: Text(gradoName, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Chat del aula (mi grado)'),
                    trailing: TextButton.icon(
                      onPressed: () => onOpen(gradoId, gradoName),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Abrir'),
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

class _RecentThreadsList extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> threadsCol;
  final Color blue;
  final Color orange;
  final VoidCallback onOpenAdmin;
  final void Function(String gradoId, String gradoName) onOpen;
  final String adminThreadId;
  final String adminTitle;
  final Set<String> allowedGradeIds;

  const _RecentThreadsList({
    required this.threadsCol,
    required this.blue,
    required this.orange,
    required this.onOpenAdmin,
    required this.onOpen,
    required this.adminThreadId,
    required this.adminTitle,
    required this.allowedGradeIds,
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
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: threadsCol.orderBy('updatedAt', descending: true).limit(30).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Text('Error: ${snap.error}');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(10),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final docs = snap.data!.docs;

          // ✅ Admin arriba siempre
          final tiles = <Widget>[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: blue.withOpacity(0.10),
                child: Icon(Icons.admin_panel_settings, color: blue),
              ),
              title: Text(adminTitle, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Chat directo con la administración'),
              trailing: TextButton.icon(
                onPressed: onOpenAdmin,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir'),
              ),
            ),
            const Divider(height: 1),
          ];

          // ✅ solo threads de MIS grados (o admin)
          final filtered = docs.where((d) {
            if (d.id == adminThreadId) return true;
            return allowedGradeIds.contains(d.id);
          }).toList();

          if (filtered.isEmpty) {
            tiles.add(const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Todavía no hay conversaciones recientes en tus grados.'),
            ));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
          }

          tiles.addAll(List.generate(filtered.length, (i) {
            final d = filtered[i];
            final data = d.data();

            final gradoId = d.id;
            final gradoName = (data['gradoName'] ?? gradoId).toString();
            final last = (data['lastMessage'] ?? '').toString();
            final who = (data['lastSenderName'] ?? '').toString();

            // Evitar duplicar el admin si ya está arriba
            if (gradoId == adminThreadId) return const SizedBox.shrink();

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: blue.withOpacity(0.08),
                child: Icon(Icons.history, color: blue),
              ),
              title: Text(gradoName, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                who.isEmpty ? last : '$who: $last',
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton.icon(
                onPressed: () => onOpen(gradoId, gradoName),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir'),
              ),
            );
          }));

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
        },
      ),
    );
  }
}

class _DChatGradoThreadScreen extends StatefulWidget {
  final Escuela escuela;
  final String schoolId;
  final String gradoId;
  final String gradoName;
  final String? docenteNombre;

  final bool isAdminThread;
  final String rootCollection;

  const _DChatGradoThreadScreen({
    required this.escuela,
    required this.schoolId,
    required this.gradoId,
    required this.gradoName,
    this.docenteNombre,
    required this.isAdminThread,
    required this.rootCollection,
  });

  @override
  State<_DChatGradoThreadScreen> createState() => _DChatGradoThreadScreenState();
}

class _DChatGradoThreadScreenState extends State<_DChatGradoThreadScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _msgCtrl = TextEditingController();
  bool _sending = false;

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection(widget.rootCollection)
      .doc(widget.schoolId)
      .collection('chat_grados')
      .doc(widget.gradoId);

  CollectionReference<Map<String, dynamic>> get _msgsCol => _threadRef.collection('mensajes');

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';

      final senderName = (widget.docenteNombre ?? 'Docente').trim().isEmpty
          ? 'Docente'
          : widget.docenteNombre!.trim();

      await _msgsCol.add({
        'text': text,
        'senderRole': 'docente',
        'senderName': senderName,
        'senderUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _threadRef.set({
        'gradoId': widget.gradoId,
        'gradoName': widget.gradoName,
        'type': widget.isAdminThread ? 'admin' : 'grado',
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
        'lastSenderName': senderName,
        'lastSenderRole': 'docente',
        'lastSenderUid': uid,
      }, SetOptions(merge: true));

      _msgCtrl.clear();
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
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(widget.gradoName, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          if (widget.isAdminThread)
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
                  Icon(Icons.admin_panel_settings, color: _orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chat con la administración escolar.',
                      style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgsCol.orderBy('createdAt', descending: true).limit(80).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No hay mensajes aún. Escribe el primero.'));
                }

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

                    final isMe = senderUid.isNotEmpty ? (senderUid == myUid) : (role == 'docente');
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
                                  role == 'admin' ? 'Admin • $sender' : sender,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: _orange,
                                  ),
                                ),
                              ),
                            Text(text, style: TextStyle(color: textColor)),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
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
