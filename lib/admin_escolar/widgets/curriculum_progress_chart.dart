import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/curricular_progress.dart';

/// Completed curricular work and target by reporting period.
class CurriculumProgressChart extends StatelessWidget {
  const CurriculumProgressChart({super.key, required this.data});

  final List<CurricularProgress> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 320,
          child: Center(child: Text('No hay datos de avance curricular.')),
        ),
      );
    }

    final maxValue = data.fold<double>(0, (max, item) {
      final completed = item.completed.isFinite ? item.completed : 0.0;
      final target = item.target.isFinite ? item.target : 0.0;
      return [max, completed, target].reduce((a, b) => a > b ? a : b);
    });
    final completedColor = Theme.of(context).colorScheme.primary;
    const targetColor = Color(0xFFFFA000);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avance curricular por período',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                _LegendEntry(label: 'Completadas', color: completedColor),
                const _LegendEntry(label: 'Meta', color: targetColor),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LayoutBuilder(
                builder:
                    (context, limits) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width:
                            data.length * 64 > limits.maxWidth
                                ? data.length * 64.0
                                : limits.maxWidth,
                        child: _buildChart(
                          maxValue,
                          completedColor,
                          targetColor,
                        ),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(double maxValue, Color completedColor, Color targetColor) {
    return BarChart(
      BarChartData(
        maxY: maxValue > 0 ? maxValue * 1.15 : 1,
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY:
                      data[i].completed.isFinite
                          ? data[i].completed
                              .clamp(0, double.infinity)
                              .toDouble()
                          : 0,
                  color: completedColor,
                  width: 12,
                ),
                BarChartRodData(
                  toY:
                      data[i].target.isFinite
                          ? data[i].target.clamp(0, double.infinity).toDouble()
                          : 0,
                  color: targetColor,
                  width: 12,
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length || value != index)
                  return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    data[index].period,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.square, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}
