class SchoolAccessLink {
  const SchoolAccessLink({required this.schoolId, required this.module});
  final String schoolId;
  final String module;

  static SchoolAccessLink? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.length > 4096) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    String schoolId;
    String module;
    try {
      if (scheme == 'eduproapp' || scheme == 'valmichapp') {
        if (uri.pathSegments.length != 1) return null;
        schoolId = uri.host;
        module = uri.pathSegments.single.toLowerCase();
      } else {
        if (scheme.isNotEmpty && scheme != 'https' && scheme != 'http') {
          return null;
        }
        var segments = uri.pathSegments;
        if (segments.isEmpty && uri.fragment.isNotEmpty) {
          final fragment = Uri.tryParse(uri.fragment);
          if (fragment == null) return null;
          segments = fragment.pathSegments;
        }
        if (segments.length != 3 || segments.first.toLowerCase() != 'eduproapp') {
          return null;
        }
        schoolId = segments[1];
        module = segments[2].toLowerCase();
      }
    } on FormatException {
      return null;
    }
    if (schoolId.isEmpty ||
        schoolId == '.' ||
        schoolId == '..' ||
        RegExp(r'[\x00-\x20\x7f/\\]').hasMatch(schoolId) ||
        !const {'admin', 'admincole', 'doc', 'docentes', 'alum', 'alumnos'}
            .contains(module)) {
      return null;
    }
    return SchoolAccessLink(schoolId: schoolId, module: module);
  }
}
