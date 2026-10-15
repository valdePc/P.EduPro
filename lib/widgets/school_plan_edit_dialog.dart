import 'package:flutter/material.dart';

import 'school_plan_fields.dart';

class SchoolPlanEditDialog extends StatefulWidget {
  final String schoolName;
  final SchoolPlanValues initialValues;
  final Future<bool> Function(SchoolPlanValues values, String reason) onSave;
  final String Function(Object error) errorMessage;

  const SchoolPlanEditDialog({
    super.key,
    required this.schoolName,
    required this.initialValues,
    required this.onSave,
    required this.errorMessage,
  });

  @override
  State<SchoolPlanEditDialog> createState() => _SchoolPlanEditDialogState();
}

class _SchoolPlanEditDialogState extends State<SchoolPlanEditDialog> {
  final _form = GlobalKey<FormState>();
  final _plan = SchoolPlanController();
  final _reason = TextEditingController();
  bool _saving = false;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValues;
    _plan.selectPlan(initial.planTier);
    _plan.admins.text = '${initial.adminsLimit}';
    _plan.teachers.text = '${initial.teachersLimit}';
    _plan.students.text = '${initial.studentsLimit}';
  }

  Future<void> _save() async {
    if (_saving || _completed || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final values = _plan.readValues();
    final reason = _reason.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(values, reason);
      if (!mounted) return;
      if (saved) {
        setState(() {
          _saving = false;
          _completed = true;
        });
        Navigator.of(context).pop(true);
      } else {
        setState(
          () =>
              _error =
                  'No se completó la confirmación. Tus cambios siguen aquí.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _plan.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Editar plan y límites'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.schoolName),
              const SizedBox(height: 12),
              ExcludeFocus(
                excluding: _saving || _completed,
                child: AbsorbPointer(
                  absorbing: _saving || _completed,
                  child: Form(
                    key: _form,
                    child: Column(
                      children: [
                        SchoolPlanSelector(
                          controller: _plan,
                          editable: !_saving,
                        ),
                        const SizedBox(height: 12),
                        SchoolPlanLimitFields(
                          controller: _plan,
                          editable: !_saving,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('school-plan-reason'),
                          controller: _reason,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: 'Justificación del cambio',
                            helperText:
                                'Se guardará en la auditoría. No incluyas datos personales.',
                            helperMaxLines: 3,
                            border: OutlineInputBorder(),
                          ),
                          validator: (text) {
                            final length = (text ?? '').trim().length;
                            if (length < 10 || length > 500) {
                              return 'Escribe una justificación de 10 a 500 caracteres';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _saving || _completed
                  ? null
                  : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('school-plan-save'),
          onPressed: _saving || _completed ? null : _save,
          child:
              _saving
                  ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Guardando…'),
                    ],
                  )
                  : Text(_error == null ? 'Guardar' : 'Reintentar'),
        ),
      ],
    ),
  );
}
