import 'package:flutter/material.dart';

/// Keeps the entered fields mounted until creation has been confirmed.
class SchoolCreationDialog extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final Widget Function(BuildContext context, bool saving) contentBuilder;
  final Future<bool> Function() onCreate;
  final String Function(Object error) errorMessage;

  const SchoolCreationDialog({
    super.key,
    required this.formKey,
    required this.contentBuilder,
    required this.onCreate,
    required this.errorMessage,
  });

  @override
  State<SchoolCreationDialog> createState() => _SchoolCreationDialogState();
}

class _SchoolCreationDialogState extends State<SchoolCreationDialog> {
  bool _saving = false;
  bool _completed = false;
  String? _error;

  Future<void> _create() async {
    if (_saving ||
        _completed ||
        !(widget.formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await widget.onCreate();
      if (!mounted) return;
      if (created) {
        setState(() {
          _saving = false;
          _completed = true;
        });
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error =
              'No se completó la confirmación. Tus datos siguen aquí; puedes volver a intentarlo.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_business_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Nuevo colegio')),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ExcludeFocus(
                excluding: _saving || _completed,
                child: AbsorbPointer(
                  absorbing: _saving || _completed,
                  child: widget.contentBuilder(context, _saving || _completed),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('school-create-cancel'),
          onPressed:
              _saving || _completed
                  ? null
                  : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('school-create-submit'),
          onPressed: _saving || _completed ? null : _create,
          child:
              _saving
                  ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Guardando…'),
                    ],
                  )
                  : Text(_error == null ? 'Crear' : 'Reintentar'),
        ),
      ],
    ),
  );
}
