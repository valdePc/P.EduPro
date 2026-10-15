import 'package:flutter/material.dart';
import 'dart:typed_data';

abstract final class RegistroEquipoColors {
  static const blue = Color(0xFF1A237E);
  static const ink = Color(0xFF17243A);
  static const muted = Color(0xFF536174);
  static const page = Color(0xFFF4F6FB);
  static const border = Color(0xFFE1E7F0);
  static const amberInk = Color(0xFF805000);
}

class RegistroEquipoHero extends StatelessWidget {
  final String schoolName;
  final String level;

  const RegistroEquipoHero({
    super.key,
    required this.schoolName,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 480;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 14 : 18,
            vertical: narrow ? 8 : 16,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [RegistroEquipoColors.blue, Color(0xFF3949AB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              if (!narrow) ...[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.how_to_reg_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nueva inscripción',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$schoolName  •  $level',
                      style: const TextStyle(
                        color: Color(0xFFE9ECFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RegistroEquipoExitAction extends StatelessWidget {
  final bool compact;
  final VoidCallback onPressed;

  const RegistroEquipoExitAction({
    super.key,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: Colors.white.withValues(alpha: 0.55));
    final background = Colors.white.withValues(alpha: 0.12);
    if (compact) {
      return IconButton.outlined(
        tooltip: 'Salir del registro',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: background,
          side: border,
          minimumSize: const Size(44, 44),
        ),
        icon: const Icon(Icons.logout_rounded, size: 21),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: background,
        side: border,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 19),
      label: const Text('Salir', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class RegistroEquipoDesktopLayout extends StatelessWidget {
  final Widget header;
  final Widget form;
  final Widget list;
  final Widget? banner;

  const RegistroEquipoDesktopLayout({
    super.key,
    required this.header,
    required this.form,
    required this.list,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: ListView(
            key: const ValueKey('registro-form-scroll'),
            padding: const EdgeInsets.all(16),
            children: [
              header,
              const SizedBox(height: 16),
              if (banner != null) banner!,
              form,
            ],
          ),
        ),
        Container(width: 1, color: RegistroEquipoColors.border),
        Expanded(
          flex: 5,
          child: ListView(
            key: const ValueKey('registro-list-scroll'),
            padding: const EdgeInsets.all(16),
            children: [list],
          ),
        ),
      ],
    );
  }
}

class RegistroEquipoFieldRow extends StatelessWidget {
  final List<Widget> fields;
  final double minWidthPerField;

  const RegistroEquipoFieldRow({
    super.key,
    required this.fields,
    this.minWidthPerField = 220,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final minWidth = minWidthPerField * (scale > 1.5 ? 1.4 : 1);
        final available =
            (constraints.maxWidth - spacing * (fields.length - 1)) /
            fields.length;
        if (available < minWidth) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i < fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: fields[i]),
            ],
          ],
        );
      },
    );
  }
}

class RegistroEquipoChoiceWrap extends StatelessWidget {
  final List<Widget> choices;

  const RegistroEquipoChoiceWrap({super.key, required this.choices});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            scale > 1.4 || constraints.maxWidth < 450
                ? 1
                : constraints.maxWidth < 680
                ? 2
                : choices.length;
        const spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final choice in choices) SizedBox(width: width, child: choice),
          ],
        );
      },
    );
  }
}

class RegistroEquipoChoiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const RegistroEquipoChoiceTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color:
                selected
                    ? accent.withValues(alpha: 0.65)
                    : RegistroEquipoColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? accent : RegistroEquipoColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? accent : RegistroEquipoColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistroEquipoExitDialog extends StatelessWidget {
  const RegistroEquipoExitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Salir del formulario'),
      content: const Text(
        'Los datos que no hayas guardado se perderán. ¿Deseas salir?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Continuar registrando'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Salir'),
        ),
      ],
    );
  }
}

class RegistroEquipoPhotoField extends StatelessWidget {
  const RegistroEquipoPhotoField({
    super.key,
    required this.canUpload,
    required this.saving,
    required this.photoPicked,
    required this.onPick,
    required this.onRemove,
    this.bytes,
  });

  final bool canUpload, saving, photoPicked;
  final Uint8List? bytes;
  final VoidCallback onPick, onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 34,
        backgroundColor: RegistroEquipoColors.blue.withValues(alpha: 0.08),
        backgroundImage: bytes != null ? MemoryImage(bytes!) : null,
        child:
            bytes == null
                ? const Icon(
                  Icons.person,
                  size: 34,
                  color: RegistroEquipoColors.blue,
                )
                : null,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          canUpload
              ? 'Sube una foto (opcional).'
              : 'La carga de fotos está desactivada para el equipo de registro.',
          style: const TextStyle(
            color: RegistroEquipoColors.muted,
            fontSize: 14,
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Elegir foto',
        onPressed: saving || !canUpload ? null : onPick,
        icon: const Icon(Icons.photo_library_outlined),
        color: RegistroEquipoColors.blue,
      ),
      IconButton(
        tooltip: 'Quitar foto',
        onPressed: saving || !photoPicked ? null : onRemove,
        icon: const Icon(Icons.delete_outline),
        color: RegistroEquipoColors.muted,
      ),
    ],
  );
}

class RegistroEquipoCodeDialog extends StatelessWidget {
  const RegistroEquipoCodeDialog({super.key});

  @override
  Widget build(BuildContext context) => const _RegistroInputDialog(
    title: 'Renovar acceso de registro',
    description:
        'Introduce la clave actual del colegio. Los datos del formulario se conservarán.',
    label: 'Clave de registro',
    action: 'Renovar acceso',
    secure: true,
    maxLength: 128,
  );
}

class RegistroEquipoGradeDialog extends StatelessWidget {
  const RegistroEquipoGradeDialog({super.key, required this.level});
  final String level;

  @override
  Widget build(BuildContext context) => _RegistroInputDialog(
    title: 'Crear grado de $level',
    description:
        'Escribe el nombre o número del grado. Se añadirá al nivel seleccionado.',
    label: 'Nombre del grado',
    action: 'Crear grado',
    maxLength: 120,
  );
}

class _RegistroInputDialog extends StatefulWidget {
  const _RegistroInputDialog({
    required this.title,
    required this.description,
    required this.label,
    required this.action,
    required this.maxLength,
    this.secure = false,
  });
  final String title, description, label, action;
  final int maxLength;
  final bool secure;

  @override
  State<_RegistroInputDialog> createState() => _RegistroInputDialogState();
}

class _RegistroInputDialogState extends State<_RegistroInputDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;
    // Secret values retain their exact value, including spaces.
    Navigator.pop(context, widget.secure ? _text.text : _text.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.description,
                style: const TextStyle(
                  color: RegistroEquipoColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _text,
                autofocus: true,
                obscureText: widget.secure,
                enableSuggestions: !widget.secure,
                autocorrect: !widget.secure,
                maxLength: widget.maxLength,
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value ?? '').trim().isEmpty
                            ? 'Completa este campo.'
                            : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        child: Text(widget.action),
      ),
    ],
  );
}
