import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum ChatThreadKind { chatsAdmin, chatGrados }

class ChatThreadScreen extends StatefulWidget {
  // Root siempre "schools" en tu proyecto
  final String rootCollection; // 'schools'
  final String schoolId;

  // 'chats_admin' o 'chat_grados'
  final String collectionName;
  final String threadId;

  // Título en AppBar
  final String title;

  // Sender (quien escribe desde esta pantalla)
  // roles esperados por tus rules v2: admin_escolar/admin, docente/teacher, student/alumno/estudiante
  final String senderRole;
  final String senderName;

  // Para crear thread con schema estricto cuando falte
  final ChatThreadKind kind;

  /// Si true: crea doc del thread si no existe (solo recomendado para admin/docente).
  final bool createThreadIfMissing;

  /// Si true: actualiza lastMessage/lastSender*/updatedAt en el thread (solo admin/docente recomendado).
  final bool canUpdateThreadMeta;

  // Solo aplica si kind == chatsAdmin (direct_teacher)
  final String? teacherDocId; // requerido para direct_teacher

  // Solo aplica si kind == chatGrados
  final String? gradeId;   // normalmente = threadId
  final String? gradeName; // nombre bonito para guardar en thread

  const ChatThreadScreen({
    super.key,
    required this.rootCollection,
    required this.schoolId,
    required this.collectionName,
    required this.threadId,
    required this.title,
    required this.senderRole,
    required this.senderName,
    required this.kind,
    this.createThreadIfMissing = true,
    this.canUpdateThreadMeta = true,
    this.teacherDocId,
    this.gradeId,
    this.gradeName,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _msgCtrl = TextEditingController();
  bool _sending = false;

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection(widget.rootCollection)
      .doc(widget.schoolId)
      .collection(widget.collectionName)
      .doc(widget.threadId);

  CollectionReference<Map<String, dynamic>> get _msgsCol => _threadRef.collection('mensajes');

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  String get _myUid => _auth.currentUser?.uid ?? '';

  // -------------------------
  // Schema estricto (CHAT v2)
  // -------------------------
  Map<String, dynamic> _buildThreadCreatePayload({
    required String lastText,
    required String senderUid,
    required String senderName,
    required String senderRole,
  }) {
    final now = FieldValue.serverTimestamp();

    if (widget.kind == ChatThreadKind.chatsAdmin) {
      final isAllTeachers = widget.threadId == 'all_teachers';
      final type = isAllTeachers ? 'all_teachers' : 'direct_teacher';

      final data = <String, dynamic>{
        'title': widget.title, // <=80 recomendado en rules
        'type': type,
        'createdAt': now,
        'updatedAt': now,
        'lastMessage': lastText,
        'lastSenderUid': senderUid,
        'lastSenderName': senderName,
        'lastSenderRole': senderRole,
      };

      if (!isAllTeachers) {
        final tdoc = (widget.teacherDocId ?? '').trim();
        // Si no lo tienes, se rompe el create en rules v2
        data['teacherDocId'] = tdoc;
      }

      return data;
    }

    // chat_grados
    final gradeId = (widget.gradeId ?? widget.threadId).trim();
    final gradeName = (widget.gradeName ?? widget.title).trim();

    return <String, dynamic>{
      'gradeId': gradeId,
      'gradeName': gradeName,
      'createdAt': now,
      'updatedAt': now,
      'lastMessage': lastText,
      'lastSenderUid': senderUid,
      'lastSenderName': senderName,
      'lastSenderRole': senderRole,
    };
  }

  Future<void> _ensureThreadExists({
    required String lastText,
    required String senderUid,
    required String senderName,
    required String senderRole,
  }) async {
    if (!widget.createThreadIfMissing) return;

    final snap = await _threadRef.get();
    if (snap.exists) return;

    final payload = _buildThreadCreatePayload(
      lastText: lastText,
      senderUid: senderUid,
      senderName: senderName,
      senderRole: senderRole,
    );

    // ⚠️ merge: false para que el doc tenga solo el schema permitido
    await _threadRef.set(payload, SetOptions(merge: false));
  }

  Future<void> _updateThreadMeta({
    required String lastText,
    required String senderUid,
    required String senderName,
    required String senderRole,
  }) async {
    if (!widget.canUpdateThreadMeta) return;

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
      final uid = _myUid;
      final senderName = widget.senderName.trim().isEmpty ? 'Usuario' : widget.senderName.trim();
      final senderRole = widget.senderRole;

      // 1) Crear thread si falta (solo si corresponde)
      await _ensureThreadExists(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

      // 2) Crear mensaje (esto es lo esencial)
      await _msgsCol.add({
        'text': text,
        'senderUid': uid,
        'senderRole': senderRole,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3) Actualizar meta del thread (si reglas lo permiten)
      await _updateThreadMeta(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

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
  Widget build(BuildContext context) {
    final myUid = _myUid;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
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
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final text = (d['text'] ?? '').toString();
                    final sender = (d['senderName'] ?? '').toString();
                    final role = (d['senderRole'] ?? '').toString();
                    final uid = (d['senderUid'] ?? '').toString();

                    final isMe = uid.isNotEmpty && uid == myUid;
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
                            if (!isMe && sender.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  _roleLabel(role, sender),
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
      ),
    );
  }

  String _roleLabel(String role, String sender) {
    final r = role.toLowerCase();
    if (r == 'admin' || r == 'admin_escolar' || r == 'school_admin') return 'Admin • $sender';
    if (r == 'docente' || r == 'teacher') return 'Docente • $sender';
    if (r == 'student' || r == 'alumno' || r == 'estudiante') return 'Alumno • $sender';
    return sender;
  }
}