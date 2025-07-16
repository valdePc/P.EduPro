import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edupro/models/escuela.dart';
import 'package:url_launcher/url_launcher.dart';




class EstudiantesScreen extends StatefulWidget {
  final Escuela escuela;
  const EstudiantesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
   State<EstudiantesScreen> createState() => _EstudiantesScreenState();
}

class _EstudiantesScreenState extends State<EstudiantesScreen> {
  // Helper para normalizar cada palabra
  String _capitalizeEach(String input) {
    return input
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) =>
            word.isEmpty
                ? ''
                : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  final List<String> grados = [
    '1ro','2do','3ro','4to','5to','6to',
    '1ro de secundaria','2do de secundaria','3ro de secundaria',
    '4to de secundaria','5to de secundaria','6to de secundaria',
  ];

  String gradoAgregar = '1ro';
  String gradoBuscar  = '1ro';
  String filtroNombre = '';
  String sortField    = 'Nombre'; // 'Nombre', 'Apellido' o 'Número'
  bool sortAsc        = true;
  int? hoveredRow;

  List<Map<String, String>> estudiantes = [];

  final nombreCtrl   = TextEditingController();
  final apellidoCtrl = TextEditingController();
  final numeroCtrl   = TextEditingController();
  final filtroCtrl   = TextEditingController();

  void agregarEstudiante() {
    final nom = _capitalizeEach(nombreCtrl.text);
    final ape = _capitalizeEach(apellidoCtrl.text);
    final num = numeroCtrl.text.trim();
    if (nom.isEmpty || ape.isEmpty || num.isEmpty) return;

    // evitar duplicados dentro del mismo grado
    final exists = estudiantes.any((e) =>
        e['nombre']  == nom &&
        e['apellido']== ape &&
        e['numero']  == num &&
        e['grado']   == gradoAgregar);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Estudiante duplicado!')),
      );
      return;
    }

    setState(() {
      estudiantes.add({
        'nombre': nom,
        'apellido': ape,
        'numero': num,
        'grado': gradoAgregar,
      });
      nombreCtrl.clear();
      apellidoCtrl.clear();
      numeroCtrl.clear();
    });
  }

  List<Map<String, String>> get estudiantesFiltrados {
    return estudiantes.where((e) {
      final matchGrado = e['grado'] == gradoBuscar;
      final matchName  = e['nombre']!
          .toLowerCase()
          .contains(filtroNombre.toLowerCase());
      return matchGrado && matchName;
    }).toList();
  }

  List<Map<String, String>> get estudiantesOrdenados {
    final list = [...estudiantesFiltrados];
    list.sort((a, b) {
      int cmp;
      if (sortField == 'Nombre') {
        cmp = a['nombre']!.compareTo(b['nombre']!);
      } else if (sortField == 'Apellido') {
        cmp = a['apellido']!.compareTo(b['apellido']!);
      } else {
        final na = int.tryParse(a['numero']!) ?? 0;
        final nb = int.tryParse(b['numero']!) ?? 0;
        cmp = na.compareTo(nb);
      }
      return sortAsc ? cmp : -cmp;
    });
    return list;
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
          Center(
            child: ElevatedButton(
              onPressed: agregarEstudiante,
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
              items: ['Nombre','Apellido','Número']
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

          // TABLA ORDENADA
          Table(
            border: TableBorder.all(color: Colors.grey.shade300),
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FlexColumnWidth(),
              2: FixedColumnWidth(90),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xFFEAEDED)),
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Apellido', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Número', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              for (var i = 0; i < estudiantesOrdenados.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: hoveredRow == i
                        ? Colors.orange.shade100
                        : (i.isEven ? Colors.blue.shade50 : Colors.orange.shade50),
                  ),
                  children: [
                    for (var j = 0; j < 3; j++)
                      MouseRegion(
                        onEnter: (_) => setState(() => hoveredRow = i),
                        onExit:  (_) => setState(() => hoveredRow = null),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text([
                            estudiantesOrdenados[i]['nombre']!,
                            estudiantesOrdenados[i]['apellido']!,
                            estudiantesOrdenados[i]['numero']!
                          ][j]),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
