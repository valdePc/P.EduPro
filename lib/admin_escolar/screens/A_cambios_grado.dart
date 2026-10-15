import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class ACambiosGradoScreen extends StatefulWidget {
  final Escuela escuela;

  const ACambiosGradoScreen({super.key, required this.escuela});

  @override
  State<ACambiosGradoScreen> createState() => _ACambiosGradoScreenState();
}

class _ACambiosGradoScreenState extends State<ACambiosGradoScreen> {
  static const Color _blue = Color(0xFF1A237E);
  static const Color _ink = Color(0xFF17243A);
  static const Color _muted = Color(0xFF5C687A);
  static const Color _page = Color(0xFFF4F6FB);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolId;
  bool _loading = true;
  bool _saving = false;
  String _statusFilter = 'pending';
  List<_MoveRequestRow> _rows = const [];
  Map<String, _GradeLite> _gradesById = const {};

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela).trim();
    _bootstrap();
  }

  CollectionReference<Map<String, dynamic>> _schoolCol(String path) {
    return _db.collection('schools').doc(_schoolId).collection(path);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CAMBIO_GRADO_ADMIN] $message');
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final gradesSnap = await _schoolCol('grados').get();
      final gradesById = <String, _GradeLite>{};
      for (final d in gradesSnap.docs) {
        final data = d.data();
        final id = (data['gradeId'] ?? d.id).toString().trim();
        final label = (data['name'] ?? data['grado'] ?? d.id).toString().trim();
        final nivel = (data['nivel'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        gradesById[id] = _GradeLite(
          id: id,
          label: label.isEmpty ? id : label,
          nivel: nivel,
        );
      }
      _gradesById = gradesById;
      await _loadRequests();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final snap =
          await _schoolCol(
            'solicitudes_cambio_grado',
          ).orderBy('createdAt', descending: true).get();
      final rows = snap.docs.map((d) => _MoveRequestRow.fromDoc(d)).toList();
      if (!mounted) return;
      setState(() => _rows = rows);
      _log('loaded requests=${rows.length} filter=$_statusFilter');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rejectRequest(_MoveRequestRow row) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rechazar solicitud'),
          content: TextField(
            controller: commentController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Comentario para el docente',
              hintText: 'Explica por qué no procede el cambio.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rechazar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _schoolCol('solicitudes_cambio_grado').doc(row.id).set({
        'status': 'rejected',
        'adminUid': _auth.currentUser?.uid,
        'adminComment': commentController.text.trim(),
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solicitud rechazada para ${row.studentName}.')),
      );
      await _loadRequests();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _executeRequest(_MoveRequestRow row) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Aprobar y ejecutar cambio'),
          content: TextField(
            controller: commentController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Comentario administrativo',
              hintText: 'Opcional. Se guardará en el historial del movimiento.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ejecutar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final studentRef = _schoolCol('alumnos').doc(row.studentId);
      final requestRef = _schoolCol('solicitudes_cambio_grado').doc(row.id);
      final globalRef = _db.collection('alumnos_global').doc(row.studentId);
      final movementRef = studentRef.collection('movimientos_academicos').doc();
      final adminUid = _auth.currentUser?.uid ?? '';

      final studentSnap = await studentRef.get();
      if (!studentSnap.exists) {
        throw Exception('El alumno ya no existe en la escuela.');
      }
      final studentData = studentSnap.data() ?? const <String, dynamic>{};
      final currentGradeId =
          (studentData['gradeId'] ?? studentData['gradoId'] ?? '')
              .toString()
              .trim();
      final currentYear =
          (studentData['schoolYear'] ?? studentData['anioEscolar'] ?? '')
              .toString()
              .trim();
      if (currentGradeId.isNotEmpty && currentGradeId != row.fromGradeId) {
        throw Exception(
          'El alumno ya cambió de grado. Refresca la bandeja antes de ejecutar.',
        );
      }
      if (currentYear.isNotEmpty && currentYear != row.schoolYear) {
        throw Exception(
          'El alumno ya está en otro periodo escolar. Refresca la bandeja.',
        );
      }

      final targetGrade = _gradesById[row.toGradeId];
      final targetGradeName = targetGrade?.label ?? row.toGradeName;
      final targetNivel = targetGrade?.nivel ?? '';
      final updatePayload = <String, dynamic>{
        'gradoId': row.toGradeId,
        'gradeId': row.toGradeId,
        'grado': targetGradeName,
        'gradeName': targetGradeName,
        'gradeLabel': targetGradeName,
        'gradoKey': _nameKey(targetGradeName),
        'tanda': row.toTanda,
        'schoolYear': row.schoolYear,
        'anioEscolar': row.schoolYear,
        'placementUpdatedAt': FieldValue.serverTimestamp(),
        'placementReason': row.reason,
        'currentMovementId': movementRef.id,
        if (targetNivel.isNotEmpty) 'nivel': targetNivel,
      };

      final movementPayload = <String, dynamic>{
        'requestId': row.id,
        'schoolId': _schoolId,
        'studentId': row.studentId,
        'studentName': row.studentName,
        'schoolYear': row.schoolYear,
        'fromGradeId': row.fromGradeId,
        'fromGradeName': row.fromGradeName,
        'fromTanda': row.fromTanda,
        'toGradeId': row.toGradeId,
        'toGradeName': targetGradeName,
        'toTanda': row.toTanda,
        'requestType': row.requestType,
        'reason': row.reason,
        'teacherUid': row.teacherUid,
        'teacherDocId': row.teacherDocId,
        'teacherName': row.teacherName,
        'adminUid': adminUid,
        'adminComment': commentController.text.trim(),
        'executedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final batch = _db.batch();
      batch.set(studentRef, updatePayload, SetOptions(merge: true));
      batch.set(globalRef, updatePayload, SetOptions(merge: true));
      batch.set(movementRef, movementPayload);
      batch.set(requestRef, {
        'status': 'executed',
        'adminUid': adminUid,
        'adminComment': commentController.text.trim(),
        'approvedAt': FieldValue.serverTimestamp(),
        'executedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final accesos =
          (studentData['accesosEmails'] is List)
              ? List<String>.from(
                (studentData['accesosEmails'] as List)
                    .map((e) => e.toString().trim().toLowerCase())
                    .where((e) => e.isNotEmpty),
              )
              : const <String>[];
      for (final emailLower in accesos) {
        final loginRef = _schoolCol('alumnos_login').doc(emailLower);
        batch.set(loginRef, {
          'gradeIds': FieldValue.arrayUnion([row.toGradeId]),
          'gradoIds': FieldValue.arrayUnion([row.toGradeId]),
          'currentGradeId': row.toGradeId,
          'currentGradeName': targetGradeName,
          'currentSchoolYear': row.schoolYear,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      _log(
        'execute requestId=${row.id} studentId=${row.studentId} to=${row.toGradeId}/${row.toTanda}',
      );
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cambio ejecutado para ${row.studentName}.')),
      );
      await _loadRequests();
    } catch (e) {
      _log('execute error requestId=${row.id} value=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ejecutar el cambio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _nameKey(String value) {
    const accents = <String, String>{
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'Á': 'a',
      'À': 'a',
      'Ä': 'a',
      'Â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'É': 'e',
      'È': 'e',
      'Ë': 'e',
      'Ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'Í': 'i',
      'Ì': 'i',
      'Ï': 'i',
      'Î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'Ó': 'o',
      'Ò': 'o',
      'Ö': 'o',
      'Ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Ú': 'u',
      'Ù': 'u',
      'Ü': 'u',
      'Û': 'u',
      'ñ': 'n',
      'Ñ': 'n',
    };
    return value
        .split('')
        .map((c) => accents[c] ?? c.toLowerCase())
        .join()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  List<_MoveRequestRow> get _visibleRows {
    if (_statusFilter == 'all') return _rows;
    return _rows.where((r) => r.status == _statusFilter).toList();
  }

  MaterialColor _statusColor(String status) {
    switch (status) {
      case 'executed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de cambios de grado',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Administra los movimientos académicos de tu escuela.',
                  style: TextStyle(
                    color: Color(0xFFE5E9FF),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final pending = _rows.where((row) => row.status == 'pending').length;
    final executed = _rows.where((row) => row.status == 'executed').length;
    final rejected = _rows.where((row) => row.status == 'rejected').length;
    final summaries = <(String, int, IconData, Color)>[
      (
        'Pendientes',
        pending,
        Icons.hourglass_top_rounded,
        const Color(0xFFB86A00),
      ),
      (
        'Ejecutados',
        executed,
        Icons.check_circle_outline_rounded,
        const Color(0xFF218653),
      ),
      ('Rechazados', rejected, Icons.cancel_outlined, const Color(0xFFC44545)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final width =
            compact
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in summaries)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE5EAF2)),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$3, color: item.$4, size: 23),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: TextStyle(
                                color: item.$4,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.$2}',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    if (MediaQuery.sizeOf(context).width < 760) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5EAF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bandeja de solicitudes',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Revisa, aprueba o rechaza movimientos académicos.',
              style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _statusFilter,
              isExpanded: true,
              style: const TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Filtrar solicitudes',
                filled: true,
                fillColor: const Color(0xFFF8F9FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pendientes')),
                DropdownMenuItem(value: 'executed', child: Text('Ejecutados')),
                DropdownMenuItem(value: 'rejected', child: Text('Rechazados')),
                DropdownMenuItem(value: 'all', child: Text('Todos')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
              },
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bandeja de solicitudes',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Revisa cambios excepcionales dentro del periodo escolar y ejecuta solo cuando estés segura.',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              isExpanded: true,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'Filtrar solicitudes',
                filled: true,
                fillColor: const Color(0xFFF8F9FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pendientes')),
                DropdownMenuItem(value: 'executed', child: Text('Ejecutados')),
                DropdownMenuItem(value: 'rejected', child: Text('Rechazados')),
                DropdownMenuItem(value: 'all', child: Text('Todos')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E7F5)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: _blue,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'executed':
        return 'Ejecutado';
      case 'rejected':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  String _requestTypeLabel(String type) {
    switch (type) {
      case 'promocion_anticipada':
        return 'Promocion anticipada';
      case 'descenso_grado':
        return 'Descenso de grado';
      case 'cambio_administrativo':
        return 'Cambio administrativo';
      default:
        return 'Reubicacion';
    }
  }

  Widget _buildRequestCard(_MoveRequestRow row) {
    final statusColor = _statusColor(row.status);
    final createdLabel =
        row.createdAt != null
            ? '${row.createdAt!.day.toString().padLeft(2, '0')}/${row.createdAt!.month.toString().padLeft(2, '0')}/${row.createdAt!.year}'
            : 'Sin fecha';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.studentName,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (row.matricula.isNotEmpty)
                          'Matricula ${row.matricula}',
                        row.schoolYear,
                        createdLabel,
                      ].join(' · '),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withOpacity(0.25)),
                ),
                child: Text(
                  _statusLabel(row.status),
                  style: TextStyle(
                    color: statusColor.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip('Origen', '${row.fromGradeName} · ${row.fromTanda}'),
              _infoChip('Destino', '${row.toGradeName} · ${row.toTanda}'),
              _infoChip('Tipo', _requestTypeLabel(row.requestType)),
              _infoChip('Docente', row.teacherName),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FC),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFE8ECF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 17, color: _blue),
                    SizedBox(width: 7),
                    Text(
                      'Motivo de la solicitud',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  row.reason.isEmpty ? 'Sin motivo adicional.' : row.reason,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (row.adminComment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFFFE2A5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    color: Color(0xFF9A6500),
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Comentario administrativo\n${row.adminComment}',
                      style: const TextStyle(color: _ink, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (row.status == 'pending') ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _rejectRequest(row),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB84040),
                    side: const BorderSide(color: Color(0xFFE5B8B8)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 13,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _executeRequest(row),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Aprobar y ejecutar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('Cambios de grado'),
        actions: [
          IconButton(
            tooltip: 'Actualizar solicitudes',
            onPressed: _loading || _saving ? null : _bootstrap,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      backgroundColor: _page,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final pagePadding = compact ? 13.0 : 24.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(pagePadding, 16, pagePadding, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHero(),
                  const SizedBox(height: 14),
                  _buildSummary(),
                  const SizedBox(height: 14),
                  _buildHeader(),
                  const SizedBox(height: 14),
                  Expanded(
                    child:
                        _loading
                            ? const Center(
                              child: CircularProgressIndicator(color: _blue),
                            )
                            : _visibleRows.isEmpty
                            ? Center(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 30,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFE5EAF2),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F2FA),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: const Icon(
                                        Icons.inbox_outlined,
                                        color: _blue,
                                        size: 29,
                                      ),
                                    ),
                                    const SizedBox(height: 13),
                                    const Text(
                                      'No hay solicitudes en esta bandeja',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    const Text(
                                      'Cuando un docente solicite un cambio de grado, aparecerá aquí.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _muted,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            : ListView.separated(
                              itemCount: _visibleRows.length,
                              padding: const EdgeInsets.only(bottom: 8),
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 13),
                              itemBuilder:
                                  (context, index) =>
                                      _buildRequestCard(_visibleRows[index]),
                            ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MoveRequestRow {
  final String id;
  final String studentId;
  final String studentName;
  final String matricula;
  final String schoolYear;
  final String fromGradeId;
  final String fromGradeName;
  final String fromTanda;
  final String toGradeId;
  final String toGradeName;
  final String toTanda;
  final String requestType;
  final String reason;
  final String teacherUid;
  final String teacherDocId;
  final String teacherName;
  final String status;
  final String adminComment;
  final DateTime? createdAt;

  const _MoveRequestRow({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.matricula,
    required this.schoolYear,
    required this.fromGradeId,
    required this.fromGradeName,
    required this.fromTanda,
    required this.toGradeId,
    required this.toGradeName,
    required this.toTanda,
    required this.requestType,
    required this.reason,
    required this.teacherUid,
    required this.teacherDocId,
    required this.teacherName,
    required this.status,
    required this.adminComment,
    required this.createdAt,
  });

  factory _MoveRequestRow.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _MoveRequestRow(
      id: doc.id,
      studentId: (data['studentId'] ?? '').toString().trim(),
      studentName: (data['studentName'] ?? '').toString().trim(),
      matricula: (data['matricula'] ?? '').toString().trim(),
      schoolYear: (data['schoolYear'] ?? '').toString().trim(),
      fromGradeId: (data['fromGradeId'] ?? '').toString().trim(),
      fromGradeName: (data['fromGradeName'] ?? '').toString().trim(),
      fromTanda: (data['fromTanda'] ?? '').toString().trim(),
      toGradeId: (data['toGradeId'] ?? '').toString().trim(),
      toGradeName: (data['toGradeName'] ?? '').toString().trim(),
      toTanda: (data['toTanda'] ?? '').toString().trim(),
      requestType: (data['requestType'] ?? 'reubicacion').toString().trim(),
      reason: (data['reason'] ?? '').toString().trim(),
      teacherUid: (data['teacherUid'] ?? '').toString().trim(),
      teacherDocId: (data['teacherDocId'] ?? '').toString().trim(),
      teacherName: (data['teacherName'] ?? 'Docente').toString().trim(),
      status: (data['status'] ?? 'pending').toString().trim().toLowerCase(),
      adminComment: (data['adminComment'] ?? '').toString().trim(),
      createdAt:
          data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : null,
    );
  }
}

class _GradeLite {
  final String id;
  final String label;
  final String nivel;

  const _GradeLite({
    required this.id,
    required this.label,
    required this.nivel,
  });
}
