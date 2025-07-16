import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AlumnosScreen extends StatefulWidget {
  final Escuela escuela;
  const AlumnosScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AlumnosScreen> createState() => _AlumnosScreenState();
}

class _AlumnosScreenState extends State<AlumnosScreen> {
  final _nombreCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();
  bool _showPassword = false;
  bool _error = false;
  String? _gradoSeleccionado;

  final List<String> _gradosRD = [
    'Inicial 1', 'Inicial 2',
    '1ro Primaria', '2do Primaria', '3ro Primaria', '4to Primaria',
    '5to Primaria', '6to Primaria',
    '1ro Secundaria', '2do Secundaria', '3ro Secundaria',
    '4to Secundaria', '5to Secundaria', '6to Secundaria'
  ];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _contrasenaCtrl.dispose();
    super.dispose();
  }

  void _validarDatos() {
    if (_contrasenaCtrl.text.trim() == widget.escuela.password) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text('Alumnos - ${widget.escuela.nombre}'),
              backgroundColor: Colors.blue.shade900,
            ),
            body: const Center(child: Text('Bienvenido al área de estudiantes')),
          ),
        ),
      );
    } else {
      setState(() => _error = true);
    }
  }

  void _crearCuenta() {
    // Aquí navegarías a la pantalla de registro si existe
  }

  void _olvidoContrasena() {
    // Aquí navegarías a la recuperación si existe
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.blue.shade900,
        title: const Text(''),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Column(
                children: [
                  Image.asset('assets/logo.png', height: 90),
                  const SizedBox(height: 16),
                  Text(
                    widget.escuela.nombre,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bienvenido al área de estudiantes',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Selecciona tu grado',
                border: OutlineInputBorder(),
              ),
              value: _gradoSeleccionado,
              items: _gradosRD.map((grado) => DropdownMenuItem(
                value: grado,
                child: Text(grado),
              )).toList(),
              onChanged: (value) => setState(() => _gradoSeleccionado = value),
              validator: (value) => value == null ? 'Selecciona tu grado' : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contrasenaCtrl,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                border: const OutlineInputBorder(),
                errorText: _error ? 'Contraseña incorrecta' : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _validarDatos(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _validarDatos,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Entrar', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _crearCuenta,
                  child: const Text('Crear cuenta'),
                ),
                TextButton(
                  onPressed: _olvidoContrasena,
                  child: const Text('Olvidé mi contraseña'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}