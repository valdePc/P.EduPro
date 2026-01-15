import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/models/planificacion_model.dart';
import 'package:edupro/services/planificacion_service.dart';
import 'package:edupro/utils/school_utils.dart';

class APlanificacionAcademica extends StatefulWidget {
  final Escuela escuela;
  const APlanificacionAcademica({Key? key, required this.escuela}) : super(key: key);

  @override
  State<APlanificacionAcademica> createState() => _APlanificacionAcademicaState();
}

class _APlanificacionAcademicaState extends State<APlanificacionAcademica> {
  final PlanificacionService _service = PlanificacionService();
  late final String _schoolId;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  Future<void> _setupDefaultPeriodos() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _service.initDefaultRDPeriodos(_schoolId, DateTime.now().year);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Periodos escolares de RD configurados correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al configurar periodos: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF0D47A1);
    const naranja = Color(0xFFFFA000);
    const bg = Color(0xFFF4F7FB);

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        );
    final sectionTitleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        );
    final subtleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          height: 1.25,
        );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: azul,
        elevation: 0,
        toolbarHeight: 56,
        titleSpacing: 12,
        title: Text(
          'Planificación Académica',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              widget.escuela.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(
                      accent: naranja,
                      titleStyle: titleStyle,
                      subtleStyle: subtleStyle,
                    ),
                    const SizedBox(height: 12),
                    _buildPeriodosSection(
                      primary: azul,
                      sectionTitleStyle: sectionTitleStyle,
                      subtleStyle: subtleStyle,
                    ),
                    const SizedBox(height: 14),
                    _buildPlanAnualSection(
                      sectionTitleStyle: sectionTitleStyle,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard({
    required Color accent,
    TextStyle? titleStyle,
    TextStyle? subtleStyle,
  }) {
    return Card(
      elevation: 0.8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_stories_rounded, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gestión Curricular RD', style: titleStyle),
                  const SizedBox(height: 4),
                  Text(
                    'Configura periodos evaluativos y planificación anual alineada al MINERD.',
                    style: subtleStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodosSection({
    required Color primary,
    TextStyle? sectionTitleStyle,
    TextStyle? subtleStyle,
  }) {
    return Card(
      elevation: 0.8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Periodos Escolares (P1 - P4)',
                    style: sectionTitleStyle,
                  ),
                ),
                TextButton.icon(
                  onPressed: _setupDefaultPeriodos,
                  icon: Icon(
                    _loading ? Icons.hourglass_top_rounded : Icons.restore_rounded,
                    size: 18,
                  ),
                  label: Text(_loading ? 'Cargando...' : 'Estándar RD'),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<PeriodoAcademico>>(
              stream: _service.getPeriodos(_schoolId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildEmptyState('Error cargando periodos: ${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                final periodos = snapshot.data!;
                if (periodos.isEmpty) {
                  return _buildEmptyState(
                    'No hay periodos configurados. Usa “Estándar RD” para cargar los periodos.',
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: periodos.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final p = periodos[index];
                    final rango =
                        '${DateFormat('d MMM yyyy').format(p.inicio)} – ${DateFormat('d MMM yyyy').format(p.fin)}';

                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: primary.withOpacity(0.10),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      title: Text(
                        p.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      subtitle: Text(rango, style: subtleStyle),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (p.activo ? Colors.green : Colors.grey).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              p.activo ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                              size: 16,
                              color: p.activo ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              p.activo ? 'Activo' : 'Inactivo',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: p.activo ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanAnualSection({
    TextStyle? sectionTitleStyle,
  }) {
    return Card(
      elevation: 0.8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Planificación por Grados', style: sectionTitleStyle),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final crossAxisCount = w >= 520 ? 4 : (w >= 360 ? 2 : 1);
                final aspect = crossAxisCount >= 4 ? 1.05 : 1.35;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: aspect,
                  children: [
                    _buildPlanCard('Nivel Inicial', Icons.child_care_rounded, Colors.pink),
                    _buildPlanCard('Nivel Primario', Icons.menu_book_rounded, Colors.blue),
                    _buildPlanCard('Nivel Secundario', Icons.school_rounded, Colors.indigo),
                    _buildPlanCard('Especialidades', Icons.star_rounded, Colors.orange),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(String title, IconData icon, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abriendo planificación de $title...')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.grey.shade700, height: 1.25, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
