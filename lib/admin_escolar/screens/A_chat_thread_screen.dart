import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AChatThreadScreen extends StatefulWidget {
  final Escuela escuela;
  final String threadId;
  final String threadTitle;

  /// true = admin escolar / admin general
  /// false = docente (si luego reutilizas este screen para el lado docente)
  final bool isAdmin;

  /// Opcional: nombre para mostrar del que envía (admin o docente).
  final String? senderName;

  const AChatThreadScreen({
    super.key,
    required this.escuela,
    required this.threadId,
    required this.threadTitle,
    this.isAdmin = true,
    this.senderName,
  });

  @override
  State<AChatThreadScreen> createState() => _AChatThreadScreenState();
}

class _AChatThreadScreenState extends State<AChatThreadScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final String _schoolId;

  final _msgCtrl = TextEditingController();
  bool _sending = false;

  // ✅ Unifica con tu estructura real (recomendado: "schools")
  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('chats_admin')
      .doc(widget.threadId);

  // ✅ Unifica el nombre con el otro chat (recomendado: "mensajes")
  CollectionReference<Map<String, dynamic>> get _msgsCol => _threadRef.collection('mensajes');

  String _ensureSchoolDocId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    return id.startsWith('eduproapp_admin_') ? id : 'eduproapp_admin_$id';
  }

  String _inferThreadType() {
    if (widget.threadId == 'all_teachers') return 'all_teachers';
    if (widget.threadId.startsWith('direct_')) return 'direct_teacher';
    return 'group_teachers';
  }

  String get _senderRole => widget.isAdmin ? 'admin_escolar' : 'docente';

  String get _senderName {
    final raw = (widget.senderName ??
            (widget.isAdmin ? 'Administración' : 'Docente'))
        .trim();
    return raw.isEmpty ? (widget.isAdmin ? 'Administración' : 'Docente') : raw;
  }

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _ensureSchoolDocId(raw);

    // ✅ Asegura que el thread exista (evita fallos si alguien entra directo)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureThreadDoc();
    });
  }

  Future<void> _ensureThreadDoc() async {
    try {
      final snap = await _threadRef.get();
      if (snap.exists) return;

      await _threadRef.set({
        'title': widget.threadTitle,
        'type': _inferThreadType(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastSenderUid': null,
        'lastSenderName': null,
        'lastSenderRole': null,
      }, SetOptions(merge: true));
    } catch (_) {
      // silencioso: si rules no permiten crear aquí, igual funcionará cuando el admin lo cree desde el selector
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sesión activa.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      _msgCtrl.clear();

      final msgRef = _msgsCol.doc();
      final batch = _db.batch();

      // ✅ Mensaje (doc)
      batch.set(msgRef, {
        'text': text,
        'senderUid': uid,
        'senderRole': _senderRole,
        'senderName': _senderName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ✅ Resumen del thread (para "recientes")
      batch.set(_threadRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
        'lastSenderUid': uid,
        'lastSenderName': _senderName,
        'lastSenderRole': _senderRole,
      }, SetOptions(merge: true));

      await batch.commit();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(widget.threadTitle, overflow: TextOverflow.ellipsis),
        backgroundColor: _blue,
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
                if (docs.isEmpty) return const Center(child: Text('Aún no hay mensajes.'));

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data();

                    final text = (data['text'] ?? '').toString();
                    final senderUid = (data['senderUid'] ?? '').toString();
                    final senderName = (data['senderName'] ?? '').toString();
                    final mine = senderUid.isNotEmpty && senderUid == myUid;

                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: mine ? _blue : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: mine ? _blue : Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!mine && senderName.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: _orange,
                                  ),
                                ),
                              ),
                            Text(
                              text,
                              style: TextStyle(
                                color: mine ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
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
                    width: 52,
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      style: FilledButton.styleFrom(backgroundColor: _orange),
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
