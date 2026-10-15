import 'package:edupro/widgets/team_access_gate.dart';
import 'package:edupro/widgets/school_catalog_view.dart';
import 'package:edupro/services/team_school_catalog_controller.dart';
import '../services/team_school_access_service.dart';
import '../services/team_action_verification.dart';
import '../utils/equipo_edupro_access.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:edupro/widgets/school_location_picker.dart';
import 'package:edupro/widgets/team_section_navigation.dart';

class ColegiosScreen extends StatefulWidget {
  const ColegiosScreen({super.key});
  @override
  State<ColegiosScreen> createState() => _ColegiosScreenState();
}

class _ColegiosScreenState extends State<ColegiosScreen> {
  late TeamSchoolCatalogController _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog = TeamSchoolAccessService.sharedCatalog(
      role: TeamAccessRoleScope.of(context),
    );
    _catalog.ensureFresh();
  }

  double? _coordinate(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  Future<void> _editLocation(
    BuildContext context,
    TeamSchoolRecord school,
  ) async {
    if (!EquipoEduProPermissions.canEditSchoolCore(school.role)) return;
    final location = school.data()['location'];
    final current = location is Map ? location : const <String, dynamic>{};
    final picked = await showSchoolLocationPickerDialog(
      context,
      initialLatitude: _coordinate(current['latitude']),
      initialLongitude: _coordinate(current['longitude']),
    );
    if (picked == null || !context.mounted) return;
    try {
      if (!await TeamActionVerification.confirm(context) || !context.mounted)
        return;
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateSchoolLocation').call(<String, dynamic>{
        'schoolId': school.id,
        'latitude': picked.latitude,
        'longitude': picked.longitude,
      });
      TeamSchoolAccessService.refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación guardada. Ya aparece en Red Escolar.'),
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message ??
                  'No se pudo guardar la ubicación (${error.code}).',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar la operación. Intenta nuevamente.',
            ),
          ),
        );
      }
    }
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return '—';
    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _showAssignmentResult(
    BuildContext context, {
    required String email,
    required bool created,
    required bool resetEmailSent,
  }) async {
    if (!context.mounted) return;
    if (!created) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrador asignado correctamente.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Cuenta de administrador creada'),
            content: Text(
              resetEmailSent
                  ? 'Asignamos $email al colegio y enviamos un enlace para que establezca su contraseña. Pídele que revise también la carpeta de spam.'
                  : 'Asignamos $email al colegio, pero no se pudo enviar el enlace para establecer su contraseña. Reintenta el envío desde aquí.',
            ),
            actions: [
              if (!resetEmailSent)
                TextButton(
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: email,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enlace enviado al administrador.'),
                          ),
                        );
                      }
                    } on FirebaseAuthException {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No se pudo enviar el enlace. Comprueba la configuración del correo en Firebase Auth.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Reenviar enlace'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  Future<void> _mostrarDialogCorreo(
    BuildContext context,
    String schoolCode,
  ) async {
    String email = '';
    String? errorText;
    bool createIfMissing = true;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: Text('Administrador de $schoolCode'),
                  content: SizedBox(
                    width: 460,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Correo del administrador',
                            border: OutlineInputBorder(),
                          ),
                          onChanged:
                              (value) => email = value.trim().toLowerCase(),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: createIfMissing,
                          onChanged:
                              saving
                                  ? null
                                  : (value) => setDialogState(
                                    () => createIfMissing = value ?? false,
                                  ),
                          title: const Text('Crear la cuenta si aún no existe'),
                          subtitle: const Text(
                            'El administrador recibirá un enlace para establecer su propia contraseña.',
                          ),
                        ),
                        if (errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              errorText!,
                              style: TextStyle(
                                color:
                                    Theme.of(dialogContext).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed:
                          saving
                              ? null
                              : () async {
                                if (!RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(email)) {
                                  setDialogState(
                                    () =>
                                        errorText = 'Escribe un correo válido.',
                                  );
                                  return;
                                }
                                setDialogState(() {
                                  saving = true;
                                  errorText = null;
                                });
                                try {
                                  final result =
                                      await FirebaseFunctions.instanceFor(
                                            region: 'us-central1',
                                          )
                                          .httpsCallable('assignSchoolAdmin')
                                          .call(<String, dynamic>{
                                            'schoolCode': schoolCode,
                                            'email': email,
                                            'createIfMissing': createIfMissing,
                                          });
                                  final response = Map<String, dynamic>.from(
                                    result.data as Map,
                                  );
                                  final created = response['created'] == true;
                                  var resetEmailSent = false;
                                  if (created) {
                                    try {
                                      await FirebaseAuth.instance
                                          .sendPasswordResetEmail(email: email);
                                      resetEmailSent = true;
                                    } on FirebaseAuthException {
                                      resetEmailSent = false;
                                    }
                                  }
                                  if (!dialogContext.mounted) return;
                                  final route = ModalRoute.of(dialogContext);
                                  Navigator.pop(dialogContext);
                                  await route?.completed;
                                  if (context.mounted) {
                                    await _showAssignmentResult(
                                      context,
                                      email: email,
                                      created: created,
                                      resetEmailSent: resetEmailSent,
                                    );
                                  }
                                } on FirebaseFunctionsException catch (error) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    errorText = switch (error.code) {
                                      'not-found' =>
                                        error.message ??
                                            'El colegio o la cuenta no existe.',
                                      'permission-denied' =>
                                        'Tu cuenta no tiene permiso para asignar este administrador.',
                                      'failed-precondition' =>
                                        'Completa la verificación de seguridad y vuelve a intentar.',
                                      _ =>
                                        error.message ??
                                            'No se pudo asignar el administrador (${error.code}).',
                                    };
                                  });
                                } catch (_) {
                                  if (dialogContext.mounted) {
                                    setDialogState(
                                      () =>
                                          errorText =
                                              'No se pudo completar la asignación. Intenta de nuevo.',
                                    );
                                  }
                                } finally {
                                  if (dialogContext.mounted)
                                    setDialogState(() => saving = false);
                                }
                              },
                      child: Text(
                        saving ? 'Guardando…' : 'Asignar administrador',
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Colegios'),
      leading: TeamSectionNavigation.backButton(context),
    ),
    body: SchoolCatalogView(
      controller: _catalog,
      builder: (context) {
        final schools = _catalog.records;
        if (schools.isEmpty)
          return const Center(child: Text('No hay colegios'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: schools.length,
          itemBuilder: (context, index) {
            final doc = schools[index];
            final data = doc.data();
            final code = (data['schoolCode'] ?? doc.id).toString();
            final name = (data['name'] ?? data['nombre'] ?? '').toString();
            final adminEmail = (data['adminEmail'] ?? '').toString();
            final location = data['location'];
            final hasLocation =
                location is Map &&
                _coordinate(location['latitude']) != null &&
                _coordinate(location['longitude']) != null;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Código: $code'),
                    Text('Admin: ${adminEmail.isEmpty ? '—' : adminEmail}'),
                    Text('Creado: ${_formatDate(data['createdAt'])}'),
                    Text(
                      hasLocation
                          ? 'Ubicación: registrada'
                          : 'Ubicación: pendiente de marcar',
                    ),
                  ],
                ),
                trailing: Wrap(
                  children: [
                    if (EquipoEduProPermissions.canEditSchoolCore(doc.role))
                      IconButton(
                        icon: Icon(
                          hasLocation
                              ? Icons.edit_location_alt_outlined
                              : Icons.add_location_alt_outlined,
                        ),
                        tooltip:
                            hasLocation
                                ? 'Editar ubicación'
                                : 'Marcar ubicación exacta',
                        onPressed: () => _editLocation(context, doc),
                      ),
                    if (EquipoEduProPermissions.canAssignSchoolAdmin(doc.role))
                      IconButton(
                        icon: const Icon(Icons.email_outlined),
                        tooltip: 'Asignar correo admin',
                        onPressed: () => _mostrarDialogCorreo(context, code),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
