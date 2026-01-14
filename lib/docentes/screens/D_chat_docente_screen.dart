// lib/docentes/screens/d_chat_docente_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  CollectionReference<Map<String, dynamic>> get _gradosCol =>
      _db.collection('escuelas').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _threadsCol =>
      _db.collection('escuelas').doc(_schoolId).collection('chat_grados');

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _blue => const Color(0xFF0D47A1);
  Color get _orange => const Color(0xFFFFA000);

  void _openThread({
    required String gradoId,
    required String gradoName,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DChatGradoThreadScreen(
          escuela: widget.escuela,
          schoolId: _schoolId,
          gradoId: gradoId,
          gradoName: gradoName,
          docenteNombre: widget.docenteNombre,
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text('Chat docente • $nombreEscuela', overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
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
                  'Comunicación por aula (grado). Nada de chats 1 a 1 con alumnos aquí.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
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
                  labelText: 'Buscar grado (ej: 3ro, Inicial, 6to...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              ),
            ),

          const SizedBox(height: 14),

          // Lista principal
          if (_mode == DocenteChatMode.recientes)
            _RecentThreadsList(
              threadsCol: _threadsCol,
              blue: _blue,
              orange: _orange,
              onOpen: (gradoId, gradoName) => _openThread(gradoId: gradoId, gradoName: gradoName),
            )
          else
            _GradesList(
              gradosCol: _gradosCol,
              blue: _blue,
              orange: _orange,
              search: _mode == DocenteChatMode.buscar ? _search : '',
              onOpen: (gradoId, gradoName) => _openThread(gradoId: gradoId, gradoName: gradoName),
            ),
        ],
      ),
    );
  }
}

class _GradesList extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> gradosCol;
  final Color blue;
  final Color orange;
  final String search;
  final void Function(String gradoId, String gradoName) onOpen;

  const _GradesList({
    required this.gradosCol,
    required this.blue,
    required this.orange,
    required this.search,
    required this.onOpen,
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
          final items = docs.map((d) {
            final name = (d.data()['name'] ?? '').toString().trim();
            return {'id': d.id, 'name': name};
          }).where((x) => (x['name'] as String).isNotEmpty).toList();

          items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

          final filtered = search.isEmpty
              ? items
              : items.where((x) => (x['name'] as String).toLowerCase().contains(search)).toList();

          if (filtered.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No se encontraron grados.'),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grupos por grado',
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
              ),
              const SizedBox(height: 10),
              ListView.separated(
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
                    subtitle: const Text('Chat grupal del aula'),
                    trailing: TextButton.icon(
                      onPressed: () => onOpen(gradoId, gradoName),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Abrir'),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentThreadsList extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> threadsCol;
  final Color blue;
  final Color orange;
  final void Function(String gradoId, String gradoName) onOpen;

  const _RecentThreadsList({
    required this.threadsCol,
    required this.blue,
    required this.orange,
    required this.onOpen,
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
        stream: threadsCol.orderBy('updatedAt', descending: true).limit(20).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Text('Error: ${snap.error}');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(10),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Todavía no hay conversaciones recientes.'),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Conversaciones recientes',
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
              ),
              const SizedBox(height: 10),
              ListView.separated(
                itemCount: docs.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data();

                  final gradoId = d.id;
                  final gradoName = (data['gradoName'] ?? 'Grado').toString();
                  final last = (data['lastMessage'] ?? '').toString();
                  final who = (data['lastSenderName'] ?? '').toString();

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
                },
              ),
            ],
          );
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

  const _DChatGradoThreadScreen({
    required this.escuela,
    required this.schoolId,
    required this.gradoId,
    required this.gradoName,
    this.docenteNombre,
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
      .collection('escuelas')
      .doc(widget.schoolId)
      .collection('chat_grados')
      .doc(widget.gradoId);

  CollectionReference<Map<String, dynamic>> get _msgsCol =>
      _threadRef.collection('mensajes');

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final senderName = (widget.docenteNombre ?? 'Docente').trim().isEmpty
          ? 'Docente'
          : widget.docenteNombre!.trim();

      await _msgsCol.add({
        'text': text,
        'senderRole': 'docente',
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _threadRef.set({
        'gradoId': widget.gradoId,
        'gradoName': widget.gradoName,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
        'lastSenderName': senderName,
        'lastSenderRole': 'docente',
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(widget.gradoName, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgsCol.orderBy('createdAt', descending: true).limit(60).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No hay mensajes aún. Escribe el primero.'),
                  );
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

                    final isMe = role == 'docente'; // MVP: aquí asumimos docente como emisor
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
                                  sender,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
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

          // Input
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
