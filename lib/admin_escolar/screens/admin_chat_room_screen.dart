import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

const Color _blue = Color(0xFF0D47A1);
const Color _orange = Color(0xFFFFA000);

class AdminChatRoomScreen extends StatefulWidget {
  final Escuela escuela;
  final DocumentReference<Map<String, dynamic>> conversationRef;
  final String title;

  const AdminChatRoomScreen({
    super.key,
    required this.escuela,
    required this.conversationRef,
    required this.title,
  });

  @override
  State<AdminChatRoomScreen> createState() => _AdminChatRoomScreenState();
}

class _AdminChatRoomScreenState extends State<AdminChatRoomScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final String _schoolId;

  final _msgCtrl = TextEditingController();
  bool _sending = false;

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

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('No hay usuario autenticado.');
    return u.uid;
  }

  String _clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  CollectionReference<Map<String, dynamic>> get _messagesCol =>
      widget.conversationRef.collection('messages');

  Stream<QuerySnapshot<Map<String, dynamic>>> get _messagesStream => _messagesCol
      .orderBy('createdAt', descending: true)
      .limit(250)
      .snapshots();

  Future<void> _send() async {
    final text = _clean(_msgCtrl.text);
    if (text.isEmpty) return;

    // anti “novela”
    if (text.length > 1200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje muy largo (máximo 1200 caracteres).')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final msgRef = _messagesCol.doc();
      final batch = _db.batch();

      batch.set(msgRef, {
        'text': text,
        'senderId': _uid,
        'senderRole': 'admin',
        'senderName': 'Administración',
        'createdAt': FieldValue.serverTimestamp(),
        'schoolId': _schoolId,
      });

      batch.set(widget.conversationRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

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
    final nombreEscuela = (widget.escuela.nombre ?? '—').trim().isEmpty
        ? '—'
        : widget.escuela.nombre!.trim();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(
          '${widget.title} • $nombreEscuela',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Info',
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              final snap = await widget.conversationRef.get();
              final data = snap.data() ?? {};
              final type = (data['type'] ?? '').toString();
              final locked = (data['locked'] is bool) ? data['locked'] as bool : false;

              if (!mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Detalles'),
                  content: Text('Tipo: $type\nBloqueado: $locked'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF6F7FB),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snap) {
                if (snap.hasError) return Text('Error: ${snap.error}');
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Sin mensajes aún.'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();

                    final text = (m['text'] ?? '').toString();
                    final senderId = (m['senderId'] ?? '').toString();
                    final senderName = (m['senderName'] ?? '').toString();
                    final isMine = senderId == _uid;

                    final ts = m['createdAt'];
                    final when = (ts is Timestamp) ? ts.toDate() : null;

                    return _MessageBubble(
                      isMine: isMine,
                      text: text,
                      senderName: senderName,
                      time: when,
                    );
                  },
                );
              },
            ),
          ),

          // Composer
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _sending ? null : _send,
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

class _MessageBubble extends StatelessWidget {
  final bool isMine;
  final String text;
  final String senderName;
  final DateTime? time;

  const _MessageBubble({
    required this.isMine,
    required this.text,
    required this.senderName,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine ? _blue : Colors.white;
    final textColor = isMine ? Colors.white : Colors.black87;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                senderName.isEmpty ? 'Docente' : senderName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 540),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(text, style: TextStyle(color: textColor, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                    time == null ? '' : _fmt(time!),
                    style: TextStyle(
                      color: isMine ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 11,
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

String _fmt(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
