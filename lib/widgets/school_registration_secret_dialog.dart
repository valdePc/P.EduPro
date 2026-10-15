import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A transient receipt, available only to the session that created the school.
class SchoolRegistrationSecretDialog extends StatefulWidget {
  final String schoolName;
  final String secret;
  final bool Function() canAccess;
  final Stream<bool> accessChanges;

  const SchoolRegistrationSecretDialog({
    super.key,
    required this.schoolName,
    required this.secret,
    required this.canAccess,
    required this.accessChanges,
  });

  @override
  State<SchoolRegistrationSecretDialog> createState() =>
      _SchoolRegistrationSecretDialogState();
}

class _SchoolRegistrationSecretDialogState
    extends State<SchoolRegistrationSecretDialog>
    with WidgetsBindingObserver {
  StreamSubscription<bool>? _subscription;
  bool _visible = false;
  bool _copying = false;
  bool _closed = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.accessChanges.listen((allowed) {
      if (!allowed) _close();
    }, onError: (Object _) => _close());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.canAccess()) _close();
    });
  }

  void _close() {
    if (!mounted || _closed) return;
    setState(() {
      _closed = true;
      _visible = false;
    });
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _visible = false);
    }
  }

  Future<void> _copy() async {
    if (_copying || _closed) return;
    if (!widget.canAccess()) {
      _close();
      return;
    }
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.secret));
      if (mounted && !_closed) {
        setState(() => _status = 'Clave copiada.');
      }
    } catch (_) {
      if (mounted && !_closed) {
        setState(
          () => _status = 'No se pudo copiar la clave. Intenta nuevamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Colegio creado'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.schoolName),
            const SizedBox(height: 16),
            const Text(
              'Esta clave de registro se muestra solo en esta ocasión. '
              'Guárdala en un lugar seguro antes de cerrar.',
            ),
            const SizedBox(height: 16),
            Semantics(
              label:
                  _visible && !_closed ? 'Clave de registro' : 'Clave oculta',
              child: Text(
                _visible && !_closed ? widget.secret : '••••••••••••',
                key: const ValueKey('school-secret-value'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('school-secret-reveal'),
              onPressed:
                  _closed
                      ? null
                      : () {
                        if (!widget.canAccess()) {
                          _close();
                          return;
                        }
                        setState(() => _visible = !_visible);
                      },
              icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
              label: Text(_visible ? 'Ocultar clave' : 'Mostrar clave'),
            ),
            const Text('Copia la clave únicamente en un equipo de confianza.'),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_status!)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _close, child: const Text('Cerrar')),
      FilledButton.icon(
        key: const ValueKey('school-secret-copy'),
        onPressed: _copying || _closed ? null : _copy,
        icon: const Icon(Icons.copy),
        label: const Text('Copiar clave'),
      ),
    ],
  );
}
