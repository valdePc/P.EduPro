import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/equipo_edupro_access.dart';
import '../utils/school_document_id.dart';

/// A projected catalog record, never permission to read school collections.
class TeamSchoolRecord {
  TeamSchoolRecord(this.id, this._data, this.role);
  final String id;
  final String role;
  final Map<String, dynamic> _data;
  Map<String, dynamic> data() => _data;

  static Map<String, dynamic> decode(Map raw) => raw.map((key, value) {
    final name = '$key';
    if (value is num && name.endsWith('At')) {
      return MapEntry(
        name,
        Timestamp.fromMillisecondsSinceEpoch(value.toInt()),
      );
    }
    return MapEntry(name, value is Map ? decode(value) : value);
  });
}

class SchoolCatalogMetrics {
  const SchoolCatalogMetrics({
    required this.total,
    required this.active,
    required this.suspended,
    required this.draft,
    this.located,
  });
  final int total, active, suspended, draft;
  final int? located;
  int? get unlocated => located == null ? null : total - located!;

  factory SchoolCatalogMetrics.fromMap(Map raw) {
    int number(String field) {
      final value = raw[field];
      if (value is! int || value < 0) {
        throw const FormatException('Indicador inválido.');
      }
      return value;
    }

    final result = SchoolCatalogMetrics(
      total: number('total'),
      active: number('active'),
      suspended: number('suspended'),
      draft: number('draft'),
      located: raw['located'] == null ? null : number('located'),
    );
    if (result.active + result.suspended + result.draft > result.total ||
        (result.located ?? 0) > result.total) {
      throw const FormatException('Indicadores inconsistentes.');
    }
    return result;
  }
}

class SchoolCatalogPage {
  const SchoolCatalogPage({
    required this.records,
    required this.role,
    required this.nextCursor,
    this.matchingTotal,
    this.metrics,
  });
  final List<TeamSchoolRecord> records;
  final String role;
  final String? nextCursor;
  final int? matchingTotal;
  final SchoolCatalogMetrics? metrics;

  factory SchoolCatalogPage.fromMap(Map<String, dynamic> raw) {
    final role = raw['role'];
    final schools = raw['schools'];
    final cursor = raw['nextCursor'];
    final count = raw['matchingTotal'];
    if (role is! String ||
        !EquipoEduProRoles.all.contains(role) ||
        schools is! List ||
        schools.length > 25 ||
        cursor != null &&
            (cursor is! String ||
                !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(cursor)) ||
        count != null && (count is! int || count < 0)) {
      throw const FormatException('Página de colegios inválida.');
    }
    final ids = <String>{};
    final records = schools
        .map((item) {
          if (item is! Map || item['id'] is! String || item['data'] is! Map) {
            throw const FormatException('Colegio inválido.');
          }
          final id = item['id'] as String;
          if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
              isInternalSchoolDocumentId(id) ||
              !ids.add(id)) {
            throw const FormatException('Identificador de colegio inválido.');
          }
          return TeamSchoolRecord(
            id,
            TeamSchoolRecord.decode(item['data'] as Map),
            role,
          );
        })
        .toList(growable: false);
    final metrics = raw['metrics'];
    if (metrics != null && metrics is! Map) {
      throw const FormatException('Indicadores inválidos.');
    }
    return SchoolCatalogPage(
      records: List.unmodifiable(records),
      role: role,
      nextCursor: cursor as String?,
      matchingTotal: count as int?,
      metrics:
          metrics == null ? null : SchoolCatalogMetrics.fromMap(metrics as Map),
    );
  }
}
