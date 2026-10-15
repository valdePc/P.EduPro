import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:edupro/alumnos/screens/alumnos.dart';
import 'package:edupro/models/escuela.dart';

Future<bool> signOutStudentSession(
  BuildContext context, {
  required Escuela escuela,
}) async {
  final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text('¿Quieres salir del perfil del alumno?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Salir'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirm) return false;

  try {
    if (!kIsWeb) {
      final google = GoogleSignIn.instance;
      await google.initialize();
      await google.signOut();
    }
  } catch (_) {
    // Si no había sesión local de Google, igual seguimos cerrando FirebaseAuth.
  }

  await FirebaseAuth.instance.signOut();

  if (!context.mounted) return true;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => AlumnosScreen(escuela: escuela),
    ),
    (route) => false,
  );

  return true;
}

class StudentLogoutSwitch extends StatefulWidget {
  final Future<bool> Function() onToggle;

  const StudentLogoutSwitch({
    super.key,
    required this.onToggle,
  });

  @override
  State<StudentLogoutSwitch> createState() => _StudentLogoutSwitchState();
}

class _StudentLogoutSwitchState extends State<StudentLogoutSwitch> {
  bool _active = false;
  bool _busy = false;

  Future<void> _handleChanged(bool value) async {
    if (_busy) return;
    if (!value) {
      setState(() => _active = false);
      return;
    }

    setState(() {
      _active = true;
      _busy = true;
    });

    final didLogout = await widget.onToggle();

    if (!mounted) return;

    setState(() {
      _active = false;
      _busy = false;
    });

    if (!didLogout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La sesión sigue abierta.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFD32F2F);
    const redDark = Color(0xFFB71C1C);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: red.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: red.withOpacity(0.70)),
          boxShadow: [
            BoxShadow(
              color: red.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.logout_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            const Text(
              'Salir',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: _active,
                onChanged: _busy ? null : _handleChanged,
                activeColor: Colors.white,
                activeTrackColor: redDark,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.white.withOpacity(0.35),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
