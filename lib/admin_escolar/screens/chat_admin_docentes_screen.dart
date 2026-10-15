// lib/admin_escolar/screens/chat_admin_docentes_screen.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/admin_escolar/widgets/admin_chat_widgets.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class ChatAdminDocentesScreen extends StatefulWidget {
  final Escuela escuela;
  final String? adminNombre;

  const ChatAdminDocentesScreen({
    super.key,
    required this.escuela,
    this.adminNombre,
  });

  @override
  State<ChatAdminDocentesScreen> createState() =>
      _ChatAdminDocentesScreenState();
}

class _ChatAdminDocentesScreenState extends State<ChatAdminDocentesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _root = 'schools';
  static const String _colTeachers = 'teachers';
  static const String _colChatsAdmin = 'chats_admin';
  static const String _threadAllTeachers = 'all_teachers';

  late final String _schoolId;

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  Color get _blue => const Color(0xFF1A237E);

  CollectionReference<Map<String, dynamic>> get _teachersCol =>
      _db.collection(_root).doc(_schoolId).collection(_colTeachers);

  CollectionReference<Map<String, dynamic>> get _chatsAdminCol =>
      _db.collection(_root).doc(_schoolId).collection(_colChatsAdmin);

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _cleanSchoolId(raw);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  String _adminDisplayName() {
    final manual = (widget.adminNombre ?? '').trim();
    if (manual.isNotEmpty) return manual;

    final u = _auth.currentUser;
    final dn = (u?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;

    final em = (u?.email ?? '').trim();
    if (em.isNotEmpty) return em;

    return 'Admin';
  }

  String _pickTeacherName(Map<String, dynamic> m, String fallbackId) {
    final v =
        (m['displayName'] ??
                m['name'] ??
                m['nombre'] ??
                m['nombres'] ??
                m['fullName'] ??
                '')
            .toString()
            .trim();
    return v.isNotEmpty ? v : fallbackId;
  }

  String _directThreadId(String teacherDocId) => 'direct_$teacherDocId';

  String _teacherStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'activo':
        return 'Cuenta activa';
      case 'pending':
      case 'pending_approval':
      case 'pendiente':
        return 'Cuenta pendiente';
      case 'blocked':
      case 'bloqueado':
        return 'Cuenta bloqueada';
      default:
        return status.isEmpty ? '' : 'Estado: $status';
    }
  }

  void _openAllTeachers() {
    _openThread(
      threadId: _threadAllTeachers,
      title: 'Todos los docentes',
      type: 'all_teachers',
      teacherDocId: null,
    );
  }

  void _openDirectTeacher(String teacherDocId, String teacherName) {
    _openThread(
      threadId: _directThreadId(teacherDocId),
      title: teacherName,
      type: 'direct_teacher',
      teacherDocId: teacherDocId,
    );
  }

  void _openThread({
    required String threadId,
    required String title,
    required String type,
    required String? teacherDocId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => _AdminChatThreadScreen(
              rootCollection: _root,
              schoolId: _schoolId,
              chatsAdminCol: _colChatsAdmin,
              threadId: threadId,
              title: title,
              threadType: type,
              teacherDocId: teacherDocId,
              senderRole: 'admin_escolar',
              senderName: _adminDisplayName(),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schoolName = (widget.escuela.nombre ?? 'Escuela').toString().trim();

    return Scaffold(
      backgroundColor: AdminChatColors.page,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        leading: const AdminBackButton(),
        title: const Text('Chat de administración'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 700 ? 14 : 24,
              ),
              children: [
                AdminChatHero(schoolName: schoolName),
                const SizedBox(height: 20),
                const Text(
                  'Chat del equipo',
                  style: TextStyle(
                    color: AdminChatColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                AdminChatConversationTile(
                  title: 'Todos los docentes',
                  isGroup: true,
                  onTap: _openAllTeachers,
                  subtitle: StreamBuilder<
                    DocumentSnapshot<Map<String, dynamic>>
                  >(
                    stream: _chatsAdminCol.doc(_threadAllTeachers).snapshots(),
                    builder: (_, snap) {
                      if (snap.hasError)
                        return const Text(
                          'No se pudo cargar el último mensaje.',
                        );
                      if (!snap.hasData)
                        return const Text('Cargando conversación…');
                      final d = snap.data?.data();
                      final last = (d?['lastMessage'] ?? '').toString().trim();
                      final who =
                          (d?['lastSenderName'] ?? '').toString().trim();
                      return Text(
                        last.isEmpty
                            ? 'Comparte el primer aviso con el equipo.'
                            : who.isEmpty
                            ? last
                            : '$who: $last',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: AdminChatColors.ink),
                  decoration: InputDecoration(
                    labelText: 'Buscar docente',
                    hintText: 'Nombre del docente',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AdminChatColors.blue,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: AdminChatColors.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: AdminChatColors.blue,
                        width: 1.4,
                      ),
                    ),
                  ),
                  onChanged:
                      (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Conversaciones privadas',
                  style: TextStyle(
                    color: AdminChatColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Selecciona un docente para abrir su conversación.',
                  style: TextStyle(
                    color: AdminChatColors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _teachersCol.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const AdminChatEmptyState(
                        title: 'No se pudieron cargar los docentes',
                        description: 'Intenta abrir el chat de nuevo.',
                        icon: Icons.cloud_off_outlined,
                      );
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AdminChatColors.blue,
                          ),
                        ),
                      );
                    }
                    final docs = snap.data!.docs;
                    final items =
                        docs.map((d) {
                          final data = d.data();
                          final id = d.id;
                          final name = _pickTeacherName(data, id);
                          final status =
                              (data['status'] ?? data['statusLower'] ?? '')
                                  .toString()
                                  .trim();
                          final gradeIds =
                              (data['gradeIds'] is List)
                                  ? (data['gradeIds'] as List)
                                      .map((e) => e.toString())
                                      .toList()
                                  : <String>[];
                          return _TeacherRow(
                            teacherDocId: id,
                            name: name,
                            status: status,
                            gradesCount: gradeIds.length,
                          );
                        }).toList();
                    items.sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
                    final filtered =
                        _search.isEmpty
                            ? items
                            : items
                                .where(
                                  (x) => x.name.toLowerCase().contains(_search),
                                )
                                .toList();
                    if (filtered.isEmpty) {
                      return AdminChatEmptyState(
                        title:
                            _search.isEmpty
                                ? 'No hay docentes para mostrar'
                                : 'No encontramos coincidencias',
                        description:
                            _search.isEmpty
                                ? 'Las conversaciones estarán disponibles cuando se registren docentes.'
                                : 'Prueba con otro nombre en la búsqueda.',
                        icon: Icons.person_search_outlined,
                      );
                    }
                    return ListView.separated(
                      itemCount: filtered.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final t = filtered[i];
                        final gradeLabel =
                            t.gradesCount > 0
                                ? '${t.gradesCount} ${t.gradesCount == 1 ? 'grado asignado' : 'grados asignados'}'
                                : 'Sin grados asignados';
                        final statusLabel = _teacherStatusLabel(t.status);
                        return AdminChatConversationTile(
                          title: t.name,
                          subtitle: Text(
                            '$gradeLabel${statusLabel.isEmpty ? '' : ' · $statusLabel'}',
                          ),
                          onTap:
                              () => _openDirectTeacher(t.teacherDocId, t.name),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherRow {
  final String teacherDocId;
  final String name;
  final String status;
  final int gradesCount;

  _TeacherRow({
    required this.teacherDocId,
    required this.name,
    required this.status,
    required this.gradesCount,
  });
}

class _AdminChatThreadScreen extends StatefulWidget {
  final String rootCollection;
  final String schoolId;
  final String chatsAdminCol;
  final String threadId;
  final String title;
  final String threadType;
  final String? teacherDocId;
  final String senderRole;
  final String senderName;

  const _AdminChatThreadScreen({
    required this.rootCollection,
    required this.schoolId,
    required this.chatsAdminCol,
    required this.threadId,
    required this.title,
    required this.threadType,
    required this.teacherDocId,
    required this.senderRole,
    required this.senderName,
  });

  @override
  State<_AdminChatThreadScreen> createState() => _AdminChatThreadScreenState();
}

class _AdminChatThreadScreenState extends State<_AdminChatThreadScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _msgCtrl = TextEditingController();
  bool _sending = false;

  Color get _blue => const Color(0xFF1A237E);

  DocumentReference<Map<String, dynamic>> get _threadRef => _db
      .collection(widget.rootCollection)
      .doc(widget.schoolId)
      .collection(widget.chatsAdminCol)
      .doc(widget.threadId);

  CollectionReference<Map<String, dynamic>> get _msgsCol =>
      _threadRef.collection('mensajes');

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureThreadExists({
    required String lastText,
    required String senderUid,
    required String senderName,
    required String senderRole,
  }) async {
    final snap = await _threadRef.get();
    if (snap.exists) return;

    final data = <String, dynamic>{
      'title':
          widget.threadType == 'all_teachers'
              ? 'Todos los docentes'
              : widget.title,
      'type': widget.threadType,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': lastText,
      'lastSenderUid': senderUid,
      'lastSenderName': senderName,
      'lastSenderRole': senderRole,
    };

    if (widget.threadType == 'direct_teacher') {
      data['teacherDocId'] = (widget.teacherDocId ?? '').trim();
    }

    await _threadRef.set(data, SetOptions(merge: false));
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
    await _sendTextMessage(text);
  }

  Future<void> _sendTextMessage(String text) async {
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final u = _auth.currentUser;
      final uid = u?.uid ?? '';
      final senderName =
          widget.senderName.trim().isEmpty ? 'Admin' : widget.senderName.trim();
      final senderRole = widget.senderRole;

      await _ensureThreadExists(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

      await _msgsCol.add({
        'type': 'text',
        'text': text,
        'senderUid': uid,
        'senderRole': senderRole,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _updateThreadMeta(
        lastText: text,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

      _msgCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error enviando: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = _safeName(
      picked.name.isEmpty ? 'imagen.jpg' : picked.name,
    );
    final lower = fileName.toLowerCase();
    await _sendMediaMessage(
      type: 'image',
      bytes: bytes,
      fileName: fileName,
      mimeType: lower.endsWith('.png') ? 'image/png' : 'image/jpeg',
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
    final fileName = _safeName(file.name);
    await _sendMediaMessage(
      type: 'file',
      bytes: bytes,
      fileName: fileName,
      mimeType:
          file.extension?.toLowerCase() == 'pdf'
              ? 'application/pdf'
              : 'application/octet-stream',
      summaryText: 'Archivo: $fileName',
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
      final u = _auth.currentUser;
      final uid = u?.uid ?? '';
      await _auth.currentUser?.getIdToken(true);
      final senderName =
          widget.senderName.trim().isEmpty ? 'Admin' : widget.senderName.trim();
      final senderRole = widget.senderRole;
      final filePath =
          'schools/${widget.schoolId}/chat_uploads/${widget.chatsAdminCol}/${widget.threadId}/$uid/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final ref = _storage.ref().child(filePath);
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: mimeType,
          customMetadata: {
            'senderUid': uid,
            'threadId': widget.threadId,
            'type': type,
          },
        ),
      );
      final mediaUrl = await ref.getDownloadURL();

      await _ensureThreadExists(
        lastText: summaryText,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );

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

      await _updateThreadMeta(
        lastText: summaryText,
        senderUid: uid,
        senderName: senderName,
        senderRole: senderRole,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error enviando adjunto: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = safeExternalDocumentUri(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  String _messageTime(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  double _imagePreviewSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 600 ? width * 0.46 : 220;
  }

  Widget _messageContent(
    BuildContext context,
    Map<String, dynamic> data,
    bool isMe,
    Color textColor,
  ) {
    final type = (data['type'] ?? 'text').toString().trim().toLowerCase();
    final text = (data['text'] ?? '').toString();
    final mediaUrl = (data['mediaUrl'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? '').toString().trim();
    final imageSize = _imagePreviewSize(context);

    if (type == 'image' && mediaUrl.isNotEmpty) {
      return Semantics(
        button: true,
        label:
            fileName.isEmpty
                ? 'Abrir imagen adjunta'
                : 'Abrir imagen adjunta: $fileName',
        excludeSemantics: true,
        onTap: () => _openUrl(mediaUrl),
        child: GestureDetector(
          onTap: () => _openUrl(mediaUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              mediaUrl,
              excludeFromSemantics: true,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    color:
                        isMe
                            ? Colors.white.withOpacity(0.12)
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isMe ? Colors.white : AdminChatColors.blue,
                  ),
                );
              },
              errorBuilder: (_, error, stackTrace) {
                debugPrint(
                  '[CHAT_ADMIN_DOCENTE][IMG_ERROR] No se pudo cargar la imagen.',
                );
                return Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    color:
                        isMe
                            ? Colors.white.withOpacity(0.12)
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: isMe ? Colors.white : AdminChatColors.blue,
                        size: 34,
                      ),
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
      );
    }

    if (type == 'file' && mediaUrl.isNotEmpty) {
      return Semantics(
        button: true,
        label:
            fileName.isEmpty
                ? 'Abrir archivo adjunto'
                : 'Abrir archivo: $fileName',
        excludeSemantics: true,
        onTap: () => _openUrl(mediaUrl),
        child: InkWell(
          onTap: () => _openUrl(mediaUrl),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  isMe ? Colors.white.withOpacity(0.12) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  color: isMe ? Colors.white : AdminChatColors.blue,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName.isEmpty ? 'Archivo adjunto' : fileName,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Text(
      text,
      style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AdminChatColors.page,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        leading: const AdminBackButton(),
        elevation: 0,
        title: Text(
          widget.threadType == 'all_teachers'
              ? 'Todos los docentes'
              : widget.title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminChatColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.threadType == 'all_teachers'
                          ? Icons.groups_outlined
                          : Icons.person_outline_rounded,
                      color: AdminChatColors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.threadType == 'all_teachers'
                            ? 'Conversación con todos los docentes de tu escuela.'
                            : 'Conversación privada entre administración y docente.',
                        style: const TextStyle(
                          color: AdminChatColors.muted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      _msgsCol
                          .orderBy('createdAt', descending: true)
                          .limit(80)
                          .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const SingleChildScrollView(
                        child: AdminChatEmptyState(
                          title: 'No se pudieron cargar los mensajes',
                          description:
                              'Intenta abrir la conversación de nuevo.',
                          icon: Icons.cloud_off_outlined,
                        ),
                      );
                    }
                    if (!snap.hasData)
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AdminChatColors.blue,
                        ),
                      );

                    final docs = snap.data!.docs;
                    if (docs.isEmpty)
                      return const Center(
                        child: SingleChildScrollView(
                          child: AdminChatEmptyState(
                            title: 'Inicia la conversación',
                            description:
                                'Escribe un mensaje o comparte un archivo con el equipo.',
                          ),
                        ),
                      );

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i].data();
                        final sender = (d['senderName'] ?? '').toString();
                        final role = (d['senderRole'] ?? '').toString();
                        final uid = (d['senderUid'] ?? '').toString();

                        final isMe = uid.isNotEmpty && uid == myUid;
                        final textColor =
                            isMe ? Colors.white : AdminChatColors.ink;
                        return AdminChatMessageBubble(
                          isMe: isMe,
                          sender:
                              role == 'docente' ? 'Docente · $sender' : sender,
                          timeLabel: _messageTime(d['createdAt']),
                          child: _messageContent(context, d, isMe, textColor),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: AdminChatComposer(
                  controller: _msgCtrl,
                  sending: _sending,
                  onSend: _send,
                  onImage: _sendImage,
                  onFile: _sendFile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
