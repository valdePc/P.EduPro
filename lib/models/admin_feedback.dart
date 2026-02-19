import 'package:cloud_firestore/cloud_firestore.dart';

/// Feedback interno del admin sobre un docente.
/// Colección sugerida: schools/{schoolId}/teachers/{teacherId}/admin_feedback/{feedbackId}
class AdminFeedback {
  final String id;

  final String schoolId;
  final String teacherId;

  /// Quién lo creó (admin/director/soporte)
  final String createdByUid;
  final String createdByName;

  /// Contenido
  final String title;
  final String message;

  /// Opcional: nivel/valoración
  final int? rating; // 1..5 (si lo usas)

  /// Estado
  final bool resolved;
  final bool archived;

  /// Fechas
  final DateTime createdAt;
  final DateTime updatedAt;

  AdminFeedback({
    required this.id,
    required this.schoolId,
    required this.teacherId,
    required this.createdByUid,
    required this.createdByName,
    required this.title,
    required this.message,
    this.rating,
    this.resolved = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  // -------------------------
  // Firestore mapping
  // -------------------------
  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'teacherId': teacherId,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'title': title,
      'message': message,
      if (rating != null) 'rating': rating,
      'resolved': resolved,
      'archived': archived,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Para guardar sin preocuparte por timestamps:
  Map<String, dynamic> toMapForCreate() {
    return {
      'schoolId': schoolId,
      'teacherId': teacherId,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'title': title,
      'message': message,
      if (rating != null) 'rating': rating,
      'resolved': resolved,
      'archived': archived,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {
      'title': title,
      'message': message,
      if (rating != null) 'rating': rating,
      'resolved': resolved,
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime _readDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.now();
  }

  static int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  factory AdminFeedback.fromMap(String id, Map<String, dynamic> map) {
    return AdminFeedback(
      id: id,
      schoolId: (map['schoolId'] ?? '').toString().trim(),
      teacherId: (map['teacherId'] ?? '').toString().trim(),
      createdByUid: (map['createdByUid'] ?? '').toString().trim(),
      createdByName: (map['createdByName'] ?? '').toString().trim(),
      title: (map['title'] ?? '').toString().trim(),
      message: (map['message'] ?? '').toString().trim(),
      rating: _readInt(map['rating']),
      resolved: (map['resolved'] is bool) ? map['resolved'] as bool : false,
      archived: (map['archived'] is bool) ? map['archived'] as bool : false,
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  factory AdminFeedback.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AdminFeedback.fromMap(doc.id, data);
  }
}
