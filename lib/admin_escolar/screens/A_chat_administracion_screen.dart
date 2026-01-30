import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'A_chat_thread_screen.dart';

enum AdminChatMode { todosDocentes, unDocente, grupoSeleccionado }

class AChatAdministracionScreen extends StatefulWidget {
  final Escuela escuela;
  final AdminChatMode? initialMode;

  const AChatAdministracionScreen({
    super.key,
    required this.escuela,
    this.initialMode,
  });

  @override
  State<AChatAdministracionScreen> createState() => _AChatAdministracionScreenState();
}

class _AChatAdministracionScreenState extends State<AChatAdministracionScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final String _schoolId;
  late AdminChatMode _mode;

  String _ensureSchoolDocId(String rawId) {
    final id = rawId.trim();
    if (id.isEmpty) return id;
    return id.startsWith('eduproapp_admin_') ? id : 'eduproapp_admin_$id';
  }

  CollectionReference<Map<String, dynamic>> get _threadsCol => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('chats_admin');

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = _ensureSchoolDocId(raw);
    _mode = widget.initialMode ?? AdminChatMode.todosDocentes;
  }

  Future<void> _openThread({
    required String threadId,
    required String title,
    required String type,
  }) async {
    await _threadsCol.doc(threadId).set({
      'title': title,
      'type': type,
      'lastMessage': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AChatThreadScreen(
          escuela: widget.escuela,
          threadId: threadId,
          threadTitle: title,
          isAdmin: true,
          senderName: 'Administración',
        ),
      ),
    );
  }

  Future<void> _openAllTeachers() async {
    await _openThread(
      threadId: 'all_teachers',
      title: 'Todos los docentes',
      type: 'all_teachers',
    );
  }

  Future<void> _openOneTeacher() async {
    final picked = await _pickTeachers(single: true);
    if (picked == null || picked.isEmpty) return;

    final t = picked.first;
    await _openThread(
      threadId: 'direct_${t.id}', // 👈 t.id = docId del teacher
      title: t.name,
      type: 'direct_teacher',
    );
  }

  Future<void> _openGroupTeachers() async {
    final picked = await _pickTeachers(single: false);
    if (picked == null || picked.isEmpty) return;

    final doc = _threadsCol.doc();
    final names = picked.map((e) => e.name).take(3).join(', ');
    final title = picked.length <= 3 ? 'Grupo: $names' : 'Grupo: $names…';

    await doc.set({
      'title': title,
      'type': 'group_teachers',
      'teacherIds': picked.map((e) => e.id).toList(),
      'lastMessage': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AChatThreadScreen(
          escuela: widget.escuela,
          threadId: doc.id,
          threadTitle: title,
          isAdmin: true,
          senderName: 'Administración',
        ),
      ),
    );
  }

  Future<List<_TeacherPick>?> _pickTeachers({required bool single}) async {
    // ✅ docentes en schools/{schoolId}/teachers
    final col = _db.collection('schools').doc(_schoolId).collection('teachers');

    // ✅ sin orderBy para evitar líos si el campo no está en todos
    final snap = await col.limit(250).get();

    final items = snap.docs.map((d) {
      final data = d.data();

      final nombre = (data['nombre'] ??
              data['nombres'] ??
              data['displayName'] ??
              data['name'] ??
              '')
          .toString()
          .trim();

      final apellidos = (data['apellido'] ?? data['apellidos'] ?? '')
          .toString()
          .trim();

      final full = ('$nombre $apellidos').trim();
      return _TeacherPick(id: d.id, name: full.isEmpty ? 'Docente (${d.id})' : full);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!mounted) return null;

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay docentes para seleccionar todavía.')),
      );
      return null;
    }

    return showModalBottomSheet<List<_TeacherPick>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TeacherPickerSheet(items: items, single: single),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (widget.escuela.nombre ?? '—').trim().isEmpty
        ? '—'
        : widget.escuela.nombre!.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text('Mensajes • $nombre', overflow: TextOverflow.ellipsis),
        backgroundColor: _blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardShell(
            title: 'Chat de administración',
            subtitle:
                'Canales para comunicarte con docentes: todos, uno a uno, o grupos seleccionados.',
            icon: const Icon(Icons.chat_bubble_outline, color: _orange),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ModeButton(
                  selected: _mode == AdminChatMode.todosDocentes,
                  icon: Icons.groups,
                  label: 'Todos los docentes',
                  onTap: () async {
                    setState(() => _mode = AdminChatMode.todosDocentes);
                    await _openAllTeachers();
                  },
                ),
                _ModeButton(
                  selected: _mode == AdminChatMode.unDocente,
                  icon: Icons.person,
                  label: 'A un docente',
                  onTap: () async {
                    setState(() => _mode = AdminChatMode.unDocente);
                    await _openOneTeacher();
                  },
                ),
                _ModeButton(
                  selected: _mode == AdminChatMode.grupoSeleccionado,
                  icon: Icons.group_add,
                  label: 'Grupo (seleccionar)',
                  onTap: () async {
                    setState(() => _mode = AdminChatMode.grupoSeleccionado);
                    await _openGroupTeachers();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CardShell(
            title: 'Conversaciones recientes',
            subtitle: 'Entradas visibles para administración (ordenadas por actividad).',
            icon: const Icon(Icons.forum_outlined, color: _orange),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _threadsCol.orderBy('updatedAt', descending: true).limit(20).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Text('Error: ${snap.error}');
                if (!snap.hasData) return const LinearProgressIndicator();

                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Text('Aún no hay conversaciones.');

                return Column(
                  children: docs.map((d) {
                    final data = d.data();
                    final title = (data['title'] ?? 'Conversación').toString();
                    final last = (data['lastMessage'] ?? '').toString();

                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _orange.withOpacity(0.12),
                            child: const Icon(Icons.chat, color: _orange),
                          ),
                          title: Text(title, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            last.isEmpty ? 'Sin mensajes todavía' : last,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AChatThreadScreen(
                                    escuela: widget.escuela,
                                    threadId: d.id,
                                    threadTitle: title,
                                    isAdmin: true,
                                    senderName: 'Administración',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Abrir'),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- lo demás igual ---
class _TeacherPick {
  final String id;
  final String name;
  const _TeacherPick({required this.id, required this.name});
}

class _ModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _blue : Colors.white;
    final fg = selected ? Colors.white : _blue;
    final border = selected ? _blue : Colors.grey.shade300;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? _orange : _blue),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
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
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TeacherPickerSheet extends StatefulWidget {
  final List<_TeacherPick> items;
  final bool single;

  const _TeacherPickerSheet({required this.items, required this.single});

  @override
  State<_TeacherPickerSheet> createState() => _TeacherPickerSheetState();
}

class _TeacherPickerSheetState extends State<_TeacherPickerSheet> {
  final _search = TextEditingController();
  final Set<String> _selected = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items.where((e) => e.name.toLowerCase().contains(q)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Buscar docente',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = filtered[i];
                  final checked = _selected.contains(t.id);

                  return ListTile(
                    title: Text(t.name, overflow: TextOverflow.ellipsis),
                    trailing: widget.single
                        ? const Icon(Icons.chevron_right)
                        : Checkbox(
                            value: checked,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(t.id);
                                } else {
                                  _selected.remove(t.id);
                                }
                              });
                            },
                          ),
                    onTap: () {
                      if (widget.single) {
                        Navigator.pop(context, <_TeacherPick>[t]);
                      } else {
                        setState(() {
                          if (checked) {
                            _selected.remove(t.id);
                          } else {
                            _selected.add(t.id);
                          }
                        });
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (!widget.single)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final picks = widget.items.where((e) => _selected.contains(e.id)).toList();
                          Navigator.pop(context, picks);
                        },
                  child: Text('Seleccionar (${_selected.length})'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
class AdminRecentThreadsPreview extends StatelessWidget {
  final Escuela escuela;
  final int maxItems;

  const AdminRecentThreadsPreview({
    super.key,
    required this.escuela,
    this.maxItems = 3,
  });

  static const _orange = Color(0xFFFFA000);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final schoolId = normalizeSchoolIdFromEscuela(escuela);
    final threadsCol = db.collection('escuelas').doc(schoolId).collection('chats_admin');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: threadsCol.orderBy('updatedAt', descending: true).limit(maxItems).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error cargando chat: ${snap.error}');
        if (!snap.hasData) return const LinearProgressIndicator();

        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Text('Aún no hay conversaciones recientes.');

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final title = (data['title'] ?? 'Conversación').toString();
            final last = (data['lastMessage'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _orange.withOpacity(0.12),
                  child: const Icon(Icons.forum, color: _orange),
                ),
                title: Text(title, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  last.isEmpty ? 'Sin mensajes todavía' : last,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
