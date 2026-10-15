import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../utils/equipo_edupro_access.dart';

/// Keeps pending, failed and explicitly denied checks distinct. Each result is
/// bound to the session and attempt that requested it, including after timeout.
class TeamAccessGate extends StatefulWidget {
  const TeamAccessGate({
    super.key,
    required this.loadRole,
    required this.currentSessionId,
    required this.sessionChanges,
    required this.onCheckStarted,
    required this.onExit,
    required this.allowedBuilder,
    this.deniedBuilder,
    this.timeout = const Duration(seconds: 30),
  });

  final Future<String> Function() loadRole;
  final String? Function() currentSessionId;
  final Stream<String?> sessionChanges;
  final VoidCallback onCheckStarted;
  final VoidCallback onExit;
  final Widget Function(BuildContext, String) allowedBuilder;
  final WidgetBuilder? deniedBuilder;
  final Duration timeout;

  @override
  State<TeamAccessGate> createState() => _TeamAccessGateState();
}

class _TeamAccessGateState extends State<TeamAccessGate> {
  StreamSubscription<String?>? _sessionSubscription;
  String? _sessionId;
  String? _role;
  Object? _error;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _check();
    _sessionSubscription = widget.sessionChanges.listen(
      (sessionId) {
        if (sessionId != _sessionId) _check();
      },
      onError: (Object error) {
        if (!mounted) return;
        ++_attempt;
        widget.onCheckStarted();
        setState(() {
          _role = null;
          _error = error;
        });
      },
    );
  }

  Future<void> _check() async {
    final attempt = ++_attempt;
    final sessionId = widget.currentSessionId();
    _sessionId = sessionId;
    widget.onCheckStarted();
    setState(() {
      _role = null;
      _error = null;
    });
    if (sessionId == null) {
      setState(() => _role = EquipoEduProRoles.denied);
      return;
    }
    try {
      final role = await widget.loadRole().timeout(widget.timeout);
      if (!mounted || attempt != _attempt) return;
      if (widget.currentSessionId() != sessionId) {
        _check();
        return;
      }
      if (role != EquipoEduProRoles.denied &&
          !EquipoEduProRoles.all.contains(role)) {
        throw const FormatException('Rol no reconocido.');
      }
      setState(() => _role = role);
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      if (widget.currentSessionId() != sessionId) {
        _check();
        return;
      }
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    ++_attempt;
    _sessionSubscription?.cancel();
    super.dispose();
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException ||
        error is FirebaseFunctionsException &&
            const [
              'unavailable',
              'deadline-exceeded',
              'network-request-failed',
            ].contains(error.code)) {
      return 'La comprobación no pudo completarse a tiempo. Revisa tu conexión y vuelve a intentarlo.';
    }
    if (error is FirebaseFunctionsException &&
        error.code == 'unauthenticated') {
      return 'No se pudo validar tu sesión. Intenta nuevamente o sal e inicia sesión otra vez.';
    }
    return 'No se pudieron comprobar los permisos de tu cuenta. Intenta nuevamente. Si el problema continúa, contacta con soporte.';
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    // Do not render an old account's content while its session event is pending.
    if (_sessionId != widget.currentSessionId() ||
        role == null && _error == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Comprobando acceso',
          ),
        ),
      );
    }
    if (_error == null && EquipoEduProRoles.all.contains(role)) {
      return TeamAccessRoleScope(
        role: role!,
        child: widget.allowedBuilder(context, role),
      );
    }
    final failed = _error != null;
    final noSession = _sessionId == null;
    if (!failed && !noSession && widget.deniedBuilder != null) {
      return widget.deniedBuilder!(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('EduPro')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(failed ? Icons.cloud_off : Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    failed
                        ? 'No se pudo comprobar el acceso'
                        : noSession
                        ? 'Sesión finalizada'
                        : 'Acceso restringido',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  failed
                      ? _errorMessage(_error!)
                      : noSession
                      ? 'Inicia sesión con tu cuenta del equipo para usar este panel.'
                      : 'Este panel solo permite usuarios autorizados del equipo EduPro.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (failed)
                  FilledButton(
                    onPressed: _check,
                    child: const Text('Reintentar'),
                  ),
                TextButton(
                  onPressed: widget.onExit,
                  child: const Text('Salir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TeamAccessRoleScope extends InheritedWidget {
  const TeamAccessRoleScope({
    super.key,
    required this.role,
    required super.child,
  });
  final String role;
  static String of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TeamAccessRoleScope>();
    if (scope == null) {
      throw StateError('No se ha comprobado el rol del equipo.');
    }
    return scope.role;
  }

  @override
  bool updateShouldNotify(TeamAccessRoleScope oldWidget) =>
      oldWidget.role != role;
}
