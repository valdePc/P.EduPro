import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:edupro/utils/school_access_link.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/alumnos/screens/alumnos.dart';
import 'package:edupro/docentes/screens/docentes.dart';
import 'package:edupro/admin_escolar/screens/admin_dashboard.dart' as admin;
import 'package:edupro/screens/login_general.dart';
import 'package:edupro/utils/school_utils.dart'
    show escuelaFromPublicMeta, lookupSchoolPublicMeta;

class AccesoEnlaceScreen extends StatefulWidget {
  const AccesoEnlaceScreen({super.key});

  @override
  State<AccesoEnlaceScreen> createState() => _AccesoEnlaceScreenState();
}

class _AccesoEnlaceScreenState extends State<AccesoEnlaceScreen> {
  static const Color _blue = Color(0xFF0D47A1);
  static const Color _blueDark = Color(0xFF0A2D67);
  static const Color _orange = Color(0xFFFFA000);

  final TextEditingController _linkCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  int _secretTapCount = 0;

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<Escuela?> _fetchEscuela(String sidRaw) async {
    final sid = sidRaw.trim();
    if (sid.isEmpty) return null;

    Escuela placeholder(String id) => Escuela(
          id: id,
          nombre: 'EduPro',
          adminLink: '',
          profLink: '',
          alumLink: '',
          fecha: DateTime.now(),
          grados: const <String>[],
          activo: true,
        );

    try {
      final lookup = await lookupSchoolPublicMeta(FirebaseFirestore.instance, sid);
      if (lookup != null) {
        return escuelaFromPublicMeta(
          schoolId: lookup.schoolId,
          data: lookup.data,
        );
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return placeholder(sid);
      }
    } catch (_) {}

    for (final c in <String>{
      sid,
      sid.toUpperCase(),
      sid.toLowerCase(),
      sid.replaceAll('/', '_'),
    }) {
      try {
        final snap =
            await FirebaseFirestore.instance.collection('schools').doc(c).get();
        if (!snap.exists) continue;
        final d = snap.data() ?? <String, dynamic>{};
        return escuelaFromPublicMeta(
          schoolId: snap.id,
          data: d,
        );
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          return placeholder(sid);
        }
      } catch (_) {}
    }
    return placeholder(sid);
  }

  Future<void> _continue() async {
    final parsed = SchoolAccessLink.parse(_linkCtrl.text);
    if (parsed == null) {
      setState(() {
        _error = 'Enlace inválido. Usa uno generado por EduPro.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final escuela = await _fetchEscuela(parsed.schoolId);
      if (!mounted) return;
      if (escuela == null) {
        setState(() => _error = 'No se pudo resolver la escuela del enlace.');
        return;
      }

      switch (parsed.module) {
        case 'admin':
        case 'admincole':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => admin.AdminDashboard(escuela: escuela),
            ),
          );
          return;
        case 'doc':
        case 'docentes':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DocentesScreen(escuela: escuela),
            ),
          );
          return;
        case 'alum':
        case 'alumnos':
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AlumnosScreen(escuela: escuela),
            ),
          );
          return;
        default:
          setState(() => _error = 'Módulo inválido en el enlace.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAdminGeneralLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginGeneralScreen(),
      ),
    );
  }

  void _handleSecretTap() {
    _secretTapCount++;
    if (_secretTapCount < 5) return;
    _secretTapCount = 0;
    _openAdminGeneralLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_blue, _blueDark, Color(0xFF061736)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.28)),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                        color: Colors.black.withOpacity(0.22),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.14)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.contain,
                                semanticLabel: 'Logotipo de EduPro',
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.school_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Bienvenido a EduPro',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pega el enlace de acceso para inicar sesion.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _linkCtrl,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) { if (!_loading) _continue(); },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Enlace de acceso',
                          labelStyle: const TextStyle(color: Colors.white),
                          hintText:
                              'https://edupro-8c4fd.web.app/#/eduproapp/...',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.55)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: Colors.white.withOpacity(0.30)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: Colors.white.withOpacity(0.30)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _orange, width: 2),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFFCDD2),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _continue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Continuar'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleSecretTap,
                        onLongPress: _openAdminGeneralLogin,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: const [
                            Text(
                              'Creado por EduPro',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 16,
                              color: Colors.lightBlueAccent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
          ),
        ),
      ),
    );
  }
}
