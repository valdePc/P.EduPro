import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/escuela.dart';
import '../../models/planificacion_model.dart';
import '../../services/planificacion_service.dart';
import '../../utils/school_utils.dart';
import '../widgets/docente_app_bar.dart';

class PlanificacionesScreen extends StatefulWidget {
  final Escuela escuela;
  const PlanificacionesScreen({super.key, required this.escuela});

  @override
  State<PlanificacionesScreen> createState() => _PlanificacionesScreenState();
}

class _PlanificacionesScreenState extends State<PlanificacionesScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _service = PlanificacionService();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _intro = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _schoolId = '';
  String? _teacherDocId;
  String _teacherName = 'Docente';
  List<PeriodoAcademico> _periodos = const [];
  List<_Opt> _grados = const [];
  List<_Opt> _materias = const [];
  late final List<String> _years;
  String? _year;
  String? _gradoId;
  String? _gradoName;
  String? _materiaId;
  String? _materiaName;
  PlanTemplateStyle _style = const PlanTemplateStyle();
  List<UnidadDidactica> _units = [];
  static const List<String> _fontOptions = [
    'Roboto',
    'Montserrat',
    'Lato',
    'Poppins',
    'Nunito',
    'Merriweather',
  ];

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    _years = List.generate(4, (i) => '${start + i}-${start + i + 1}');
    _year = _years.first;
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _intro.dispose();
    super.dispose();
  }

  List<String> _list(dynamic v) => v is List
      ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
      : (v is String && v.trim().isNotEmpty ? [v.trim()] : const []);

  String _norm(String s) {
    const m = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n'};
    return s.toLowerCase().split('').map((c) => m[c] ?? c).join().trim();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Sesion no disponible.');
      final uid = user.uid;
      final emailLower = (user.email ?? '').trim().toLowerCase();
      String? teacherId;
      final uidDoc = await _db.collection('schools').doc(_schoolId).collection('teachers_uid').doc(uid).get();
      if (uidDoc.exists) teacherId = (uidDoc.data()?['teacherDocId'] ?? '').toString().trim();
      if (teacherId == null || teacherId.isEmpty) {
        final q = await _db.collection('schools').doc(_schoolId).collection('teachers').where('authUid', isEqualTo: uid).limit(1).get();
        if (q.docs.isNotEmpty) teacherId = q.docs.first.id;
      }
      if ((teacherId == null || teacherId.isEmpty) && emailLower.isNotEmpty) {
        final q = await _db.collection('schools').doc(_schoolId).collection('teachers').where('emailLower', isEqualTo: emailLower).limit(1).get();
        if (q.docs.isNotEmpty) teacherId = q.docs.first.id;
      }
      if (teacherId == null || teacherId.isEmpty) throw Exception('No se pudo resolver el docente.');
      final teacherDoc = await _db.collection('schools').doc(_schoolId).collection('teachers').doc(teacherId).get();
      final teacher = teacherDoc.data() ?? <String, dynamic>{};
      _teacherDocId = teacherId;
      _teacherName = (teacher['nombreCompleto'] ?? teacher['name'] ?? teacher['nombre'] ?? 'Docente').toString();
      final gradeIds = {..._list(teacher['gradeIds']), ..._list(teacher['gradoIds']), ..._list(teacher['gradesIds'])};
      final subjectNames = {..._list(teacher['subjects']), ..._list(teacher['materias']), ..._list(teacher['asignaturas'])};

      final gSnap = await _db.collection('schools').doc(_schoolId).collection('grados').get();
      _grados = gSnap.docs
          .where((d) => gradeIds.isEmpty || gradeIds.contains(d.id))
          .map((d) => _Opt(d.id, (d.data()['nombre'] ?? d.data()['name'] ?? d.id).toString()))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      final sSnap = await _db.collection('schools').doc(_schoolId).collection('subjects').get();
      _materias = sSnap.docs
          .where((d) {
            if (subjectNames.isEmpty) return true;
            final name = (d.data()['name'] ?? d.data()['nombre'] ?? d.id).toString();
            return subjectNames.any((e) => _norm(e) == _norm(name));
          })
          .map((d) => _Opt(d.id, (d.data()['name'] ?? d.data()['nombre'] ?? d.id).toString()))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      _gradoId ??= _grados.isNotEmpty ? _grados.first.id : null;
      _gradoName ??= _grados.isNotEmpty ? _grados.first.label : null;
      _materiaId ??= _materias.isNotEmpty ? _materias.first.id : null;
      _materiaName ??= _materias.isNotEmpty ? _materias.first.label : null;
      _periodos = await _service.getPeriodos(_schoolId).first;
      if (_periodos.isEmpty) {
        final y = int.tryParse((_year ?? '').split('-').first) ?? DateTime.now().year;
        _periodos = [
          PeriodoAcademico(id: 'p1', nombre: 'P1', inicio: DateTime(y, 8, 20), fin: DateTime(y, 10, 31)),
          PeriodoAcademico(id: 'p2', nombre: 'P2', inicio: DateTime(y, 11, 1), fin: DateTime(y, 12, 20)),
          PeriodoAcademico(id: 'p3', nombre: 'P3', inicio: DateTime(y + 1, 1, 7), fin: DateTime(y + 1, 3, 31)),
          PeriodoAcademico(id: 'p4', nombre: 'P4', inicio: DateTime(y + 1, 4, 1), fin: DateTime(y + 1, 6, 20)),
        ];
      }
      await _loadPlan();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPlan() async {
    if (_teacherDocId == null || _gradoId == null || _materiaId == null || _year == null) return;
    final plan = await _service.getPlanAnual(
      schoolId: _schoolId,
      teacherDocId: _teacherDocId!,
      anioEscolar: _year!,
      gradeId: _gradoId!,
      asignaturaId: _materiaId!,
    );
    final p = plan ??
        PlanificacionAnual(
          id: _service.buildPlanDocId(teacherDocId: _teacherDocId!, anioEscolar: _year!, gradeId: _gradoId!, asignaturaId: _materiaId!),
          schoolId: _schoolId,
          schoolName: widget.escuela.nombre,
          anioEscolar: _year!,
          anio: int.tryParse((_year ?? '').split('-').first) ?? DateTime.now().year,
          nivel: '',
          grado: _gradoName ?? '',
          gradeId: _gradoId!,
          asignatura: _materiaName ?? '',
          asignaturaId: _materiaId!,
          teacherDocId: _teacherDocId!,
          teacherUid: _auth.currentUser?.uid ?? '',
          teacherName: _teacherName,
          secciones: const [],
          templateTitle: 'Planificacion anual de ${_materiaName ?? 'asignatura'}',
          templateSubtitle: '${_gradoName ?? ''} | ${_year ?? ''}',
          introductoryNote: 'Plan editable para organizar el ano escolar.',
          unidades: _periodos.map((e) => UnidadDidactica(id: 'u_${e.id}', periodoId: e.id, titulo: 'Unidad ${e.nombre}')).toList(),
          style: _style,
        );
    _style = p.style;
    _title.text = p.templateTitle;
    _subtitle.text = p.templateSubtitle;
    _intro.text = p.introductoryNote;
    _units = List<UnidadDidactica>.from(p.unidades);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_teacherDocId == null || _gradoId == null || _materiaId == null || _year == null) return;
    setState(() => _saving = true);
    try {
      await _service.savePlanAnual(PlanificacionAnual(
        id: _service.buildPlanDocId(teacherDocId: _teacherDocId!, anioEscolar: _year!, gradeId: _gradoId!, asignaturaId: _materiaId!),
        schoolId: _schoolId,
        schoolName: widget.escuela.nombre,
        anioEscolar: _year!,
        anio: int.tryParse((_year ?? '').split('-').first) ?? DateTime.now().year,
        nivel: '',
        grado: _gradoName ?? '',
        gradeId: _gradoId!,
        asignatura: _materiaName ?? '',
        asignaturaId: _materiaId!,
        teacherDocId: _teacherDocId!,
        teacherUid: _auth.currentUser?.uid ?? '',
        teacherName: _teacherName,
        secciones: const [],
        templateTitle: _title.text.trim(),
        templateSubtitle: _subtitle.text.trim(),
        introductoryNote: _intro.text.trim(),
        unidades: _units,
        style: _style,
      ));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planificacion guardada.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  String? _safeDropdownValue(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return null;
    return options.contains(value) ? value : null;
  }

  List<DropdownMenuItem<String>> _buildDropdownItems(
    List<_Opt> options,
  ) {
    return options
        .map(
          (e) => DropdownMenuItem<String>(
            value: e.id,
            child: Text(
              e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: buildDocenteBackAppBar(context), body: const Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: buildDocenteBackAppBar(context), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))));
    final accent = Color(_style.accentColor);
    final textColor = Color(_style.textColor);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: buildDocenteBackAppBar(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Planificacion Academica', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Plantilla anual editable por grado y asignatura.'),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    value: _year,
                    isExpanded: true,
                    decoration: _dec('Ano escolar'),
                    items: _years
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e,
                            child: Text(
                              e,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      _year = v;
                      await _loadPlan();
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _gradoId,
                    isExpanded: true,
                    decoration: _dec('Grado'),
                    items: _buildDropdownItems(_grados),
                    onChanged: (v) async {
                      if (v == null) return;
                      final o = _grados.firstWhere((e) => e.id == v);
                      _gradoId = o.id;
                      _gradoName = o.label;
                      await _loadPlan();
                    },
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<String>(
                    value: _materiaId,
                    isExpanded: true,
                    decoration: _dec('Asignatura'),
                    items: _buildDropdownItems(_materias),
                    selectedItemBuilder: (context) => _materias
                        .map(
                          (e) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              e.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      final o = _materias.firstWhere((e) => e.id == v);
                      _materiaId = o.id;
                      _materiaName = o.label;
                      await _loadPlan();
                    },
                  ),
                ),
              ])
            ]),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 1100;
            final editor = _editor(accent);
            final preview = _preview(accent, textColor);
            return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: editor), const SizedBox(width: 20), Expanded(child: preview)]) : Column(children: [editor, const SizedBox(height: 20), preview]);
          }),
          const SizedBox(height: 20),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _style = const PlanTemplateStyle()),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restablecer estilo'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando...' : 'Guardar plan'),
            )
          ])
        ]),
      ),
    );
  }

  Widget _editor(Color accent) {
    return Column(children: [
      _card('Estructura base', Column(children: [
        TextField(controller: _title, decoration: _dec('Titulo')),
        const SizedBox(height: 12),
        TextField(controller: _subtitle, decoration: _dec('Subtitulo')),
        const SizedBox(height: 12),
        TextField(controller: _intro, decoration: _dec('Introduccion'), minLines: 3, maxLines: 5),
      ])),
      const SizedBox(height: 20),
      _card('Personalizacion', Column(children: [
        DropdownButtonFormField<String>(
          value: _safeDropdownValue(_style.fontFamily, _fontOptions) ?? _fontOptions.first,
          isExpanded: true,
          decoration: _dec('Tipografia'),
          items: _fontOptions
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _style = _style.copyWith(fontFamily: v ?? _style.fontFamily)),
        ),
        Slider(value: _style.titleFontSize, min: 20, max: 40, divisions: 20, label: _style.titleFontSize.round().toString(), onChanged: (v) => setState(() => _style = _style.copyWith(titleFontSize: v))),
        Slider(value: _style.headingFontSize, min: 14, max: 28, divisions: 14, label: _style.headingFontSize.round().toString(), onChanged: (v) => setState(() => _style = _style.copyWith(headingFontSize: v))),
        Slider(value: _style.bodyFontSize, min: 11, max: 22, divisions: 11, label: _style.bodyFontSize.round().toString(), onChanged: (v) => setState(() => _style = _style.copyWith(bodyFontSize: v))),
        Wrap(spacing: 10, runSpacing: 10, children: _palette((v) => _style = _style.copyWith(accentColor: v), _style.accentColor)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: _palette((v) => _style = _style.copyWith(cardColor: v), _style.cardColor)),
      ])),
      const SizedBox(height: 20),
      _card(
        'Unidades didacticas',
        Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => setState(() => _units.add(UnidadDidactica(id: 'u_${DateTime.now().millisecondsSinceEpoch}', periodoId: _periodos.first.id, titulo: 'Nueva unidad'))),
              icon: const Icon(Icons.add),
              label: const Text('Agregar unidad'),
            ),
          ),
          const SizedBox(height: 12),
          ..._units.asMap().entries.map((entry) {
            final i = entry.key;
            final u = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
              child: ExpansionTile(
                title: Text(u.titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(_periodos.firstWhere((p) => p.id == u.periodoId, orElse: () => _periodos.first).nombre),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  DropdownButtonFormField<String>(
                    value: u.periodoId,
                    isExpanded: true,
                    decoration: _dec('Periodo'),
                    items: _periodos
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(
                              p.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final p = _periodos.firstWhere((e) => e.id == v);
                      setState(() => _units[i] = u.copyWith(periodoId: p.id));
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.titulo, decoration: _dec('Titulo de la unidad'), onChanged: (v) => _units[i] = _units[i].copyWith(titulo: v)),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.mes, decoration: _dec('Rango / mes'), onChanged: (v) => _units[i] = _units[i].copyWith(mes: v)),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.situacionAprendizaje, decoration: _dec('Situacion de aprendizaje'), minLines: 2, maxLines: 3, onChanged: (v) => _units[i] = _units[i].copyWith(situacionAprendizaje: v)),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.competenciasEspecificas.join('\n'), decoration: _dec('Competencias especificas'), minLines: 3, maxLines: 5, onChanged: (v) => _units[i] = _units[i].copyWith(competenciasEspecificas: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.contenidos.join('\n'), decoration: _dec('Contenidos'), minLines: 3, maxLines: 5, onChanged: (v) => _units[i] = _units[i].copyWith(contenidos: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.actividades.join('\n'), decoration: _dec('Actividades'), minLines: 3, maxLines: 5, onChanged: (v) => _units[i] = _units[i].copyWith(actividades: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.recursos.join('\n'), decoration: _dec('Recursos'), minLines: 3, maxLines: 5, onChanged: (v) => _units[i] = _units[i].copyWith(recursos: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())),
                  const SizedBox(height: 12),
                  TextFormField(initialValue: u.evaluacion.join('\n'), decoration: _dec('Evaluacion'), minLines: 3, maxLines: 5, onChanged: (v) => _units[i] = _units[i].copyWith(evaluacion: v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())),
                  Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => setState(() => _units.removeAt(i)), icon: const Icon(Icons.delete_outline), label: const Text('Eliminar unidad'))),
                ],
              ),
            );
          }),
        ]),
      ),
    ]);
  }

  Widget _preview(Color accent, Color textColor) {
    return _card(
      'Vista previa',
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Color(_style.cardColor), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title.text.isEmpty ? 'Planificacion anual' : _title.text, style: TextStyle(fontSize: _style.titleFontSize, fontWeight: FontWeight.w900, color: textColor, fontFamily: _style.fontFamily)),
          const SizedBox(height: 6),
          Text(_subtitle.text.isEmpty ? '${_gradoName ?? ''} | ${_materiaName ?? ''}' : _subtitle.text, style: TextStyle(fontSize: _style.headingFontSize, color: textColor.withOpacity(0.75), fontFamily: _style.fontFamily)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _tag(accent, _year ?? ''),
            _tag(accent, _gradoName ?? ''),
            _tag(accent, _materiaName ?? ''),
            _tag(accent, _teacherName),
          ]),
          if (_intro.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_intro.text.trim(), style: TextStyle(fontSize: _style.bodyFontSize, color: textColor, fontFamily: _style.fontFamily)),
          ],
          const SizedBox(height: 16),
          ..._units.map((u) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: accent.withOpacity(0.18))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_periodos.firstWhere((p) => p.id == u.periodoId, orElse: () => _periodos.first).nombre} | ${u.titulo}', style: TextStyle(fontSize: _style.headingFontSize, fontWeight: FontWeight.w800, color: textColor, fontFamily: _style.fontFamily)),
                  if (u.situacionAprendizaje.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(u.situacionAprendizaje, style: TextStyle(fontSize: _style.bodyFontSize, color: textColor, fontFamily: _style.fontFamily)),
                  ],
                  if (u.competenciasEspecificas.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Competencias', style: TextStyle(fontWeight: FontWeight.w800, color: accent, fontFamily: _style.fontFamily)),
                    ...u.competenciasEspecificas.take(4).map((e) => Text('• $e', style: TextStyle(fontSize: _style.bodyFontSize, color: textColor, fontFamily: _style.fontFamily))),
                  ],
                ]),
              )),
        ]),
      ),
    );
  }

  List<Widget> _palette(ValueChanged<int> onSelect, int current) => const [
        _ColorChoice('Azul', Color(0xFF0D47A1)),
        _ColorChoice('Naranja', Color(0xFFF59E0B)),
        _ColorChoice('Verde', Color(0xFF2E7D32)),
        _ColorChoice('Rojo', Color(0xFFC62828)),
        _ColorChoice('Gris', Color(0xFF455A64)),
        _ColorChoice('Crema', Color(0xFFF4E7CF)),
        _ColorChoice('Blanco', Colors.white),
      ].map((c) {
        final active = c.color.value == current;
        return InkWell(
          onTap: () => setState(() => onSelect(c.color.value)),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? c.color : Colors.grey.shade300, width: active ? 2 : 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 18, height: 18, decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.black12))),
              const SizedBox(width: 8),
              Text(c.label),
            ]),
          ),
        );
      }).toList();

  Widget _card(String title, Widget child) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget _tag(Color color, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      );
}

class _Opt {
  final String id;
  final String label;
  const _Opt(this.id, this.label);
}

class _ColorChoice {
  final String label;
  final Color color;
  const _ColorChoice(this.label, this.color);
}
