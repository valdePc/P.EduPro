import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edupro/models/escuela.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class EstudiantesScreen extends StatefulWidget {
  final Escuela escuela;
  const EstudiantesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<EstudiantesScreen> createState() => _EstudiantesScreenState();
}

class _EstudiantesScreenState extends State<EstudiantesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  // ------- Estado DOB/Edad -------
  DateTime? _fechaNacimiento;
  String _anioInfo = '';

  final fechaNacCtrl = TextEditingController();
  final edadCtrl = TextEditingController();

  // ------- Helpers -------
  String _capitalizeEach(String input) {
    return input
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  int _calcAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthdayThisYear =
        (now.month > dob.month) || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age--;
    return age < 0 ? 0 : age;
  }

  /// Si SOLO tienes edad (sin fecha exacta), el año puede ser un rango
  /// porque no sabemos si ya cumplió años este año.
  String _anioRangoFromEdad(int edad) {
    final now = DateTime.now();
    final maxYear = now.year - edad;     // si ya cumplió
    final minYear = now.year - edad - 1; // si todavía no cumple
    return '$minYear–$maxYear';
  }

  Future<void> _pickFechaNacimiento() async {
    final now = DateTime.now();
    final initial = _fechaNacimiento ?? DateTime(now.year - 10, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
    );

    if (picked == null) return;

    final edad = _calcAge(picked);

    setState(() {
      _fechaNacimiento = picked;
      fechaNacCtrl.text = _fmtDate(picked);
      edadCtrl.text = edad.toString();
      _anioInfo = 'Año de nacimiento: ${picked.year}';
    });
  }

  void _onEdadManualChanged(String v) {
    final txt = v.trim();
    if (txt.isEmpty) {
      setState(() => _anioInfo = '');
      return;
    }

    final edad = int.tryParse(txt);
    if (edad == null || edad < 0 || edad > 120) {
      setState(() => _anioInfo = 'Edad no válida');
      return;
    }

    // Si el usuario escribe edad manualmente, no sabemos fecha exacta.
    // Dejamos fechaNacimiento vacía (opcional), pero mostramos el rango.
    setState(() {
      _fechaNacimiento = null;
      fechaNacCtrl.clear();
      _anioInfo = 'Año de nacimiento aprox: ${_anioRangoFromEdad(edad)}';
    });
  }

  // ------- Datos existentes -------
  final List<String> grados = [
    '1ro', '2do', '3ro', '4to', '5to', '6to',
    '1ro de secundaria', '2do de secundaria', '3ro de secundaria',
    '4to de secundaria', '5to de secundaria', '6to de secundaria',
  ];

  String gradoAgregar = '1ro';
  String gradoBuscar = '1ro';
  String filtroNombre = '';
  String sortField = 'Nombre'; // 'Nombre', 'Apellido' o 'Número'
  bool sortAsc = true;
  int? hoveredRow;

  final nombreCtrl = TextEditingController();
  final apellidoCtrl = TextEditingController();
  final numeroCtrl = TextEditingController();
  final filtroCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  @override
  void dispose() {
    nombreCtrl.dispose();
    apellidoCtrl.dispose();
    numeroCtrl.dispose();
    filtroCtrl.dispose();
    fechaNacCtrl.dispose();
    edadCtrl.dispose();
    super.dispose();
  }

  Future<void> agregarEstudiante() async {
    final nom = _capitalizeEach(nombreCtrl.text);
    final ape = _capitalizeEach(apellidoCtrl.text);
    final num = numeroCtrl.text.trim();

    // Edad (opcional si hay fecha)
    final edadManual = int.tryParse(edadCtrl.text.trim());

    if (nom.isEmpty || ape.isEmpty || num.isEmpty) return;

    // Debe existir fecha o edad (para poder filtrar luego)
    if (_fechaNacimiento == null && (edadManual == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona fecha de nacimiento o escribe la edad')),
        );
      }
      return;
    }

    try {
      // evitar duplicados por (grado + numero)
      final dup = await _db
          .collection('escuelas')
          .doc(_schoolId)
          .collection('estudiantes')
          .where('grado', isEqualTo: gradoAgregar)
          .where('numero', isEqualTo: num)
          .limit(1)
          .get();

      if (dup.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ya existe un estudiante con ese número en ese grado')),
          );
        }
        return;
      }

      final data = <String, dynamic>{
        'nombre': nom,
        'apellido': ape,
        'numero': num,
        'grado': gradoAgregar,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (_fechaNacimiento != null) {
        final edad = _calcAge(_fechaNacimiento!);
        data['fechaNacimiento'] = Timestamp.fromDate(_fechaNacimiento!);
        data['edad'] = edad;
        data['anioNacimiento'] = _fechaNacimiento!.year;
      } else if (edadManual != null) {
        // Sin fecha exacta, guardamos edad + rango de año
        final now = DateTime.now();
        data['edad'] = edadManual;
        data['anioNacimientoAproxMin'] = now.year - edadManual - 1;
        data['anioNacimientoAproxMax'] = now.year - edadManual;
      }

      await _db
          .collection('escuelas')
          .doc(_schoolId)
          .collection('estudiantes')
          .add(data);

      // Limpia inputs
      nombreCtrl.clear();
      apellidoCtrl.clear();
      numeroCtrl.clear();
      fechaNacCtrl.clear();
      edadCtrl.clear();

      setState(() {
        _fechaNacimiento = null;
        _anioInfo = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estudiante guardado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.escuela.alumLink;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edupro'),
        backgroundColor: const Color.fromARGB(255, 21, 101, 192),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // LINK + COPY + OPEN
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Link de acceso:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copiar enlace',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enlace copiado')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: 'Abrir enlace',
                    onPressed: () async {
                      final uri = Uri.parse(link);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No se pudo abrir el enlace')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          SelectableText(link, style: const TextStyle(color: Colors.blue)),
          const Divider(height: 30),

          // AGREGAR ESTUDIANTE
          const Text('Agregar estudiante', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: nombreCtrl,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑáéíóúÁÉÍÓÚ ]"))
                ],
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: apellidoCtrl,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑáéíóúÁÉÍÓÚ ]"))
                ],
                decoration: InputDecoration(
                  labelText: 'Apellido',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: numeroCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Número',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: gradoAgregar,
                decoration: InputDecoration(
                  labelText: 'Grado',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: grados.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (g) => setState(() => gradoAgregar = g!),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // FECHA NACIMIENTO + EDAD
          Row(children: [
            Expanded(
              child: TextField(
                controller: fechaNacCtrl,
                readOnly: true,
                onTap: _pickFechaNacimiento,
                decoration: InputDecoration(
                  labelText: 'Fecha de nacimiento',
                  hintText: 'dd/mm/aaaa',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: _pickFechaNacimiento,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: edadCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  labelText: 'Edad',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: _onEdadManualChanged,
              ),
            ),
          ]),

          if (_anioInfo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_anioInfo, style: TextStyle(color: Colors.grey.shade700)),
          ],

          const SizedBox(height: 12),

          Center(
            child: ElevatedButton(
              onPressed: () => agregarEstudiante(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 255, 193, 7),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Agregar estudiante', style: TextStyle(fontSize: 16)),
            ),
          ),

          const Divider(height: 40),

          // BUSCAR + ORDENAR
          const Text('Buscar y ordenar', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: gradoBuscar,
                decoration: InputDecoration(
                  labelText: 'Grado',
                  filled: true,
                  fillColor: Colors.blue.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: grados.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (g) => setState(() => gradoBuscar = g!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: filtroCtrl,
                decoration: InputDecoration(
                  labelText: 'Buscar por nombre',
                  filled: true,
                  fillColor: Colors.blue.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => filtroNombre = v),
              ),
            ),
          ]),

          const SizedBox(height: 12),

          Row(children: [
            const Text('Ordenar por:'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: sortField,
              items: ['Nombre', 'Apellido', 'Número']
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setState(() => sortField = v!),
            ),
            IconButton(
              icon: Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward),
              onPressed: () => setState(() => sortAsc = !sortAsc),
            ),
          ]),

          const SizedBox(height: 20),

          // TABLA DESDE FIRESTORE
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('escuelas')
                .doc(_schoolId)
                .collection('estudiantes')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Text('Error: ${snap.error}');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final raw = snap.data!.docs.map((d) {
                final data = d.data();

                // edad: si hay fechaNacimiento calculamos, si no usamos campo edad
                int? edad;
                final fn = data['fechaNacimiento'];
                if (fn is Timestamp) {
                  final dob = fn.toDate();
                  edad = _calcAge(dob);
                } else if (data['edad'] is int) {
                  edad = data['edad'] as int;
                }

                return {
                  'nombre': (data['nombre'] ?? '').toString(),
                  'apellido': (data['apellido'] ?? '').toString(),
                  'numero': (data['numero'] ?? '').toString(),
                  'grado': (data['grado'] ?? '').toString(),
                  'edad': edad?.toString() ?? '—',
                };
              }).toList();

              // filtrar (grado + nombre)
              final q = filtroNombre.toLowerCase();
              final lista = raw.where((e) {
                final matchGrado = (e['grado'] ?? '') == gradoBuscar;
                final matchName = (e['nombre'] ?? '').toLowerCase().contains(q);
                return matchGrado && matchName;
              }).toList();

              // ordenar
              lista.sort((a, b) {
                int cmp;
                if (sortField == 'Nombre') {
                  cmp = (a['nombre'] ?? '').compareTo(b['nombre'] ?? '');
                } else if (sortField == 'Apellido') {
                  cmp = (a['apellido'] ?? '').compareTo(b['apellido'] ?? '');
                } else {
                  final na = int.tryParse(a['numero'] ?? '') ?? 0;
                  final nb = int.tryParse(b['numero'] ?? '') ?? 0;
                  cmp = na.compareTo(nb);
                }
                return sortAsc ? cmp : -cmp;
              });

              if (lista.isEmpty) {
                return const Center(child: Text('No hay estudiantes para mostrar'));
              }

              return Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: FlexColumnWidth(),
                  2: FixedColumnWidth(90),
                  3: FixedColumnWidth(70),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFEAEDED)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Apellido', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Número', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Edad', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  for (var i = 0; i < lista.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: hoveredRow == i
                            ? Colors.orange.shade100
                            : (i.isEven ? Colors.blue.shade50 : Colors.orange.shade50),
                      ),
                      children: [
                        for (var j = 0; j < 4; j++)
                          MouseRegion(
                            onEnter: (_) => setState(() => hoveredRow = i),
                            onExit: (_) => setState(() => hoveredRow = null),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text([
                                lista[i]['nombre'] ?? '',
                                lista[i]['apellido'] ?? '',
                                lista[i]['numero'] ?? '',
                                lista[i]['edad'] ?? '—',
                              ][j]),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ]),
      ),
    );
  }
}
