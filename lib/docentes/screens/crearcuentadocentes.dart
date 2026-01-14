// lib/admin_escolar/screens/crear_cuenta_docente.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/asignaturas.dart' show sharedSubjectsService;
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;
import 'package:cloud_firestore/cloud_firestore.dart';

typedef OnCreateRequest = Future<void> Function(Map<String, dynamic> request);

class CrearCuentaDocentesScreen extends StatefulWidget {
  final Escuela escuela;
  final List<String> nombresDisponibles; // proviene de administración
  final List<String> asignaturasDisponibles; // proviene de administración
  final OnCreateRequest? onRequestCreate; // callback para persistir la petición

  const CrearCuentaDocentesScreen({
    Key? key,
    required this.escuela,
    this.nombresDisponibles = const [],
    this.asignaturasDisponibles = const [],
    this.onRequestCreate,
  }) : super(key: key);

  @override
  State<CrearCuentaDocentesScreen> createState() =>
      _CrearCuentaDocentesScreenState();
}

class _CrearCuentaDocentesScreenState extends State<CrearCuentaDocentesScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _telefonoCtrl = TextEditingController();
  final TextEditingController _buscadorAsignaturaCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();

  // seleccion múltiple para asignaturas (nombres normalizados)
  final List<String> _asignaturasSeleccionadas = [];

  // copia local de asignaturasDisponibles para búsqueda/filtrado
  List<String> _availableSubjects = []; // <-- inicializada aquí

  bool _loading = false;
  bool _showPassword = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    // Si el padre ya pasó asignaturas, las usamos; si no, las cargamos desde el servicio compartido.
    if (widget.asignaturasDisponibles.isNotEmpty) {
      _availableSubjects = List<String>.from(widget.asignaturasDisponibles)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else {
      // cargar desde servicio compartido (async)
      sharedSubjectsService.getSubjects().then((list) {
        final names = list.map((s) => s.name).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (mounted) {
          setState(() {
            _availableSubjects = names;
          });
        }
      }).catchError((e) {
        // opcional: log o notificar, pero no romper UI
      });
    }
  }

  // Si el padre actualiza la lista de asignaturas, actualizamos la copia local.
  @override
  void didUpdateWidget(covariant CrearCuentaDocentesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asignaturasDisponibles != widget.asignaturasDisponibles) {
      setState(() {
        _availableSubjects = List<String>.from(widget.asignaturasDisponibles)
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _asignaturasSeleccionadas.retainWhere((s) => _availableSubjects.contains(s));
      });
    } else {
      // si el padre no pasó lista, but el servicio pudo haber cambiado (por admin),
      // recargamos del servicio compartido para mantener sincronización cuando vuelvan cambios.
      sharedSubjectsService.getSubjects().then((list) {
        final names = list.map((s) => s.name).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (mounted) {
          setState(() {
            _availableSubjects = names;
            _asignaturasSeleccionadas.retainWhere((s) => _availableSubjects.contains(s));
          });
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _buscadorAsignaturaCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  int _passwordStrengthScore(String pwd) {
    // Simple heuristic: longitud + variedad de clases de caracteres
    var score = 0;
    if (pwd.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score++;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)) score++;
    return score; // 0..4
  }

  String _passwordStrengthLabel(String pwd) {
    final s = _passwordStrengthScore(pwd);
    switch (s) {
      case 0:
      case 1:
        return 'Débil';
      case 2:
        return 'Aceptable';
      case 3:
        return 'Buena';
      case 4:
        return 'Fuerte';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    // validaciones: nombre, contraseña y confirmación, asignaturas
    if (!_formKey.currentState!.validate()) return;
    if (_asignaturasSeleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una asignatura')),
      );
      return;
    }

    final password = _passwordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }

    // Genera schoolId usando la misma normalización que AGestionDeMaestros
    final schoolId = normalizeSchoolIdFromEscuela(widget.escuela);

    // Construir la petición: **NO** almacenes contraseñas en texto plano en Firestore.
    // Aquí el 'request' es lo que se pasará a `onRequestCreate` (backend/Cloud Function
    // puede decidir crear el usuario en Auth y guardar profile en Firestore).
    final request = {
      'schoolId': schoolId,
      'schoolName': widget.escuela.nombre ?? '',
      'name': _nombreCtrl.text.trim(),
      'phone': _telefonoCtrl.text.trim(),
      'subjects': List<String>.from(_asignaturasSeleccionadas),
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'pending',
      // 'password': password, // opcional: enviar solo si tu backend lo requiere para crear Auth
      'createdFrom': 'self_signup',
    };

    setState(() => _loading = true);
    try {
      if (widget.onRequestCreate != null) {
        // Si tu onRequestCreate necesita la contraseña (para crear en Auth),
        // considera pasar un map separado o un parámetro extra con la password de forma segura.
        await widget.onRequestCreate!(request);
      } else {
        // demo: escribir directamente en Firestore (si lo quieres)
        // Atención: no incluir contraseñas en texto plano si haces esto.
        final db = FirebaseFirestore.instance;
        final coll = db.collection('schools').doc(schoolId).collection('teachers');
        await coll.add({
          'name': request['name'],
          'phone': request['phone'],
          'subjects': request['subjects'],
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'createdFrom': 'self_signup',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud creada (modo demo)')),
        );
      }

      // Limpieza y feedback
      _asignaturasSeleccionadas.clear();
      _telefonoCtrl.clear();
      _nombreCtrl.clear();
      _passwordCtrl.clear();
      _confirmPasswordCtrl.clear();

      if (mounted) {
        setState(() => _loading = false);
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Solicitud enviada'),
            content: const Text(
                'Tu solicitud fue enviada. La administración revisará y aprobará la cuenta.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear la solicitud: $e')),
        );
      }
    }
  }

  void _toggleAsignatura(String subject) {
    setState(() {
      if (_asignaturasSeleccionadas.contains(subject)) {
        _asignaturasSeleccionadas.remove(subject);
      } else {
        _asignaturasSeleccionadas.add(subject);
      }
    });
  }

  Future<void> _openSeleccionAsignaturas() async {
    // copia local para filtrar sin tocar el original
    final List<String> copy = List<String>.from(_availableSubjects);
    String filter = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (contextModal, setModalState) {
          final filtered = (filter.trim().isEmpty)
              ? copy
              : copy.where((s) => s.toLowerCase().contains(filter.toLowerCase())).toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            builder: (_, controller) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscadorAsignaturaCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar asignatura...',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setModalState(() {
                              filter = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _asignaturasSeleccionadas.clear();
                            _asignaturasSeleccionadas.addAll(copy);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Seleccionar todas'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              copy.isEmpty
                                  ? 'No hay asignaturas disponibles. Contacta a la administración.'
                                  : 'No se encontraron coincidencias.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final selected = _asignaturasSeleccionadas.contains(s);
                            return CheckboxListTile(
                              value: selected,
                              title: Text(s),
                              onChanged: (_) => _toggleAsignatura(s),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                      const SizedBox(width: 12),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Guardar selección')),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // limpiar buscador del modal
    _buscadorAsignaturaCtrl.clear();
    setState(() {}); // forzar repaint de chips
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) ??
        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold);

    final pwd = _passwordCtrl.text;
    final pwdScore = _passwordStrengthScore(pwd);
    final pwdLabel = _passwordStrengthLabel(pwd);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta - Docente'),
        backgroundColor: Colors.blue.shade900,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.escuela.nombre ?? 'Escuela', style: headerStyle),
                      const SizedBox(height: 8),
                      Text('Solicita la creación de tu cuenta. La administración aprobará y activará el acceso.',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 18),

                      // Autocomplete nombre
                      Autocomplete<String>(
                        optionsBuilder: (textEditingValue) {
                          final q = textEditingValue.text.toLowerCase();
                          return widget.nombresDisponibles.where((n) => n.toLowerCase().contains(q)).toList();
                        },
                        onSelected: (sel) => _nombreCtrl.text = sel,
                        fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                          controller.text = _nombreCtrl.text;
                          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Tu nombre (búscalo en la lista)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Indica tu nombre' : null,
                            onChanged: (v) => _nombreCtrl.text = v,
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Teléfono (solo almacenar)
                      TextFormField(
                        controller: _telefonoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono (opcional, solo para contacto)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                        keyboardType: TextInputType.phone,
                      ),

                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final s = v ?? '';
                          if (s.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),
                      // Strength bar
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: pwd.isEmpty ? 0 : (pwdScore / 4),
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              color: pwdScore <= 1 ? Colors.redAccent : (pwdScore == 2 ? Colors.orange : Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(pwd.isEmpty ? '' : pwdLabel, style: const TextStyle(fontSize: 12)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Confirm password
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: !_showConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar contraseña',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showConfirm = !_showConfirm),
                          ),
                        ),
                        validator: (v) {
                          final s = v ?? '';
                          if (s.isEmpty) return 'Confirma tu contraseña';
                          if (s != _passwordCtrl.text) return 'Las contraseñas no coinciden';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      const Text('Asignaturas', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _asignaturasSeleccionadas)
                            InputChip(
                              label: Text(s),
                              onDeleted: () => _toggleAsignatura(s),
                              selected: true,
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: Text(_asignaturasSeleccionadas.isEmpty ? 'Seleccionar asignaturas' : 'Agregar / editar'),
                            onPressed: _openSeleccionAsignaturas,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: const Text('La administración aprobará la cuenta. Ellos podrán activar, bloquear temporalmente o eliminar la cuenta.'),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Solicitar creación de cuenta', style: TextStyle(fontSize: 16)),
                        ),
                      ),

                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('¿Por qué solicito mi cuenta?'),
                              content: const Text('La administración mantiene la lista oficial de docentes y asignaturas. Si tu nombre o asignaturas no aparecen, solicita al administrador que te agregue.'),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                            ),
                          );
                        },
                        child: const Text('¿Necesitas ayuda?'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
