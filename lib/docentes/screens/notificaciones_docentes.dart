// lib/docentes/screens/notificaciones_docentes.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class DocentesNotificacionesScreen extends StatefulWidget {
  final Escuela escuela;

  const DocentesNotificacionesScreen({
    super.key,
    required this.escuela,
  });

  @override
  State<DocentesNotificacionesScreen> createState() =>
      _DocentesNotificacionesScreenState();
}

class _DocentesNotificacionesScreenState
    extends State<DocentesNotificacionesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

  late final String _schoolId;

  // Tabs
  int _tab = 0; // 0 = todas, 1 = no leídas

  // Teacher binding
  String? _teacherDocId;
  String _teacherName = 'Docente';
  List<String> _gradeIds = [];
  String? _err;

  // Sound & reactions
  bool _soundEnabled = true;
  bool _userInteracted = false; // para Web (autoplay policy)

  // Stream state
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _primed = false;
  final Set<String> _seenIds = <String>{};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _schoolId = raw.replaceAll('/', '_');

    _bindTeacherAndListen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _myUid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _notifsCol => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('notificaciones_docentes');

  CollectionReference<Map<String, dynamic>> get _teacherUidCol =>
      _db.collection('schools').doc(_schoolId).collection('teachers_uid');

  CollectionReference<Map<String, dynamic>> get _teachersCol =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  // ------------------------- Helpers (time) -------------------------
  DateTime? _asDateTime(dynamic v) => (v is Timestamp) ? v.toDate().toLocal() : null;

  String _fmtTimeShort(DateTime? dt) {
    if (dt == null) return '';
    final h24 = dt.hour;
    final h = (h24 % 12 == 0) ? 12 : (h24 % 12);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _fmtDateShort(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$mo/$y';
  }

  // ------------------------- Teacher binding -------------------------
  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? <String>[] : <String>[s];
    }
    return <String>[];
  }

  List<String> _extractGradeIds(Map<String, dynamic> m) {
    // tolerante a nombres
    final raw = m['gradeIds'] ??
        m['gradesIds'] ??
        m['gradoIds'] ??
        m['gradosIds'] ??
        m['gradeId'] ??
        m['gradoId'];

    final out = _asStringList(raw);
    // normaliza (sin vacíos, sin duplicados)
    final seen = <String>{};
    final clean = <String>[];
    for (final s in out) {
      final v = s.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) clean.add(v);
    }
    return clean;
  }

  String _pickTeacherName(Map<String, dynamic> m) {
    final n = (m['displayName'] ??
            m['name'] ??
            m['nombre'] ??
            m['nombres'] ??
            m['fullName'] ??
            '')
        .toString()
        .trim();
    return n.isNotEmpty ? n : 'Docente';
  }

  Future<void> _bindTeacherAndListen() async {
    try {
      final u = _auth.currentUser;
      if (u == null) {
        setState(() => _err = 'No hay sesión activa del docente.');
        return;
      }

      final uid = u.uid;

      // teachers_uid/{uid} -> teacherDocId
      final linkSnap = await _teacherUidCol.doc(uid).get();
      if (!linkSnap.exists) {
        setState(() {
          _err =
              'Este docente no está vinculado en teachers_uid.\n'
              'Falta: schools/$_schoolId/teachers_uid/$uid con teacherDocId.';
        });
        return;
      }

      final link = linkSnap.data() ?? {};
      final tDocId = (link['teacherDocId'] ?? '').toString().trim();
      if (tDocId.isEmpty) {
        setState(() => _err = 'teachers_uid existe pero teacherDocId está vacío.');
        return;
      }

      // teachers/{teacherDocId}
      final tRef = _teachersCol.doc(tDocId);
      final tSnap = await tRef.get();
      final tData = tSnap.data() ?? <String, dynamic>{};

      final name = _pickTeacherName(tData);
      final gradeIds = _extractGradeIds(tData);

      setState(() {
        _teacherDocId = tDocId;
        _teacherName = name;
        _gradeIds = gradeIds;
        _err = null;
      });

      _attachNotificationsStream(); // ya con teacher data cargada
    } catch (e) {
      setState(() => _err = 'Error cargando docente: $e');
    }
  }

  // ------------------------- Target filter -------------------------
  bool _isForMe(Map<String, dynamic> n) {
    final ttype = (n['targetType'] ?? 'all_teachers').toString().trim().toLowerCase();

    if (ttype == 'all_teachers') return true;

    if (ttype == 'teacher') {
      final mine = (_teacherDocId ?? '').trim();
      final doc = (n['teacherDocId'] ?? '').toString().trim();
      return mine.isNotEmpty && doc.isNotEmpty && doc == mine;
    }

    if (ttype == 'grade') {
      final gid = (n['gradeId'] ?? '').toString().trim();
      if (gid.isEmpty) return false;
      return _gradeIds.contains(gid);
    }

    // desconocido -> por seguridad, no mostrar
    return false;
  }

  bool _isUnread(Map<String, dynamic> n) {
    final uid = _myUid;
    if (uid.isEmpty) return false;

    final readBy = n['readBy'];
    if (readBy is List) {
      return !readBy.map((e) => e.toString()).contains(uid);
    }
    // si no existe readBy => tratamos como NO leída
    return true;
  }

  Future<void> _markRead(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final uid = _myUid;
    if (uid.isEmpty) return;
    if (!_isUnread(data)) return;

    try {
      await ref.set({
        'readBy': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude marcar como leída: $e')),
      );
    }
  }

  // ------------------------- Reactions (type/priority) -------------------------
  _NotifKind _inferKind(Map<String, dynamic> n) {
    final typeRaw = (n['type'] ?? n['tipo'] ?? '').toString().trim().toLowerCase();
    final prioRaw = (n['priority'] ?? n['prioridad'] ?? '').toString().trim().toLowerCase();
    final title = (n['title'] ?? n['titulo'] ?? '').toString().toLowerCase();
    final body = (n['body'] ?? n['mensaje'] ?? n['text'] ?? '').toString().toLowerCase();

    // prioridad explícita
    if (prioRaw == 'high' || prioRaw == 'alta' || prioRaw == 'critica' || prioRaw == 'crítica') {
      return _NotifKind.critica;
    }
    if (prioRaw == 'low' || prioRaw == 'baja') {
      return _NotifKind.info;
    }

    // tipo explícito
    if (typeRaw.contains('seguridad') || typeRaw.contains('security') || typeRaw.contains('alerta')) {
      return _NotifKind.critica;
    }
    if (typeRaw.contains('pago') || typeRaw.contains('factura') || typeRaw.contains('billing')) {
      return _NotifKind.pago;
    }
    if (typeRaw.contains('academ') || typeRaw.contains('grade') || typeRaw.contains('aula')) {
      return _NotifKind.academica;
    }

    // inferencia por texto
    final text = '$title $body';
    if (text.contains('seguridad') || text.contains('alerta') || text.contains('bloqueo')) {
      return _NotifKind.critica;
    }
    if (text.contains('pago') || text.contains('factura') || text.contains('venc')) {
      return _NotifKind.pago;
    }
    if (text.contains('grado') || text.contains('calificación') || text.contains('evalu')) {
      return _NotifKind.academica;
    }

    return _NotifKind.general;
  }

  _ReactionProfile _profileFor(_NotifKind k) {
    switch (k) {
      case _NotifKind.critica:
        return const _ReactionProfile(
          icon: Icons.warning_amber_rounded,
          accent: Colors.red,
          label: 'Alerta',
          severity: _Severity.high,
        );
      case _NotifKind.pago:
        return const _ReactionProfile(
          icon: Icons.payment,
          accent: Color(0xFF6A1B9A),
          label: 'Pago',
          severity: _Severity.medium,
        );
      case _NotifKind.academica:
        return const _ReactionProfile(
          icon: Icons.school,
          accent: Color(0xFF1565C0),
          label: 'Académico',
          severity: _Severity.medium,
        );
      case _NotifKind.info:
        return const _ReactionProfile(
          icon: Icons.info_outline,
          accent: Color(0xFF2E7D32),
          label: 'Info',
          severity: _Severity.low,
        );
      case _NotifKind.general:
      default:
        return const _ReactionProfile(
          icon: Icons.notifications,
          accent: Color(0xFFFFA000),
          label: 'General',
          severity: _Severity.low,
        );
    }
  }

  void _playReaction(_ReactionProfile p, {required String title}) async {
    if (!_soundEnabled) return;

    // Web: evita intento de sonido sin interacción
    if (kIsWeb && !_userInteracted) return;

    try {
      // sonido simple sin dependencias externas
      SystemSound.play(SystemSoundType.alert);

      // haptics (en web normalmente no aplica)
      if (!kIsWeb) {
        switch (p.severity) {
          case _Severity.high:
            await HapticFeedback.heavyImpact();
            break;
          case _Severity.medium:
            await HapticFeedback.mediumImpact();
            break;
          case _Severity.low:
            await HapticFeedback.selectionClick();
            break;
        }
      }
    } catch (_) {
      // silencioso
    }

    if (!mounted) return;

    // reacción visual: SnackBar diferente
    final snack = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.white,
      elevation: 6,
      content: Row(
        children: [
          Icon(p.icon, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${p.label}: $title',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  // ------------------------- Stream attach -------------------------
  void _attachNotificationsStream() {
    _sub?.cancel();
    _primed = false;
    _seenIds.clear();

    _sub = _notifsCol
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
      // 1) primer snapshot: no disparar reacciones
      if (!_primed) {
        _seenIds.addAll(snap.docs.map((d) => d.id));
        _primed = true;
        setState(() => _docs = snap.docs);
        return;
      }

      // 2) siguientes snapshots: detectar nuevos
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final doc = ch.doc;
        if (_seenIds.contains(doc.id)) continue;
        _seenIds.add(doc.id);

        final data = doc.data() ?? <String, dynamic>{};
        // solo reaccionar si ES PARA MI
        if (_isForMe(data)) {
          final title = (data['title'] ?? data['titulo'] ?? 'Notificación').toString().trim();
          final kind = _inferKind(data);
          final profile = _profileFor(kind);
          _playReaction(profile, title: title);
        }
      }

      setState(() => _docs = snap.docs);
    }, onError: (e) {
      setState(() => _err = 'Error leyendo notificaciones: $e');
    });
  }

  // ------------------------- UI helpers -------------------------
  Widget _tabButton({required int idx, required String text, required IconData icon}) {
    final sel = _tab == idx;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _tab = idx),
        icon: Icon(icon, size: 18, color: sel ? Colors.white : _blue),
        label: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: sel ? Colors.white : _blue,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: sel ? _blue : Colors.white,
          side: BorderSide(color: sel ? _blue : Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        ),
      ),
    );
  }

  void _openDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    await _markRead(doc.reference, data);

    final title = (data['title'] ?? data['titulo'] ?? 'Notificación').toString().trim();
    final body = (data['body'] ?? data['mensaje'] ?? data['text'] ?? '').toString().trim();
    final createdAt = _asDateTime(data['createdAt']);
    final date = _fmtDateShort(createdAt);
    final time = _fmtTimeShort(createdAt);

    final kind = _inferKind(data);
    final profile = _profileFor(kind);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: profile.accent.withOpacity(0.14),
                      child: Icon(profile.icon, color: profile.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (date.isNotEmpty || time.isNotEmpty)
                  Text(
                    [date, time].where((x) => x.isNotEmpty).join(' • '),
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 12),
                Text(body.isEmpty ? 'Sin contenido.' : body, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _unreadDot() => Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final schoolName = (widget.escuela.nombre ?? 'Escuela').toString().trim();

    // interacción del usuario (para permitir sonido en Web)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_userInteracted) setState(() => _userInteracted = true);
      },
      child: Scaffold(
        appBar: buildDocenteBackAppBar(
          context,
          actions: [
            IconButton(
              tooltip: _soundEnabled ? 'Sonido: ON' : 'Sonido: OFF',
              onPressed: () => setState(() => _soundEnabled = !_soundEnabled),
              icon: Icon(_soundEnabled ? Icons.volume_up : Icons.volume_off),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header + tabs
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: _orange.withOpacity(0.14),
                          child: Icon(Icons.notifications_active, color: _orange),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Docente: $_teacherName',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                          
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_err != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _err!,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _tabButton(idx: 0, text: 'Todas', icon: Icons.inbox),
                        const SizedBox(width: 10),
                        _tabButton(idx: 1, text: 'No leídas', icon: Icons.markunread),
                      ],
                    ),
                    if (kIsWeb && !_userInteracted) ...[
                      const SizedBox(height: 10),
                      Text(
                        '',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                      ),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    // Si aún no cargó teacherDocId (y no hay error), mostramos loader suave
    if (_teacherDocId == null && _err == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filtra “para mí”
    final mine = _docs.where((d) => _isForMe(d.data())).toList();

    final filtered = (_tab == 0)
        ? mine
        : mine.where((d) => _isUnread(d.data())).toList();

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('Sin notificaciones por ahora.', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final doc = filtered[i];
        final n = doc.data();

        final title = (n['title'] ?? n['titulo'] ?? 'Notificación').toString().trim();
        final body = (n['body'] ?? n['mensaje'] ?? n['text'] ?? '').toString().trim();
        final createdAt = _asDateTime(n['createdAt']);
        final time = _fmtTimeShort(createdAt);
        final date = _fmtDateShort(createdAt);

        final unread = _isUnread(n);

        final kind = _inferKind(n);
        final profile = _profileFor(kind);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(doc),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // icon + dot
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: profile.accent.withOpacity(0.12),
                      child: Icon(profile.icon, color: profile.accent),
                    ),
                    if (unread)
                      Positioned(right: 0, top: 0, child: _unreadDot()),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty || date.isNotEmpty)
                            Text(
                              [date, time].where((x) => x.isNotEmpty).join(' • '),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body.isEmpty ? 'Toca para ver detalles.' : body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: profile.accent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: profile.accent.withOpacity(0.25)),
                            ),
                            child: Text(
                              profile.label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: profile.accent,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right, color: Colors.grey.shade500),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------- Models for reactions -------------------------
enum _NotifKind { general, academica, pago, critica, info }

enum _Severity { low, medium, high }

class _ReactionProfile {
  final IconData icon;
  final Color accent;
  final String label;
  final _Severity severity;

  const _ReactionProfile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.severity,
  });
}
