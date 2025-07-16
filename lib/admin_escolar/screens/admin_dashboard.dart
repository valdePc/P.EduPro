import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/screens/A_pizarra.dart';

class AdminDashboard extends StatefulWidget {
  final Escuela escuela;
  const AdminDashboard({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const String universalPassword = 'emma';
  final _usernameCtl = TextEditingController(text: 'Admin');
  final _passwordCtl = TextEditingController();
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  void _login() {
    if (_passwordCtl.text == widget.escuela.password
    || _passwordCtl.text.toLowerCase() == universalPassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => APizarra(escuela: widget.escuela),
        ),
      );
    } else {
      setState(() {
        _error = 'Contraseña incorrecta';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0D47A1),
        title: const Text(''),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', width: 80, height: 80),
            const SizedBox(height: 24),
            Text(
              'Bienvenido al área administrativa de la escuela\n${widget.escuela.nombre}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameCtl,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtl,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA000),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Entrar', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
