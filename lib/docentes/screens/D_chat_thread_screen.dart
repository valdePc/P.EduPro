import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class DChatThreadScreen extends StatefulWidget {
  final Escuela escuela;

  /// Colección del thread: 'chats_admin' o 'chats_aulas'
  final String threadCollection;

  final String threadId;
  final String threadTitle;

  /// 'docente' (por ahora). Luego haremos 'admin' y 'alumno'.
  final String senderRole;
  final String senderId;

  const DChatThreadScreen({
    super.key,
    required this.escuela,
    required this.threadCollection,
    required this.threadId,
    required this.threadTitle,
    required this.senderRole,
    required this.senderId,
  });

  @override
  State<DChatThreadScreen> createState() => _DChatThreadScreenState();
}

class _DChatThreadScreenState extends State<DChatThreadScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final String _schoolId;
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection('escuelas')
      .doc(_schoolId)
      .collection(widget.threadCollection)
      .doc(widget.threadId);

  CollectionReference<Map<String, dynamic>> get _msgsCol =>
      _threadRef.collection('messages');

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      _msgCtrl.clear();

      final msgRef = _msgsCol.doc();
      final batch = _db.batch();

      batch.set(msgRef, {
        'text': text,
        'senderRole': widget.senderRole,
        'senderId': widget.senderId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(_threadRef, {
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
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
              stream: _msgsCol
                  .orderBy('createdAt', descending: true)
                  .limit(80)
                  .snapshots(),
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
                    final role = (data['senderRole'] ?? '').toString();
                    final senderId = (data['senderId'] ?? '').toString();

                    final mine =
                        role == widget.senderRole && senderId == widget.senderId;

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
                        child: Text(
                          text,
                          style: TextStyle(
                            color: mine ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
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
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
