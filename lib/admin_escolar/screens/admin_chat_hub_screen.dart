import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'admin_chat_room_screen.dart';

const Color _blue = Color(0xFF0D47A1);
const Color _orange = Color(0xFFFFA000);

class AdminChatHubScreen extends StatefulWidget {
  final Escuela escuela;
  const AdminChatHubScreen({super.key, required this.escuela});

  @override
  State<AdminChatHubScreen> createState() => _AdminChatHubScreenState();
}

class _AdminChatHubScreenState extends State<AdminChatHubScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final String _schoolId;

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('No hay usuario autenticado (FirebaseAuth).');
    }
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _conversationsCol => _db
      .collection('escuelas')
      .doc(_schoolId)
      .collection('conversations');

  // ⚠️ CAMBIA AQUÍ si tu colección real es "docentes" en vez de "maestros"
  CollectionReference<Map<String, dynamic>> get _teachersCol => _db
      .collection('escuelas')
      .doc(_schoolId)
      .collection('maestros');

  Stream<QuerySnapshot<Map<String, dynamic>>> get _adminConversationsStream =>
      _conversationsCol
          .where('visibilityRoles', arrayContains: 'admin')
          .orderBy('updatedAt', descending: true)
          .snapshots();

  Future<void> _openConversation({
    required DocumentReference<Map<String, dynamic>> ref,
    required String title,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminChatRoomScreen(
          escuela: widget.escuela,
          conversationRef: ref,
          title: title,
        ),
      ),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> _ensureAllTeachersChannel() async {
    final ref = _conversationsCol.doc('all_teachers');
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'schoolId': _schoolId,
        'type': 'all_teachers',
        'title': 'Todos los docentes',
        'visibilityRoles': ['admin', 'teacher'],
        'participants': <String>[], // opcional para este canal
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageAt': null,
        'locked': false, // si luego quieres "solo admins", pon true y valida del lado docente
      }, SetOptions(merge: true));
    }

    return ref;
  }

  String _directId(String a, String b) {
    final pair = [a, b]..sort();
    return 'direct_${pair.join("_")}';
  }

  Future<DocumentReference<Map<String, dynamic>>> _ensureDirectWithTeacher({
    required String teacherUid,
    required String teacherName,
  }) async {
    final id = _directId(_uid, teacherUid);
    final ref = _conversationsCol.doc(id);

    await ref.set({
      'schoolId': _schoolId,
      'type': 'direct_admin_teacher',
      'title': teacherName.trim().isEmpty ? 'Docente' : teacherName.trim(),
      'visibilityRoles': ['admin', 'teacher'],
      'participants': [_uid, teacherUid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'lastMessageAt': null,
      'locked': false,
      'meta': {
        'adminUid': _uid,
        'teacherUid': teacherUid,
      }
    }, SetOptions(merge: true));

    return ref;
  }

  Future<DocumentReference<Map<String, dynamic>>> _createSelectedTeachersGroup({
    required List<_TeacherPick> teachers,
  }) async {
    final ref = _conversationsCol.doc();

    final participants = <String>{_uid, ...teachers.map((t) => t.uid)}.toList();
    final title = teachers.length == 1
        ? 'Grupo: ${teachers.first.name}'
        : 'Grupo (${teachers.length})';

    await ref.set({
      'schoolId': _schoolId,
      'type': 'staff_group',
      'title': title,
      'visibilityRoles': ['admin', 'teacher'],
      'participants': participants,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'lastMessageAt': null,
      'locked': false,
      'meta': {
        'createdBy': _uid,
        'teacherUids': teachers.map((e) => e.uid).toList(),
        'teacherNames': teachers.map((e) => e.name).toList(),
      }
    });

    return ref;
  }

  Future<List<_TeacherPick>> _pickTeachers({required bool multi}) async {
    final res = await showDialog<List<_TeacherPick>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TeacherPickerDialog(
        teachersCol: _teachersCol,
        multi: multi,
      ),
    );
    return res ?? <_TeacherPick>[];
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
          'Mensajes • $nombreEscuela',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardShell(
            title: 'Chat de administración',
            subtitle:
                'Canales para comunicarte con docentes: todos, uno a uno, o grupos seleccionados.',
            icon: const Icon(Icons.admin_panel_settings, color: _orange),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.groups),
                  label: const Text('Todos los docentes'),
                  onPressed: () async {
                    final ref = await _ensureAllTeachersChannel();
                    await _openConversation(ref: ref, title: 'Todos los docentes');
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.person),
                  label: const Text('A un docente'),
                  onPressed: () async {
                    final picked = await _pickTeachers(multi: false);
                    if (picked.isEmpty) return;
                    final t = picked.first;
                    final ref = await _ensureDirectWithTeacher(
                      teacherUid: t.uid,
                      teacherName: t.name,
                    );
                    await _openConversation(ref: ref, title: t.name);
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.group_add),
                  label: const Text('Grupo (seleccionar)'),
                  onPressed: () async {
                    final picked = await _pickTeachers(multi: true);
                    if (picked.isEmpty) return;
                    final ref = await _createSelectedTeachersGroup(teachers: picked);
                    await _openConversation(ref: ref, title: 'Grupo (${picked.length})');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _CardShell(
            title: 'Conversaciones recientes',
            subtitle: 'Entradas visibles para administración (ordenadas por actividad).',
            icon: const Icon(Icons.chat_bubble_outline, color: _orange),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _adminConversationsStream,
              builder: (context, snap) {
                if (snap.hasError) return Text('Error: ${snap.error}');
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Aún no hay conversaciones.'),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final title = (data['title'] ?? 'Chat').toString();
                      final type = (data['type'] ?? '').toString();
                      final last = (data['lastMessage'] ?? '').toString();
                      final ts = data['lastMessageAt'];
                      final when = (ts is Timestamp) ? ts.toDate() : null;

                      final tag = switch (type) {
                        'all_teachers' => 'Canal',
                        'direct_admin_teacher' => 'Directo',
                        'staff_group' => 'Grupo',
                        _ => 'Chat',
                      };

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _orange.withOpacity(0.12),
                          child: const Icon(Icons.forum, color: _orange),
                        ),
                        title: Text(title, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          last.isEmpty
                              ? 'Sin mensajes aún • $tag'
                              : '$last • $tag',
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          when == null ? '' : _fmtTime(when),
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                        onTap: () => _openConversation(ref: d.reference, title: title),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtTime(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

class _TeacherPick {
  final String uid;
  final String name;
  const _TeacherPick({required this.uid, required this.name});
}

class _TeacherPickerDialog extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> teachersCol;
  final bool multi;

  const _TeacherPickerDialog({
    required this.teachersCol,
    required this.multi,
  });

  @override
  State<_TeacherPickerDialog> createState() => _TeacherPickerDialogState();
}

class _TeacherPickerDialogState extends State<_TeacherPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  final Map<String, _TeacherPick> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.multi ? 'Selecciona docentes' : 'Selecciona un docente'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar docente',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.teachersCol.orderBy('nombre').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return Text('Error: ${snap.error}');
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;

                  final items = docs.map((d) {
                    final data = d.data();
                    final uid = (data['uid'] ?? d.id).toString();
                    final name = (data['nombre'] ??
                            data['name'] ??
                            data['fullName'] ??
                            data['displayName'] ??
                            'Docente')
                        .toString()
                        .trim();

                    return _TeacherPick(uid: uid, name: name.isEmpty ? 'Docente' : name);
                  }).toList();

                  final filtered = _q.isEmpty
                      ? items
                      : items.where((t) => t.name.toLowerCase().contains(_q)).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No hay docentes para mostrar.'));
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = filtered[i];
                      final isSel = _selected.containsKey(t.uid);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _blue.withOpacity(0.08),
                          child: const Icon(Icons.person, color: _blue),
                        ),
                        title: Text(t.name, overflow: TextOverflow.ellipsis),
                        trailing: widget.multi
                            ? Checkbox(
                                value: isSel,
                                onChanged: (_) {
                                  setState(() {
                                    if (isSel) {
                                      _selected.remove(t.uid);
                                    } else {
                                      _selected[t.uid] = t;
                                    }
                                  });
                                },
                              )
                            : Radio<bool>(
                                value: true,
                                groupValue: isSel,
                                onChanged: (_) {
                                  setState(() {
                                    _selected
                                      ..clear()
                                      ..[t.uid] = t;
                                  });
                                },
                              ),
                        onTap: () {
                          setState(() {
                            if (widget.multi) {
                              if (isSel) {
                                _selected.remove(t.uid);
                              } else {
                                _selected[t.uid] = t;
                              }
                            } else {
                              _selected
                                ..clear()
                                ..[t.uid] = t;
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, <_TeacherPick>[]),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _blue),
          onPressed: () {
            final list = _selected.values.toList();
            if (!widget.multi && list.isEmpty) return;
            Navigator.pop(context, list);
          },
          child: const Text('Continuar'),
        ),
      ],
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
