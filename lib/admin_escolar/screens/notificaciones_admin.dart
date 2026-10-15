// lib/admin_escolar/screens/notificaciones_admin.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/admin_escolar/widgets/admin_notification_widgets.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class NotificacionesAdminScreen extends StatefulWidget {
  final Escuela escuela;
  final VoidCallback? onBack;

  const NotificacionesAdminScreen({
    super.key,
    required this.escuela,
    this.onBack,
  });

  @override
  State<NotificacionesAdminScreen> createState() =>
      _NotificacionesAdminScreenState();
}

enum _SendMode { all, grade, teacher }

class _TeacherOption {
  final String teacherDocId;
  final String name;
  final String? emailLower;
  const _TeacherOption({
    required this.teacherDocId,
    required this.name,
    this.emailLower,
  });
}

class _GradeOption {
  final String gradeId;
  final String name;
  const _GradeOption({required this.gradeId, required this.name});
}

class _NotificacionesAdminScreenState extends State<NotificacionesAdminScreen> {
  static const Color _blue = Color(0xFF1A237E);
  static const Color _orange = AdminNotificationColors.amberInk;
  static const Color _bg = AdminNotificationColors.page;
  static const int _dailyNotificationLimit = 20;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolId;

  // Contenido
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();

  // (Legacy / fallback) – no lo rompemos, pero ya no lo pedimos al usuario
  final TextEditingController _teacherDocIdCtrl = TextEditingController();
  final TextEditingController _gradeIdCtrl = TextEditingController();

  // Buscadores UI
  final TextEditingController _teacherSearchCtrl = TextEditingController();
  final TextEditingController _gradeSearchCtrl = TextEditingController();

  bool _sending = false;

  // Modo envío
  _SendMode _mode = _SendMode.all;

  // Incluir
  bool _includeTeachers = true;
  bool _includeStudents = false;

  // Selecciones
  final Set<String> _selectedGradeIds = <String>{};
  final Set<String> _selectedTeacherIds = <String>{};

  // Historial: docentes / alumnos
  String _historyView = 'docentes'; // docentes | alumnos | ambos

  // Mantener estructura "channels" sin obligar UI (no rompe lectores existentes)
  static const List<String> _channels = ['Email', 'Push', 'SMS'];
  final Map<String, bool> _sendChannels = {
    'Email': false,
    'Push': true,
    'SMS': false,
  };

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _schoolId = raw.replaceAll('/', '_');

