/// Progress against a curricular target for a school reporting period.
class CurricularProgress {
  const CurricularProgress({
    required this.period,
    required this.completed,
    required this.target,
  });

  final String period;
  final double completed;
  final double target;

  factory CurricularProgress.fromMap(Map<String, dynamic> data) {
    double number(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CurricularProgress(
      period: (data['period'] ?? '').toString(),
      completed: number(data['completed']),
      target: number(data['target']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'period': period,
    'completed': completed,
    'target': target,
  };
}
