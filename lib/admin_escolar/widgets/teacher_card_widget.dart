import 'package:flutter/material.dart';

enum TeacherStatus { excellent, attention, critical }

/// Teacher summary with curriculum and attendance indicators.
class TeacherCard extends StatelessWidget {
  const TeacherCard({
    super.key,
    required this.name,
    required this.level,
    required this.grade,
    required this.curriculumScore,
    required this.attendanceRate,
    required this.status,
    this.onClick,
  });

  final String name;
  final String level;
  final String grade;
  final double curriculumScore;
  final double attendanceRate;
  final TeacherStatus status;
  final VoidCallback? onClick;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      TeacherStatus.excellent => (
        'Excelente',
        Icons.check_circle_outline,
        Colors.green,
      ),
      TeacherStatus.attention => (
        'Atención',
        Icons.warning_amber_outlined,
        Colors.amber.shade800,
      ),
      TeacherStatus.critical => ('Crítico', Icons.error_outline, Colors.red),
    };
    final theme = Theme.of(context);

    return Card(
      color: Color.alphaBlend(color.withValues(alpha: 0.08), theme.cardColor),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onClick,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleMedium),
                        Text(
                          '$level • $grade',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Icon(icon, color: color, semanticLabel: label),
                      Text(label, style: TextStyle(color: color)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Cumplimiento curricular',
                      value: curriculumScore,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(label: 'Asistencia', value: attendanceRate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final percentage =
        value.isFinite ? value.clamp(0.0, 100.0).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(
          '${percentage.round()}%',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: percentage / 100, minHeight: 5),
      ],
    );
  }
}
