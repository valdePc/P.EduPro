// lib/utils/school_utils.dart
String normalizeSchoolIdFromEscuela(dynamic escuela) {
  // intenta id -> adminLink -> nombre -> fallback hash
  String? raw;
  try {
    final cand = (escuela as dynamic).id;
    if (cand is String && cand.trim().isNotEmpty) raw = cand.trim();
  } catch (_) {}

  if (raw == null) {
    try {
      final cand = (escuela as dynamic).adminLink;
      if (cand is String && cand.trim().isNotEmpty) raw = cand.trim();
    } catch (_) {}
  }

  if (raw == null) {
    try {
      final cand = (escuela as dynamic).nombre;
      if (cand is String && cand.trim().isNotEmpty) raw = cand.trim();
    } catch (_) {}
  }

  raw ??= 'school-${escuela.hashCode}';

  // normalizar: quitar esquema, colapsar slashes, reemplazar por _
  var normalized = raw.replaceAll(RegExp(r'https?:\/\/'), '');
  normalized = normalized.replaceAll(RegExp(r'\/\/+'), '/');
  normalized = normalized.replaceAll('/', '_');
  normalized = normalized.replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '');

  if (normalized.isEmpty) normalized = 'school-${escuela.hashCode}';
  return normalized;
}
