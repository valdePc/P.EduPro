import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // para kIsWeb

class ChatGrupalScreen extends StatefulWidget {
  final String grado;

  const ChatGrupalScreen({Key? key, required this.grado}) : super(key: key);

  @override
  _ChatGrupalScreenState createState() => _ChatGrupalScreenState();
}

class _ChatGrupalScreenState extends State<ChatGrupalScreen> {
  static const Color primaryColor = Color(0xFF1A5276);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  bool _isTyping = false;
  bool _someoneTyping = false;

@override
void initState() {
  super.initState();

  // 🔒 Sólo suscribe en Android/iOS, no en web
  if (!kIsWeb) {
    FirebaseMessaging.instance.subscribeToTopic(widget.grado);
  }

  // Escucha cuando este usuario está escribiendo…
  _messageController.addListener(_onTyping);

  // …y escucha el estado de “typing” de los demás
  FirebaseFirestore.instance
    .collection('grupoChats')
    .doc(widget.grado)
    .collection('typing')
    .snapshots()
    .listen((snap) {
      final othersTyping = snap.docs.any((doc) =>
        doc.id != FirebaseAuth.instance.currentUser!.uid &&
        (doc.data()['typing'] as bool)
      );
      setState(() => _someoneTyping = othersTyping);
    });
}

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTyping() {
    final typing = _messageController.text.isNotEmpty;
    if (typing != _isTyping) {
      _isTyping = typing;
      FirebaseFirestore.instance
          .collection('grupoChats')
          .doc(widget.grado)
          .collection('typing')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({'typing': typing});
    }
  }

  Future<void> _sendMessage({String? attachmentUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && attachmentUrl == null) return;
    final now = Timestamp.now();
    await FirebaseFirestore.instance
        .collection('grupoChats')
        .doc(widget.grado)
        .collection('messages')
        .add({
      'senderId': FirebaseAuth.instance.currentUser!.uid,
      'senderName': FirebaseAuth.instance.currentUser!.displayName,
      'text': text,
      'attachment': attachmentUrl,
      'timestamp': now,
      'status': 'sent',
    });
    _messageController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      // TODO: subir a tu storage y obtener URL
      final fakeUrl = 'https://mi.storage/${result.files.single.name}';
      await _sendMessage(attachmentUrl: fakeUrl);
    }
  }

  void _showParticipants() async {
    final doc = await FirebaseFirestore.instance
        .collection('grupoChats')
        .doc(widget.grado)
        .get();
    final participants = List<String>.from(doc.data()?['participants'] ?? []);
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: participants
            .map((name) => ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(name),
                ))
            .toList(),
      ),
    );
  }

  void _reactToMessage(DocumentReference msgRef, String reaction) {
    msgRef.update({
      'reactions.${FirebaseAuth.instance.currentUser!.uid}': reaction,
    });
  }

  Future<void> _translateMessage(
      DocumentSnapshot msgDoc, String targetLang) async {
    final original = msgDoc['text'] as String;
    // TODO: llamar API de traducción
    final translated = '[Traducción de $original]';
    msgDoc.reference.update({'translations.$targetLang': translated});
  }

  String _formatTimestamp(Timestamp ts) {
    return DateFormat.Hm().format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Grupal – ${widget.grado}'),
        backgroundColor: primaryColor,
        actions: [
          IconButton(icon: const Icon(Icons.people), onPressed: _showParticipants),
          IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickAttachment),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('grupoChats')
                  .doc(widget.grado)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final msg = docs[i];
                    final isMe = msg['senderId'] == FirebaseAuth.instance.currentUser!.uid;
                    final reactions = (msg['reactions'] as Map?) ?? {};
                    final myReaction = reactions[FirebaseAuth.instance.currentUser!.uid];
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _reactToMessage(msg.reference, '👍'),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe ? primaryColor : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  msg['senderName'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              const SizedBox(height: 4),
                              if (msg['attachment'] != null)
                                Image.network(msg['attachment'], height: 150),
                              Text(
                                msg['text'] ?? '',
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTimestamp(msg['timestamp']),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isMe ? Colors.white70 : Colors.black54),
                                  ),
                                  if (myReaction != null) ...[
                                    const SizedBox(width: 6),
                                    Text(myReaction,
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                  IconButton(
                                    icon: const Icon(Icons.translate, size: 16),
                                    color: isMe ? Colors.white70 : Colors.black54,
                                    onPressed: () => _translateMessage(msg, 'en'),
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
            ),
          ),

          if (_someoneTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Alguien está escribiendo…',
                    style: TextStyle(color: primaryColor, fontStyle: FontStyle.italic)),
              ),
            ),

          // Input y botón enviar
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: primaryColor,
                  onPressed: () => _sendMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
