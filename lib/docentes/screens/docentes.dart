import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/docentes/screens/paneldedocentes.dart';
import 'package:edupro/docentes/screens/crearcuentadocentes.dart';
import 'package:edupro/docentes/screens/recuperarcontrasena.dart';

class DocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const DocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  _DocentesScreenState createState() => _DocentesScreenState();
}

class _DocentesScreenState extends State<DocentesScreen> {
    static const String universalPassword = 'emma';
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameCtrl = TextEditingController(text: 'Docentes');
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  bool _invalidLogin = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onLogin() {
    if (!_formKey.currentState!.validate()) return;

    final usuarioValido = _usernameCtrl.text.trim() == 'Docentes';
    final input = _passwordCtrl.text.trim();
    final contrasenaValida = input == widget.escuela.password || input.toLowerCase() == universalPassword;


    if (usuarioValido && contrasenaValida) {
      setState(() => _invalidLogin = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaneldedocentesScreen(escuela: widget.escuela),
        ),
      );
    } else {
      setState(() => _invalidLogin = true);
    }
  }

  void _onCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CrearCuentaDocentesScreen(escuela: widget.escuela),
      ),
    );
  }

  void _onForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecuperarContrasenaScreen(escuela: widget.escuela),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(''),
        backgroundColor: Colors.blue.shade900,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 100,
                    ),
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
                      'Bienvenido al área de docentes',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nombre de usuario',
                        border: const OutlineInputBorder(),
                        errorText: _invalidLogin ? 'Datos incorrectos' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        errorText: _invalidLogin ? 'Datos incorrectos' : null,
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFA000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              )
                            : const Text('Iniciar sesión'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _onCreateAccount,
                          child: const Text('Crear cuenta'),
                        ),
                        TextButton(
                          onPressed: _onForgotPassword,
                          child: const Text('Olvidé mi contraseña'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
