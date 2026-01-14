import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/models/estudiante.dart';


class ColocarCalificacionesScreen extends StatefulWidget {
  final Escuela escuela;
  const ColocarCalificacionesScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);

  @override
  _ColocarCalificacionesScreenState createState() => _ColocarCalificacionesScreenState();
}

class _ColocarCalificacionesScreenState extends State<ColocarCalificacionesScreen> {
  String? selectedGrado;
  Estudiante? selectedEstudiante;
  late List<String> grados;
  late List<Estudiante> estudiantes;
  final Map<String, bool> checked = {};

  @override
  void initState() {
    super.initState();
    List<String> grados = widget.escuela.grados ?? [];
                // Lista de grados desde el modelo Escuela
    estudiantes = Estudiante.getAll();               // Carga todos los estudiantes
  }

  List<Estudiante> get estudiantesFiltrados {
    if (selectedGrado == null) return [];
    return estudiantes.where((Estudiante e) => e.grado == selectedGrado).toList();

  }

  @override
  Widget build(BuildContext context) {
    final total = estudiantesFiltrados.length;
    final countChecked = checked.values.where((v) => v).length;
    final isChecked = selectedEstudiante != null && (checked[selectedEstudiante!.id] ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Colocar Calificaciones'),
        backgroundColor: ColocarCalificacionesScreen.primaryColor,
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FILA SUPERIOR: Grado, Estudiante y Checkbox
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Seleccione grado'),
                    value: selectedGrado,
                    items: grados.map((g) => DropdownMenuItem(
                      value: g,
                      child: Text(g),
                    )).toList(),
                    onChanged: (g) {
                      setState(() {
                        selectedGrado = g;
                        selectedEstudiante = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<Estudiante>(
                    isExpanded: true,
                    hint: const Text('Seleccione estudiante'),
                    value: selectedEstudiante,
items: estudiantesFiltrados.map<DropdownMenuItem<Estudiante>>((Estudiante e) {
  return DropdownMenuItem<Estudiante>(
    value: e,
    child: Text('${e.nombre} ${e.apellido}'),
  );
}).toList(),

                    onChanged: (e) {
                      setState(() {
                        selectedEstudiante = e;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isChecked,
                  onChanged: (v) {
                    if (selectedEstudiante != null) {
                      setState(() {
                        checked[selectedEstudiante!.id] = v!;
                      });
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),
            // CONTADOR
            Text(
              '$countChecked/$total',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),
            // ESPACIO PARA CAMPOS DE CALIFICACIONES
            Expanded(
              child: Center(
                child: Text(
                  'Aquí van los campos para ingresar calificaciones',
                  style: Theme.of(context).textTheme.titleMedium,

                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
