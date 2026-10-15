import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoPeriodo { bimestre, trimestre, semestre }

DateTime? _readDateOrNull(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (value is String) {
    return value
        .split(RegExp(r'[\n,;]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

int _readColor(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return fallback;
    if (raw.startsWith('#')) {
      return int.tryParse(raw.substring(1), radix: 16) ?? fallback;
    }
    return int.tryParse(raw) ?? fallback;
  }
  return fallback;
}

double _readDouble(dynamic value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

class PeriodoAcademico {
  final String id;
  final String nombre;
  final DateTime inicio;
  final DateTime fin;
  final bool activo;

  PeriodoAcademico({
    required this.id,
    required this.nombre,
    required this.inicio,
    required this.fin,
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'inicio': Timestamp.fromDate(inicio),
        'fin': Timestamp.fromDate(fin),
        'activo': activo,
      };

  factory PeriodoAcademico.fromMap(String id, Map<String, dynamic> map) {
    return PeriodoAcademico(
      id: id,
      nombre: (map['nombre'] ?? '').toString(),
      inicio: _readDateOrNull(map['inicio']) ?? DateTime.now(),
      fin: _readDateOrNull(map['fin']) ?? DateTime.now(),
      activo: (map['activo'] is bool) ? map['activo'] as bool : true,
    );
  }
}

class PlanTemplateStyle {
  final String fontFamily;
  final double titleFontSize;
  final double bodyFontSize;
  final double headingFontSize;
  final int textColor;
  final int accentColor;
  final int pageColor;
  final int cardColor;
  final int borderColor;
  final double borderRadius;
  final double lineSpacing;

  const PlanTemplateStyle({
    this.fontFamily = 'Roboto',
    this.titleFontSize = 24,
    this.bodyFontSize = 14,
    this.headingFontSize = 16,
    this.textColor = 0xFF1F2937,
    this.accentColor = 0xFF0D47A1,
    this.pageColor = 0xFFF7FAFC,
    this.cardColor = 0xFFFFFFFF,
    this.borderColor = 0xFFE2E8F0,
    this.borderRadius = 18,
    this.lineSpacing = 1.35,
  });

  Map<String, dynamic> toMap() => {
        'fontFamily': fontFamily,
        'titleFontSize': titleFontSize,
        'bodyFontSize': bodyFontSize,
        'headingFontSize': headingFontSize,
        'textColor': textColor,
        'accentColor': accentColor,
        'pageColor': pageColor,
        'cardColor': cardColor,
        'borderColor': borderColor,
        'borderRadius': borderRadius,
        'lineSpacing': lineSpacing,
      };

  factory PlanTemplateStyle.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return PlanTemplateStyle(
      fontFamily: (data['fontFamily'] ?? 'Roboto').toString(),
      titleFontSize: _readDouble(data['titleFontSize'], 24),
      bodyFontSize: _readDouble(data['bodyFontSize'], 14),
      headingFontSize: _readDouble(data['headingFontSize'], 16),
      textColor: _readColor(data['textColor'], 0xFF1F2937),
      accentColor: _readColor(data['accentColor'], 0xFF0D47A1),
      pageColor: _readColor(data['pageColor'], 0xFFF7FAFC),
      cardColor: _readColor(data['cardColor'], 0xFFFFFFFF),
      borderColor: _readColor(data['borderColor'], 0xFFE2E8F0),
      borderRadius: _readDouble(data['borderRadius'], 18),
      lineSpacing: _readDouble(data['lineSpacing'], 1.35),
    );
  }

  PlanTemplateStyle copyWith({
    String? fontFamily,
    double? titleFontSize,
    double? bodyFontSize,
    double? headingFontSize,
    int? textColor,
    int? accentColor,
    int? pageColor,
    int? cardColor,
    int? borderColor,
    double? borderRadius,
    double? lineSpacing,
  }) {
    return PlanTemplateStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
      headingFontSize: headingFontSize ?? this.headingFontSize,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      pageColor: pageColor ?? this.pageColor,
      cardColor: cardColor ?? this.cardColor,
      borderColor: borderColor ?? this.borderColor,
      borderRadius: borderRadius ?? this.borderRadius,
      lineSpacing: lineSpacing ?? this.lineSpacing,
    );
  }
}

class UnidadDidactica {
  final String id;
  final String periodoId;
  final String titulo;
  final String mes;
  final int encuentros;
  final String situacionAprendizaje;
  final String competenciaFundamental;
  final List<String> competenciasEspecificas;
  final List<String> contenidos;
  final List<String> estrategias;
  final List<String> actividades;
  final List<String> recursos;
  final List<String> indicadoresLogro;
  final List<String> evidencias;
  final List<String> evaluacion;
  final String observaciones;

  const UnidadDidactica({
    required this.id,
    required this.periodoId,
    required this.titulo,
    this.mes = '',
    this.encuentros = 0,
    this.situacionAprendizaje = '',
    this.competenciaFundamental = '',
    this.competenciasEspecificas = const [],
    this.contenidos = const [],
    this.estrategias = const [],
    this.actividades = const [],
    this.recursos = const [],
    this.indicadoresLogro = const [],
    this.evidencias = const [],
    this.evaluacion = const [],
    this.observaciones = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'unidadId': id,
        'periodoId': periodoId,
        'periodo': periodoId,
        'titulo': titulo,
        'mes': mes,
        'encuentros': encuentros,
        'cantidadEncuentros': encuentros,
        'situacionAprendizaje': situacionAprendizaje,
        'competenciaFundamental': competenciaFundamental,
        'competenciasEspecificas': competenciasEspecificas,
        'contenidos': contenidos,
        'estrategias': estrategias,
        'actividades': actividades,
        'recursos': recursos,
        'indicadoresLogro': indicadoresLogro,
        'indicadores': indicadoresLogro,
        'evidencias': evidencias,
        'evaluacion': evaluacion,
        'observaciones': observaciones,
      };

  factory UnidadDidactica.fromMap(Map<String, dynamic> map) {
    return UnidadDidactica(
      id: (map['id'] ?? map['unidadId'] ?? '').toString(),
      periodoId: (map['periodoId'] ?? map['periodo'] ?? map['periodoAcademico'] ?? 'P1').toString(),
      titulo: (map['titulo'] ?? '').toString(),
      mes: (map['mes'] ?? '').toString(),
      encuentros: (map['encuentros'] is num)
          ? (map['encuentros'] as num).toInt()
          : ((map['cantidadEncuentros'] is num) ? (map['cantidadEncuentros'] as num).toInt() : 0),
      situacionAprendizaje: (map['situacionAprendizaje'] ?? '').toString(),
      competenciaFundamental: (map['competenciaFundamental'] ?? '').toString(),
      competenciasEspecificas: _asStringList(map['competenciasEspecificas']),
      contenidos: _asStringList(map['contenidos']),
      estrategias: _asStringList(map['estrategias']),
      actividades: _asStringList(map['actividades']),
      recursos: _asStringList(map['recursos']),
      indicadoresLogro: _asStringList(map['indicadoresLogro'].toString().isNotEmpty ? map['indicadoresLogro'] : map['indicadores']),
      evidencias: _asStringList(map['evidencias']),
      evaluacion: _asStringList(map['evaluacion']),
      observaciones: (map['observaciones'] ?? '').toString(),
    );
  }

  UnidadDidactica copyWith({
    String? id,
    String? periodoId,
    String? titulo,
    String? mes,
    int? encuentros,
    String? situacionAprendizaje,
    String? competenciaFundamental,
    List<String>? competenciasEspecificas,
    List<String>? contenidos,
    List<String>? estrategias,
    List<String>? actividades,
    List<String>? recursos,
    List<String>? indicadoresLogro,
    List<String>? evidencias,
    List<String>? evaluacion,
    String? observaciones,
  }) {
    return UnidadDidactica(
      id: id ?? this.id,
      periodoId: periodoId ?? this.periodoId,
      titulo: titulo ?? this.titulo,
      mes: mes ?? this.mes,
      encuentros: encuentros ?? this.encuentros,
      situacionAprendizaje: situacionAprendizaje ?? this.situacionAprendizaje,
      competenciaFundamental: competenciaFundamental ?? this.competenciaFundamental,
      competenciasEspecificas: competenciasEspecificas ?? this.competenciasEspecificas,
      contenidos: contenidos ?? this.contenidos,
      estrategias: estrategias ?? this.estrategias,
      actividades: actividades ?? this.actividades,
      recursos: recursos ?? this.recursos,
      indicadoresLogro: indicadoresLogro ?? this.indicadoresLogro,
      evidencias: evidencias ?? this.evidencias,
      evaluacion: evaluacion ?? this.evaluacion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

class PlanificacionAnual {
  final String id;
  final String schoolId;
  final String schoolName;
  final String anioEscolar;
  final int anio;
  final String nivel;
  final String grado;
  final String gradeId;
  final String asignatura;
  final String asignaturaId;
  final String teacherDocId;
  final String teacherUid;
  final String teacherName;
  final List<String> secciones;
  final String templateTitle;
  final String templateSubtitle;
  final String introductoryNote;
  final PlanTemplateStyle style;
  final List<UnidadDidactica> unidades;

  const PlanificacionAnual({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.anioEscolar,
    required this.anio,
    required this.nivel,
    required this.grado,
    required this.gradeId,
    required this.asignatura,
    required this.asignaturaId,
    required this.teacherDocId,
    required this.teacherUid,
    required this.teacherName,
    this.secciones = const [],
    this.templateTitle = '',
    this.templateSubtitle = '',
    this.introductoryNote = '',
    this.style = const PlanTemplateStyle(),
    this.unidades = const [],
  });

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'schoolName': schoolName,
        'anioEscolar': anioEscolar,
        'anio': anio,
        'nivel': nivel,
        'grado': grado,
        'gradeId': gradeId,
        'asignatura': asignatura,
        'asignaturaId': asignaturaId,
        'teacherDocId': teacherDocId,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'createdByUid': teacherUid,
        'secciones': secciones,
        'templateTitle': templateTitle,
        'templateSubtitle': templateSubtitle,
        'introductoryNote': introductoryNote,
        'style': style.toMap(),
        'unidades': unidades.map((u) => u.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory PlanificacionAnual.fromMap(String id, Map<String, dynamic> map) {
    final raw = map['unidades'] ?? map['unidadesDidacticas'] ?? map['listaUnidades'];
    final unidades = (raw is List)
        ? raw
            .where((e) => e is Map)
            .map((e) => UnidadDidactica.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <UnidadDidactica>[];

    final anioEscolar = (map['anioEscolar'] ?? '').toString();
    final anio = (map['anio'] is num)
        ? (map['anio'] as num).toInt()
        : int.tryParse(anioEscolar.split('-').first) ?? DateTime.now().year;

    return PlanificacionAnual(
      id: id,
      schoolId: (map['schoolId'] ?? '').toString(),
      schoolName: (map['schoolName'] ?? '').toString(),
      anioEscolar: anioEscolar,
      anio: anio,
      nivel: (map['nivel'] ?? '').toString(),
      grado: (map['grado'] ?? '').toString(),
      gradeId: (map['gradeId'] ?? '').toString(),
      asignatura: (map['asignatura'] ?? '').toString(),
      asignaturaId: (map['asignaturaId'] ?? '').toString(),
      teacherDocId: (map['teacherDocId'] ?? '').toString(),
      teacherUid: (map['teacherUid'] ?? map['createdByUid'] ?? '').toString(),
      teacherName: (map['teacherName'] ?? '').toString(),
      secciones: _asStringList(map['secciones']),
      templateTitle: (map['templateTitle'] ?? '').toString(),
      templateSubtitle: (map['templateSubtitle'] ?? '').toString(),
      introductoryNote: (map['introductoryNote'] ?? '').toString(),
      style: PlanTemplateStyle.fromMap(
        map['style'] is Map ? Map<String, dynamic>.from(map['style'] as Map) : null,
      ),
      unidades: unidades,
    );
  }

  PlanificacionAnual copyWith({
    String? id,
    String? schoolId,
    String? schoolName,
    String? anioEscolar,
    int? anio,
    String? nivel,
    String? grado,
    String? gradeId,
    String? asignatura,
    String? asignaturaId,
    String? teacherDocId,
    String? teacherUid,
    String? teacherName,
    List<String>? secciones,
    String? templateTitle,
    String? templateSubtitle,
    String? introductoryNote,
    PlanTemplateStyle? style,
    List<UnidadDidactica>? unidades,
  }) {
    return PlanificacionAnual(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      schoolName: schoolName ?? this.schoolName,
      anioEscolar: anioEscolar ?? this.anioEscolar,
      anio: anio ?? this.anio,
      nivel: nivel ?? this.nivel,
      grado: grado ?? this.grado,
      gradeId: gradeId ?? this.gradeId,
      asignatura: asignatura ?? this.asignatura,
      asignaturaId: asignaturaId ?? this.asignaturaId,
      teacherDocId: teacherDocId ?? this.teacherDocId,
      teacherUid: teacherUid ?? this.teacherUid,
      teacherName: teacherName ?? this.teacherName,
      secciones: secciones ?? this.secciones,
      templateTitle: templateTitle ?? this.templateTitle,
      templateSubtitle: templateSubtitle ?? this.templateSubtitle,
      introductoryNote: introductoryNote ?? this.introductoryNote,
      style: style ?? this.style,
      unidades: unidades ?? this.unidades,
    );
  }
}
