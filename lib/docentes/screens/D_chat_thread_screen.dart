import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';
import 'dart:typed_data';

import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class DChatThreadScreen extends StatefulWidget {
  final Escuela escuela;

  /// Colección del thread: 'chats_admin' o 'chats_aulas'
  final String threadCollection;

  final String threadId;
  final String threadTitle;

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
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

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
    await _sendTextMessage(text);
  }

  Future<void> _sendTextMessage(String text) async {
    if (_sending) return;

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

  String _safeName(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final name = _safeName(picked.name.isEmpty ? 'imagen.jpg' : picked.name);
    final ext = name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    await _sendMediaMessage(
      type: 'image',
      bytes: bytes,
      fileName: name,
      mimeType: ext == 'png' ? 'image/png' : 'image/jpeg',
      summaryText: 'Imagen',
    );
  }

  Future<void> _sendFile() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final name = _safeName(file.name);
    await _sendMediaMessage(
      type: 'file',
      bytes: bytes,
      fileName: name,
      mimeType: 'application/octet-stream',
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
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final filePath =
          'schools/$_schoolId/chat_uploads/${widget.threadCollection}/${widget.threadId}/${widget.senderId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final ref = _storage.ref().child(filePath);
      await ref.putData(bytes, SettableMetadata(contentType: mimeType));
      final mediaUrl = await ref.getDownloadURL();

      final msgRef = _msgsCol.doc();
      final batch = _db.batch();
      batch.set(msgRef, {
        'type': type,
        'text': '',
        'mediaUrl': mediaUrl,
        'fileName': fileName,
        'fileSize': bytes.length,
        'mimeType': mimeType,
        'senderRole': widget.senderRole,
        'senderId': widget.senderId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_threadRef, {
        'lastMessage': summaryText,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando adjunto: $e')),
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

  Widget _messageContent(Map<String, dynamic> data, bool mine) {
    final type = (data['type'] ?? 'text').toString().trim().toLowerCase();
    final text = (data['text'] ?? '').toString();
    final mediaUrl = (data['mediaUrl'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? '').toString().trim();

    if (type == 'image' && mediaUrl.isNotEmpty) {
      return GestureDetector(
        onTap: () => _openUrl(mediaUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            mediaUrl,
            semanticLabel: fileName.isEmpty ? 'Imagen adjunta' : 'Imagen adjunta: $fileName',
            width: 220,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 220,
              height: 120,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    }

    if (type == 'file' && mediaUrl.isNotEmpty) {
      return InkWell(
        onTap: () => _openUrl(mediaUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file_rounded, color: mine ? Colors.white : _orange),
            const SizedBox(width: 8),
            Flexible(child: Text(fileName.isEmpty ? 'Archivo adjunto' : fileName)),
          ],
        ),
      );
    }

    return Text(
      text,
      style: TextStyle(
        color: mine ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: buildDocenteBackAppBar(context),
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
                        constraints: const BoxConstraints(maxWidth: 360),
                        decoration: BoxDecoration(
                          color: mine ? _blue : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: mine ? _blue : Colors.grey.shade300),
                        ),
                        child: _messageContent(data, mine),
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
                      PopupMenuItem(value: 'image', child: Text('Imagen')),
                      PopupMenuItem(value: 'file', child: Text('Archivo')),
                    ],
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Icon(Icons.add_rounded, color: _blue),
                    ),
                  ),
                  const SizedBox(width: 10),
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
