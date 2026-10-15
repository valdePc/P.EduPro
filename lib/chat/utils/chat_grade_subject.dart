class ChatGradeSubjectTarget {
  final String gradeId;
  final String gradeName;
  final String subjectId;
  final String subjectName;

  const ChatGradeSubjectTarget({
    required this.gradeId,
    required this.gradeName,
    required this.subjectId,
    required this.subjectName,
  });

  String get threadId => buildChatGradeSubjectThreadId(gradeId, subjectId);

  String get title {
    final grade = gradeName.trim().isEmpty ? gradeId.trim() : gradeName.trim();
    final subject =
        subjectName.trim().isEmpty ? subjectId.trim() : subjectName.trim();
    return '$grade - $subject';
  }
}

String buildChatGradeSubjectThreadId(String gradeId, String subjectId) {
  final gid = gradeId.trim();
  final sid = subjectId.trim();
  if (gid.isEmpty || sid.isEmpty) return '';
  return '${gid}__${sid}';
}