    _teacherSearchCtrl.addListener(() => setState(() {}));
    _gradeSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _teacherDocIdCtrl.dispose();
    _gradeIdCtrl.dispose();
    _teacherSearchCtrl.dispose();
    _gradeSearchCtrl.dispose();
    super.dispose();
  }

  String get _adminUid => _auth.currentUser?.uid ?? '';

  String _adminName() {
    final u = _auth.currentUser;
    final dn = (u?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final em = (u?.email ?? '').trim();
    if (em.isNotEmpty) return em;
    return 'Admin escolar';
  }

  // ========= Colecciones =========

  CollectionReference<Map<String, dynamic>> get _col => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('notificaciones_docentes');

  CollectionReference<Map<String, dynamic>> get _colAlumnos => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('notificaciones_alumnos');

  CollectionReference<Map<String, dynamic>> get _colMembers =>
      _db.collection('schools').doc(_schoolId).collection('members');

  CollectionReference<Map<String, dynamic>> get _colTeachers =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  CollectionReference<Map<String, dynamic>> get _colGrades =>
      _db.collection('schools').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _colDailyQuota => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('notificaciones_admin_cuota_diaria');

  // ========= Helpers =========

  DateTime? _asDateTime(dynamic v) =>
      (v is Timestamp) ? v.toDate().toLocal() : null;

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    final h24 = dt.hour;
    final h = (h24 % 12 == 0) ? 12 : (h24 % 12);
    final mi = dt.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$dd/$mm/$yy • $h:$mi $ampm';
  }

  bool _isTeacherMember(Map<String, dynamic> m) {
    final role = (m['role'] ?? m['rol'] ?? '').toString().toLowerCase().trim();
    if (role.contains('teacher') || role.contains('docente')) return true;

    final roles = m['roles'];
    if (roles is List) {
      for (final r in roles) {
        final s = r.toString().toLowerCase().trim();
        if (s.contains('teacher') || s.contains('docente')) return true;
      }
    }
    return false;
  }

  String _clean(String s) => s.trim();

  DateTime get _todayLocalStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _dateKey(DateTime dt) {
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$yyyy$mm$dd';
  }

  DocumentReference<Map<String, dynamic>> _dailyQuotaRef([DateTime? date]) {
    final target = date ?? _todayLocalStart;
    return _colDailyQuota.doc('${_adminUid}_${_dateKey(target)}');
  }

  Future<int> _reserveDailyNotificationSlot() async {
    final ref = _dailyQuotaRef();
    final dayStart = _todayLocalStart;

    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final current = (data?['sentCount'] as num?)?.toInt() ?? 0;
      if (current >= _dailyNotificationLimit) {
        throw StateError(
          'Ya alcanzaste el límite diario de $_dailyNotificationLimit notificaciones. '
          'Podrás volver a enviar mañana.',
        );
      }

      final next = current + 1;
      tx.set(ref, {
        'sentCount': next,
        'dailyLimit': _dailyNotificationLimit,
        'schoolId': _schoolId,
        'adminUid': _adminUid,
        'adminName': _adminName(),
        'dateKey': _dateKey(dayStart),
        'dayStart': Timestamp.fromDate(dayStart),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return next;
    });
  }

  Future<void> _releaseDailyNotificationSlot() async {
    final ref = _dailyQuotaRef();
    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data();
      final current = (data?['sentCount'] as num?)?.toInt() ?? 0;
      if (current <= 0) return;
      tx.set(ref, {
        'sentCount': current - 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Widget _dailyLimitCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _dailyQuotaRef().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const AdminNotificationEmptyState(
            title: 'No se pudo consultar el límite de hoy',
            description:
                'El límite se comprobará cuando intentes enviar el aviso.',
            icon: Icons.info_outline_rounded,
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data?.data();
        final used = (data?['sentCount'] as num?)?.toInt() ?? 0;
        final remaining = (_dailyNotificationLimit - used).clamp(
          0,
          _dailyNotificationLimit,
        );
        final exhausted = remaining == 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: exhausted ? Colors.red.shade50 : const Color(0xFFF1F3FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  exhausted
                      ? Colors.red.shade200
                      : AdminNotificationColors.border,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    exhausted ? Colors.red.shade100 : const Color(0xFFE2E6FF),
                child: Icon(
                  exhausted ? Icons.block_rounded : Icons.today_rounded,
                  color: exhausted ? Colors.red.shade700 : _blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exhausted
                          ? 'Límite diario alcanzado'
                          : 'Límite diario de notificaciones',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color:
                            exhausted
                                ? Colors.red.shade900
                                : AdminNotificationColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hoy llevas $used de $_dailyNotificationLimit enviadas. '
                      'Te quedan $remaining disponibles.',
                      style: TextStyle(
                        color:
                            exhausted
                                ? Colors.red.shade800
                                : AdminNotificationColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _targetLabelFromDoc(Map<String, dynamic> n) {
    final t = (n['targetType'] ?? 'all').toString();
    if (t == 'teacher') {
      final name = (n['teacherName'] ?? '').toString().trim();
      final id = (n['teacherDocId'] ?? '').toString().trim();
      if (name.isNotEmpty) return 'Docente: $name';
      if (id.isNotEmpty) return 'Docente: $id';
      return 'Docente específico';
    }
    if (t == 'grade') {
      final gn = (n['gradeName'] ?? '').toString().trim();
      final gid = (n['gradeId'] ?? '').toString().trim();
      if (gn.isNotEmpty) return 'Grado: $gn';
      if (gid.isNotEmpty) return 'Grado: $gid';
      return 'Por grado';
    }
    if (t == 'all_teachers') return 'Todos los docentes';
    if (t == 'all_students') return 'Todos los alumnos';
    return 'Todos';
  }

  String _includeLabelFromDoc(Map<String, dynamic> n) {
    final it = n['includeTeachers'] == true;
    final istd = n['includeStudents'] == true;
    if (it && istd) return 'Incluye: Docentes + Alumnos';
    if (it) return 'Incluye: Docentes';
    if (istd) return 'Incluye: Alumnos';
    return '';
  }

  void _setMode(_SendMode m) {
    setState(() {
      _mode = m;

      // Si es por docente, no tiene sentido incluir alumnos
      if (_mode == _SendMode.teacher) {
        _includeTeachers = true;
        _includeStudents = false;
        _selectedGradeIds.clear();
      }

      if (_mode == _SendMode.grade) {
        _selectedTeacherIds.clear();
      }

      if (_mode == _SendMode.all) {
        _selectedTeacherIds.clear();
        _selectedGradeIds.clear();
      }
    });
  }

  // ========= Enviar =========

  Future<void> _sendNotif() async {
    final u = _auth.currentUser;
    if (u == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay sesión activa.')));
      return;
    }

    final title = _clean(_titleCtrl.text);
    final body = _clean(_bodyCtrl.text);

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Escribe un título.')));
      return;
    }
    if (body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Escribe el mensaje.')));
      return;
    }

    if (!_includeTeachers && !_includeStudents) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona si incluir Docentes, Alumnos o ambos.'),
        ),
      );
      return;
    }

    // Validaciones por modo
    if (_mode == _SendMode.grade) {
      if (_selectedGradeIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona al menos un grado.')),
        );
        return;
      }
    }
    if (_mode == _SendMode.teacher) {
      if (_selectedTeacherIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona al menos un docente.')),
        );
        return;
      }
      // En teacher mode, forzamos teachers
      if (!_includeTeachers) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('En “Por docente” solo aplica a Docentes.'),
          ),
        );
        return;
      }
    }

    final channels = <String, bool>{
      for (final ch in _channels) ch: _sendChannels[ch] == true,
    };

    setState(() => _sending = true);

    var reservedQuota = false;

    try {
      await _reserveDailyNotificationSlot();
      reservedQuota = true;

      final base = <String, dynamic>{
        'title': title,
        'body': body,
        'channels': channels,

        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': u.uid,
        'createdByName': _adminName(),

        // Para que lo vean como NO leído
        'readBy': <String>[],

        // Para historial/admin
        'includeTeachers': _includeTeachers,
        'includeStudents': _includeStudents,
        'schoolId': _schoolId,
      };

      final batch = _db.batch();

      // 1) TODOS
      if (_mode == _SendMode.all) {
        // Docentes (legacy: targetType = all_teachers)
        if (_includeTeachers) {
          final payload = <String, dynamic>{
            ...base,
            'targetType': 'all_teachers',
          };
          batch.set(_col.doc(), payload);
        }

        // Alumnos (nuevo: targetType = all_students)
        if (_includeStudents) {
          final payload = <String, dynamic>{
            ...base,
            'targetType': 'all_students',
          };
          batch.set(_colAlumnos.doc(), payload);
        }
      }

      // 2) POR GRADOS (fan-out: 1 doc por grado, no rompe legacy)
      if (_mode == _SendMode.grade) {
        // Construimos mapa gradeId->gradeName para guardar bonito
        final gradeNameMap = await _fetchGradeNameMap(_selectedGradeIds);

        for (final gradeId in _selectedGradeIds) {
          final gradeName = gradeNameMap[gradeId] ?? gradeId;

          if (_includeTeachers) {
            final payload = <String, dynamic>{
              ...base,
              'targetType': 'grade',
              'gradeId': gradeId,
              'gradeName': gradeName,
            };
            batch.set(_col.doc(), payload);
          }

          if (_includeStudents) {
            final payload = <String, dynamic>{
              ...base,
              'targetType': 'grade',
              'gradeId': gradeId,
              'gradeName': gradeName,
            };
            batch.set(_colAlumnos.doc(), payload);
          }
        }
      }

      // 3) POR DOCENTES (fan-out: 1 doc por docente)
      if (_mode == _SendMode.teacher) {
        // Intentamos resolver nombres para guardar teacherName en el doc
        final teacherNameMap = await _fetchTeacherNameMap(_selectedTeacherIds);

        for (final teacherDocId in _selectedTeacherIds) {
          final teacherName = (teacherNameMap[teacherDocId] ?? '').trim();
          final payload = <String, dynamic>{
            ...base,
            'targetType': 'teacher',
            'teacherDocId': teacherDocId,
            if (teacherName.isNotEmpty) 'teacherName': teacherName,
          };
          batch.set(_col.doc(), payload);
        }
      }

      // Ejecutar
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notificación enviada.')));

      // Limpiar
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _teacherDocIdCtrl.clear();
      _gradeIdCtrl.clear();
      _teacherSearchCtrl.clear();
      _gradeSearchCtrl.clear();

      setState(() {
        _mode = _SendMode.all;
        _includeTeachers = true;
        _includeStudents = false;
        _selectedGradeIds.clear();
        _selectedTeacherIds.clear();
      });
    } catch (e) {
      if (reservedQuota) {
        await _releaseDailyNotificationSlot();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.toString().replaceFirst('Bad state: ', '')
                : 'No se pudo enviar la notificación. Inténtalo de nuevo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Map<String, String>> _fetchGradeNameMap(Set<String> ids) async {
    final out = <String, String>{};
    try {
      // Ojo: Firestore no permite "whereIn" sobre docId fácilmente sin field.
      // Hacemos gets individuales (normalmente pocos grados).
      final futures = ids.map((id) => _colGrades.doc(id).get());
      final snaps = await Future.wait(futures);
      for (final s in snaps) {
        if (!s.exists) continue;
        final d = s.data() ?? <String, dynamic>{};
        final name =
            (d['name'] ?? d['nombre'] ?? d['grado'] ?? s.id).toString().trim();
        out[s.id] = name.isEmpty ? s.id : name;
      }
    } catch (_) {
      // fallback: id -> id
      for (final id in ids) {
        out[id] = id;
      }
    }
    return out;
  }

  Future<Map<String, String>> _fetchTeacherNameMap(Set<String> ids) async {
    final out = <String, String>{};
    try {
      final futures = ids.map((id) => _colTeachers.doc(id).get());
      final snaps = await Future.wait(futures);
      for (final s in snaps) {
        if (!s.exists) continue;
        final d = s.data() ?? <String, dynamic>{};
        final name =
            (d['name'] ?? d['nombre'] ?? d['displayName'] ?? '')
                .toString()
                .trim();
        if (name.isNotEmpty) out[s.id] = name;
      }
    } catch (_) {
      // Ignorar: no es crítico
    }
    return out;
  }

  // ========= Eliminar =========

  Future<void> _deleteNotif(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notificación eliminada.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar la notificación. Inténtalo de nuevo.',
          ),
        ),
      );
    }
  }

  // ========= Detalle =========

  void _openDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final title = (data['title'] ?? 'Notificación').toString().trim();
    final body = (data['body'] ?? '').toString().trim();
    final createdAt = _fmtDateTime(_asDateTime(data['createdAt']));
    final targetType = (data['targetType'] ?? 'all_teachers').toString();

    final extra = <String>[];
    if (targetType == 'teacher') {
      final tn = (data['teacherName'] ?? '').toString().trim();
      extra.add(
        'Docente: ${tn.isNotEmpty ? tn : (data['teacherDocId'] ?? '').toString()}',
      );
    } else if (targetType == 'grade') {
      final gn = (data['gradeName'] ?? '').toString().trim();
      extra.add(
        'Grado: ${gn.isNotEmpty ? gn : (data['gradeId'] ?? '').toString()}',
      );
    } else if (targetType == 'all_teachers') {
      extra.add('Todos los docentes');
    } else if (targetType == 'all_students') {
      extra.add('Todos los alumnos');
    }

    final includeLine = _includeLabelFromDoc(data);
    if (includeLine.isNotEmpty) extra.add(includeLine);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AdminNotificationColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (createdAt.isNotEmpty)
                      Text(
                        createdAt,
                        style: const TextStyle(
                          color: AdminNotificationColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (extra.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        extra.join(' • '),
                        style: const TextStyle(
                          color: AdminNotificationColors.muted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      body.isEmpty ? 'Sin contenido.' : body,
                      style: const TextStyle(
                        color: AdminNotificationColors.ink,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder:
                                  (_) => const AdminNotificationDeleteDialog(),
                            );
                            if (confirmed != true || !mounted) return;
                            Navigator.pop(context);
                            await _deleteNotif(doc.reference);
                          },
                          icon: const Icon(Icons.delete),
                          label: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ========= UI Components =========

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (iconColor ?? _orange).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: iconColor ?? _orange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AdminNotificationColors.ink,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: AdminNotificationColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeChips() {
    Widget chip({
      required String label,
      required _SendMode value,
      required IconData icon,
    }) {
      final sel = _mode == value;
      return ChoiceChip(
        selected: sel,
        onSelected: (_) => _setMode(value),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: sel ? _blue : AdminNotificationColors.muted,
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        selectedColor: _blue.withValues(alpha: 0.12),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: sel ? _blue : AdminNotificationColors.ink,
        ),
        side: BorderSide(
          color:
              sel
                  ? _blue.withValues(alpha: 0.40)
                  : AdminNotificationColors.border,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        chip(label: 'Todos', value: _SendMode.all, icon: Icons.public),
        chip(label: 'Por grado', value: _SendMode.grade, icon: Icons.class_),
        chip(
          label: 'Por docente',
          value: _SendMode.teacher,
          icon: Icons.person_search,
        ),
      ],
    );
  }

  Widget _includeToggles() {
    // En teacher mode se fuerza (y se muestra bloqueado)
    final lockStudents = _mode == _SendMode.teacher;

    Widget toggle({
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
      required IconData icon,
      required Color color,
      bool disabled = false,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled ? null : () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: value ? color.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  value
                      ? color.withValues(alpha: 0.40)
                      : AdminNotificationColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    disabled
                        ? AdminNotificationColors.muted
                        : (value ? color : AdminNotificationColors.muted),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      disabled
                          ? AdminNotificationColors.muted
                          : (value ? color : AdminNotificationColors.ink),
                ),
              ),
              const SizedBox(width: 6),
              if (disabled)
                const Icon(
                  Icons.lock,
                  size: 16,
                  color: AdminNotificationColors.muted,
                )
              else
                Icon(
                  value ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: value ? color : AdminNotificationColors.muted,
                ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        toggle(
          label: 'Docentes',
          value: _includeTeachers,
          onChanged: (v) => setState(() => _includeTeachers = v),
          icon: Icons.school,
          color: _blue,
          disabled:
              _mode == _SendMode.teacher
                  ? true
                  : false, // en teacher mode siempre true
        ),
        toggle(
          label: 'Alumnos',
          value: _includeStudents,
          onChanged: (v) => setState(() => _includeStudents = v),
          icon: Icons.groups,
          color: _orange,
          disabled: lockStudents,
        ),
      ],
    );
  }

  Widget _contentFields() {
    return Column(
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: 'Título',
            hintText: 'Ej.: Reunión de familias',
            prefixIcon: const Icon(Icons.title_rounded, color: _blue),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bodyCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Mensaje',
            hintText: 'Escribe el aviso que recibirán los destinatarios.',
            alignLabelWithHint: true,
            prefixIcon: const Icon(Icons.message_outlined, color: _blue),
          ),
        ),
      ],
    );
  }

  Widget _gradePicker() {
    final q = _gradeSearchCtrl.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _gradeSearchCtrl,
          decoration: InputDecoration(
            labelText: 'Buscar grado',
            prefixIcon: const Icon(Icons.search, color: _blue),
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _colGrades.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text(
                'No se pudieron cargar los grados. Inténtalo de nuevo.',
                style: TextStyle(color: AdminNotificationColors.ink),
              );
            }
            if (!snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Text('No hay grados registrados en esta escuela.'),
              );
            }

            final list = <_GradeOption>[];
            for (final d in docs) {
              final data = d.data();
              final name =
                  (data['name'] ?? data['nombre'] ?? data['grado'] ?? d.id)
                      .toString()
                      .trim();
              final opt = _GradeOption(
                gradeId: d.id,
                name: name.isEmpty ? d.id : name,
              );
              if (q.isEmpty ||
                  opt.name.toLowerCase().contains(q) ||
                  opt.gradeId.toLowerCase().contains(q)) {
                list.add(opt);
              }
            }
            list.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  list.map((g) {
                    final sel = _selectedGradeIds.contains(g.gradeId);
                    return FilterChip(
                      label: Text(g.name),
                      selected: sel,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedGradeIds.add(g.gradeId);
                          } else {
                            _selectedGradeIds.remove(g.gradeId);
                          }
                        });
                      },
                      selectedColor: _blue.withValues(alpha: 0.12),
                      checkmarkColor: _blue,
                      side: BorderSide(
                        color:
                            sel
                                ? _blue.withValues(alpha: 0.35)
                                : Colors.grey.shade300,
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _teacherPicker() {
    final q = _teacherSearchCtrl.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _teacherSearchCtrl,
          decoration: InputDecoration(
            labelText: 'Buscar docente',
            prefixIcon: const Icon(Icons.search, color: _blue),
          ),
        ),
        const SizedBox(height: 10),

        // 1) Cargar teachers (para nombres)
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _colTeachers.snapshots(),
          builder: (context, teachersSnap) {
            if (teachersSnap.hasError) {
              return const Text(
                'No se pudieron cargar los docentes. Inténtalo de nuevo.',
                style: TextStyle(color: AdminNotificationColors.ink),
              );
            }
            if (!teachersSnap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final teachersMap = <String, Map<String, dynamic>>{};
            for (final t in teachersSnap.data!.docs) {
              teachersMap[t.id] = t.data();
            }

            // 2) Cargar members (para validar role=docente)
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _colMembers.snapshots(),
              builder: (context, membersSnap) {
                if (membersSnap.hasError) {
                  return const Text(
                    'No se pudieron cargar los docentes. Inténtalo de nuevo.',
                    style: TextStyle(color: AdminNotificationColors.ink),
                  );
                }
                if (!membersSnap.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final opts = <_TeacherOption>[];
                for (final mdoc in membersSnap.data!.docs) {
                  final m = mdoc.data();
                  if (!_isTeacherMember(m)) continue;

                  // Resolver teacherDocId (robusto)
                  final teacherDocId =
                      (m['teacherDocId'] ?? m['uid'] ?? m['authUid'] ?? mdoc.id)
                          .toString()
                          .trim();
                  if (teacherDocId.isEmpty) continue;

                  final tdata = teachersMap[teacherDocId];
                  final name =
                      (tdata?['name'] ??
                              tdata?['nombre'] ??
                              m['name'] ??
                              m['nombre'] ??
                              m['displayName'] ??
                              '')
                          .toString()
                          .trim();

                  // emailLower para ayudar a buscar / mostrar
                  final emailLower =
                      (tdata?['emailLower'] ??
                              m['emailLower'] ??
                              m['email'] ??
                              '')
                          .toString()
                          .trim()
                          .toLowerCase();
                  final showName = name.isNotEmpty ? name : teacherDocId;

                  final opt = _TeacherOption(
                    teacherDocId: teacherDocId,
                    name: showName,
                    emailLower: emailLower.isEmpty ? null : emailLower,
                  );

                  // filtro
                  final hay = opt.name.toLowerCase();
                  final hey = (opt.emailLower ?? '');
                  if (q.isEmpty ||
                      hay.contains(q) ||
                      teacherDocId.toLowerCase().contains(q) ||
                      hey.contains(q)) {
                    opts.add(opt);
                  }
                }

                if (opts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Text(
                      'No se encontraron docentes para esta búsqueda.',
                    ),
                  );
                }

                opts.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: opts.length,
                    separatorBuilder:
                        (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (_, i) {
                      final t = opts[i];
                      final sel = _selectedTeacherIds.contains(t.teacherDocId);

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (sel) {
                              _selectedTeacherIds.remove(t.teacherDocId);
                            } else {
                              _selectedTeacherIds.add(t.teacherDocId);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: _blue.withValues(alpha: 0.10),
                                child: Icon(Icons.person, color: _blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AdminNotificationColors.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if ((t.emailLower ?? '').isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          t.emailLower!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color:
                                                AdminNotificationColors.muted,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                sel
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: sel ? _blue : Colors.grey.shade500,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _advancedFallback() {
    // Mantener compatibilidad con el flujo viejo (por si algo falla en data)
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 10),
      title: const Text(
        'Opciones avanzadas',
        style: TextStyle(
          color: AdminNotificationColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: const Text(
        'Si no aparece en la lista, usa su identificador.',
        style: TextStyle(
          color: AdminNotificationColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (_mode == _SendMode.teacher)
          TextField(
            controller: _teacherDocIdCtrl,
            decoration: const InputDecoration(
              labelText: 'Identificador del docente',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            onChanged: (v) {
              final id = v.trim();
              if (id.isEmpty) return;
              setState(() {
                _selectedTeacherIds.add(id);
              });
            },
          ),
        if (_mode == _SendMode.grade)
          TextField(
            controller: _gradeIdCtrl,
            decoration: const InputDecoration(
              labelText: 'Identificador del grado',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.class_),
            ),
            onChanged: (v) {
              final id = v.trim();
              if (id.isEmpty) return;
              setState(() {
                _selectedGradeIds.add(id);
              });
            },
          ),
      ],
    );
  }

  // ========= Historial UI =========

  Widget _historySelector() {
    Widget chip(String v, String label, IconData icon) {
      final sel = _historyView == v;
      return ChoiceChip(
        selected: sel,
        onSelected: (_) => setState(() => _historyView = v),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: sel ? _blue : AdminNotificationColors.muted,
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        selectedColor: _blue.withValues(alpha: 0.12),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: sel ? _blue : AdminNotificationColors.ink,
        ),
        side: BorderSide(
          color:
              sel
                  ? _blue.withValues(alpha: 0.40)
                  : AdminNotificationColors.border,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        chip('docentes', 'Docentes', Icons.school),
        chip('alumnos', 'Alumnos', Icons.groups),
        chip('ambos', 'Ambos', Icons.view_agenda),
      ],
    );
  }

  Widget _notifList({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required String emptyText,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const AdminNotificationEmptyState(
            title: 'No se pudo cargar el historial',
            description: 'Comprueba tu conexión e inténtalo de nuevo.',
            icon: Icons.wifi_off_rounded,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return AdminNotificationEmptyState(
            title: 'Aún no hay notificaciones',
            description: emptyText,
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final n = doc.data();
            final title = (n['title'] ?? 'Notificación').toString().trim();
            final body = (n['body'] ?? '').toString().trim();
            final dt = _fmtDateTime(_asDateTime(n['createdAt']));
            final readBy =
                (n['readBy'] is List) ? (n['readBy'] as List).length : 0;

            final target = _targetLabelFromDoc(n);
            final include = _includeLabelFromDoc(n);

            return AdminNotificationHistoryCard(
              title: title,
              body: body,
              date: dt,
              target: target,
              include: include,
              readCount: readBy,
              onTap: () => _openDetail(doc),
            );
          },
        );
      },
    );
  }

  // ========= Build =========

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.escuela.nombre.toString().trim();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        leading: AdminBackButton(onBack: widget.onBack),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(
          'Notificaciones',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFFF8F9FC),
                  labelStyle: const TextStyle(
                    color: AdminNotificationColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  hintStyle: const TextStyle(
                    color: AdminNotificationColors.muted,
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AdminNotificationColors.border,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AdminNotificationColors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _blue, width: 1.6),
                  ),
                ),
              ),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 600 ? 14 : 24,
                  vertical: 20,
                ),
                children: [
                  AdminNotificationHero(schoolName: schoolName),
                  const SizedBox(height: 20),
                  // ===== Crear =====
                  Container(
                    padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AdminNotificationColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          icon: Icons.notifications_active,
                          title: 'Enviar notificación',
                          subtitle:
                              'Define quién recibirá el aviso y redacta su contenido.',
                          iconColor: _blue,
                        ),
                        const SizedBox(height: 14),

                        _dailyLimitCard(),
                        const SizedBox(height: 14),

                        // Modo
                        const Text(
                          'Destinatarios',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AdminNotificationColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _modeChips(),

                        const SizedBox(height: 12),

                        // Incluir
                        const Text(
                          'Enviar a',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AdminNotificationColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _includeToggles(),

                        const SizedBox(height: 14),

                        // Pickers según modo
                        if (_mode == _SendMode.grade) ...[
                          _sectionHeader(
                            icon: Icons.class_,
                            title: 'Selecciona grados',
                            subtitle:
                                'El aviso llegará a los grados seleccionados según los destinatarios elegidos.',
                            iconColor: _blue,
                          ),
                          const SizedBox(height: 10),
                          _gradePicker(),
                          const SizedBox(height: 10),
                        ],

                        if (_mode == _SendMode.teacher) ...[
                          _sectionHeader(
                            icon: Icons.person_search,
                            title: 'Selecciona docentes',
                            subtitle:
                                'Busca y selecciona a los docentes que recibirán el aviso.',
                            iconColor: _blue,
                          ),
                          const SizedBox(height: 10),
                          _teacherPicker(),
                          const SizedBox(height: 10),
                        ],

                        // Contenido
                        _sectionHeader(
                          icon: Icons.edit_note,
                          title: 'Contenido',
                          subtitle:
                              'Escribe un título y un mensaje fáciles de reconocer.',
                          iconColor: _blue,
                        ),
                        const SizedBox(height: 10),
                        _contentFields(),

                        const SizedBox(height: 10),
                        _advancedFallback(),

                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width:
                                MediaQuery.sizeOf(context).width < 600
                                    ? double.infinity
                                    : null,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(190, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _sending ? null : _sendNotif,
                              icon:
                                  _sending
                                      ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Icon(Icons.send),
                              label: Text(
                                _sending ? 'Enviando…' : 'Enviar notificación',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===== Historial =====
                  _sectionHeader(
                    icon: Icons.history_rounded,
                    title: 'Historial de notificaciones',
                    subtitle:
                        'Consulta los avisos enviados y abre uno para ver el mensaje completo.',
                    iconColor: _blue,
                  ),
                  const SizedBox(height: 14),
                  _historySelector(),
                  const SizedBox(height: 14),

                  if (_historyView == 'docentes')
                    _notifList(
                      stream:
                          _col
                              .orderBy('createdAt', descending: true)
                              .limit(120)
                              .snapshots(),
                      emptyText:
                          'Aún no has enviado notificaciones a docentes.',
                    ),

                  if (_historyView == 'alumnos')
                    _notifList(
                      stream:
                          _colAlumnos
                              .orderBy('createdAt', descending: true)
                              .limit(120)
                              .snapshots(),
                      emptyText: 'Aún no has enviado notificaciones a alumnos.',
                    ),

                  if (_historyView == 'ambos') ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: const Text(
                        'Docentes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AdminNotificationColors.ink,
                        ),
                      ),
                    ),
                    _notifList(
                      stream:
                          _col
                              .orderBy('createdAt', descending: true)
                              .limit(60)
                              .snapshots(),
                      emptyText: 'Sin notificaciones a docentes.',
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Alumnos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AdminNotificationColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _notifList(
                      stream:
                          _colAlumnos
                              .orderBy('createdAt', descending: true)
                              .limit(60)
                              .snapshots(),
                      emptyText: 'Sin notificaciones a alumnos.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
