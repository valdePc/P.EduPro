import 'package:edupro/widgets/school_catalog_view.dart';
import 'package:edupro/services/team_school_catalog_controller.dart';
import '../services/team_action_verification.dart';
// lib/screens/admin_general.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:edupro/data/curriculo_base_docs.dart';
import 'package:edupro/data/dominican_locations.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/models/school_administrator_details.dart';
import 'package:edupro/models/school_billing_dates.dart';
import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:edupro/utils/auth_input_validation.dart';
import 'package:edupro/utils/school_form_formatters.dart';
import 'package:edupro/services/edupro_two_factor_service.dart';
import 'package:edupro/widgets/app_info_menu.dart';
import 'package:edupro/widgets/school_location_picker.dart';
import 'package:edupro/widgets/school_plan_fields.dart';
import 'package:edupro/widgets/school_plan_edit_dialog.dart';
import 'package:edupro/widgets/school_summary_loader.dart';
import 'package:edupro/widgets/school_master_detail_layout.dart';
import 'package:edupro/widgets/school_creation_dialog.dart';
import 'package:edupro/widgets/school_registration_secret_dialog.dart';
import 'package:edupro/widgets/team_section_navigation.dart';
import 'package:edupro/widgets/team_access_gate.dart';
import 'package:edupro/services/team_school_access_service.dart';
import 'package:edupro/screens/team_billing_screen.dart';

class AdminGeneralScreen extends StatefulWidget {
  final int initialTabIndex;
  final String currentRoute;

  const AdminGeneralScreen({
    Key? key,
    this.initialTabIndex = 0,
    this.currentRoute = '/panel',
  }) : super(key: key);

  @override
  State<AdminGeneralScreen> createState() => _AdminGeneralScreenState();
}

class _AdminGeneralScreenState extends State<AdminGeneralScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );
  late final Stream<String?> _sessionChanges;
  late TeamSchoolCatalogController _catalog;
  final _summaryCache = SchoolSummaryCache();
  String _teamRole = EquipoEduProRoles.denied;

  static const Color _adminBlue = Color(0xFF1A237E);
  static const Color _adminBlueSoft = Color(0xFFE8ECFF);

  static const List<Map<String, String>> _defaultCurriculoDocs =
      kCurriculoBaseDocs;

  String? _selectedSchoolId;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    if (widget.initialTabIndex > 0) {
      _tabController.index = 0;
    }
    _sessionChanges = _auth.authStateChanges().map((user) => user?.uid);
  }

  @override
  void dispose() {
    _summaryCache.clear();
    _tabController.dispose();
    super.dispose();
  }

  String _genCode() {
    final rnd = Random.secure();
    return List.generate(
      8,
      (_) => rnd.nextInt(36).toRadixString(36),
    ).join().toUpperCase();
  }

  Future<String> _loadCurrentTeamRole() async {
    final user = _auth.currentUser;
    if (user == null) return EquipoEduProRoles.denied;
    return EquipoEduProAccess.currentTeamRole(user);
  }

  Future<void> _signOutToLogin() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Intentamos continuar para no dejar la UI bloqueada.
    }
    try {
      final gs = GoogleSignIn.instance;
      await gs.initialize();
      await gs.signOut();
    } catch (_) {
      // Puede no haber sesión de Google activa; no bloqueamos la salida.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Cerrar sesion'),
            content: const Text(
              'Vas a salir del panel de administracion general.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Salir'),
              ),
            ],
          ),
    );
    if (shouldSignOut == true) {
      await _signOutToLogin();
    }
  }

  // ---------------- HELPERS (strings limpios para Firestore) ----------------
  String? _trimOrNull(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  String? _keyOrNull(String? v) {
    final t = (v ?? '').trim().toLowerCase();
    return t.isEmpty ? null : t;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'activa':
        return Colors.green;
      case 'suspendida':
        return Colors.orange;
      case 'vencida':
        return Colors.deepOrange;
      case 'bloqueada':
        return Colors.red;
      case 'borrador':
      default:
        return Colors.blueGrey;
    }
  }

  String _schoolStatusFromData(Map<String, dynamic> d) {
    final raw = (d['accountStatus'] ?? d['status'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return (d['active'] ?? true) == true ? 'activa' : 'suspendida';
  }

  Future<String?> _solicitarPassword(String titulo) async {
    String input = '';
    Future<dynamic>? transition;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        transition = ModalRoute.of(ctx)?.completed;
        return AlertDialog(
          title: Text(titulo),
          content: TextField(
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Contrasena'),
            onChanged: (v) => input = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, input),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    await transition;
    return result;
  }

  Future<bool> _confirmSchoolCreationIdentity({
    required String schoolName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      _mostrarError('No hay una sesion activa para confirmar la creacion.');
      return false;
    }

    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      _mostrarError(
        'La cuenta actual no tiene correo para validar la creacion del colegio.',
      );
      return false;
    }

    final providerIds =
        user.providerData
            .map((p) => p.providerId.trim().toLowerCase())
            .where((p) => p.isNotEmpty)
            .toSet();
    final hasPasswordProvider =
        providerIds.isEmpty || providerIds.contains('password');

    if (providerIds.contains('google.com')) {
      if (!EquipoEduProPermissions.canCreateSchools(_teamRole)) {
        _mostrarError(
          'Esta cuenta no tiene un proveedor compatible para confirmar la creación.',
        );
        return false;
      }
      try {
        if (kIsWeb) {
          final provider = GoogleAuthProvider();
          provider.setCustomParameters({'login_hint': email});
          await user.reauthenticateWithPopup(provider);
        } else {
          final googleSignIn = GoogleSignIn.instance;
          await googleSignIn.initialize();
          final googleUser = await googleSignIn.authenticate(
            scopeHint: const ['email'],
          );
          final googleAuth = googleUser.authentication;
          final idToken = googleAuth.idToken;
          if (idToken == null) {
            throw StateError('Google no devolvió un token de identidad.');
          }
          await user.reauthenticateWithCredential(
            GoogleAuthProvider.credential(idToken: idToken),
          );
        }
        await user.getIdToken(true);
        return _auth.currentUser?.uid == user.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'popup-closed-by-user' &&
            e.code != 'cancelled-popup-request') {
          _mostrarError(
            'No se pudo confirmar tu cuenta de Google. Inténtalo de nuevo.',
          );
        }
        return false;
      } catch (_) {
        _mostrarError(
          'No se pudo confirmar tu cuenta de Google. Inténtalo de nuevo.',
        );
        return false;
      }
    }

    if (!hasPasswordProvider) {
      _mostrarError(
        'Esta cuenta no tiene un proveedor compatible para confirmar la creación.',
      );
      return false;
    }

    final password = await _solicitarPassword(
      'Confirma tu contrasena para crear ${schoolName.trim().isEmpty ? 'el colegio' : schoolName.trim()}',
    );

    if (password == null) return false;
    if (password.isEmpty) {
      _mostrarError('Debes escribir tu contrasena para confirmar.');
      return false;
    }

    try {
      final credential = exactPasswordCredential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      await user.getIdToken(true);
      return true;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          _mostrarError('La contrasena no coincide con la sesion actual.');
          break;
        case 'too-many-requests':
          _mostrarError(
            'Demasiados intentos. Espera un momento e intentalo otra vez.',
          );
          break;
        default:
          _mostrarError('No se pudo validar la contrasena. Intenta nuevamente.');
      }
      return false;
    } catch (_) {
      _mostrarError('No se pudo validar la contrasena del usuario actual.');
      return false;
    }
  }

  void _mostrarError([String msg = 'Contrasena incorrecta']) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copiado: $texto')));
  }

  void _showAddDialog({
    required String title,
    required String hint,
    required Future<void> Function(String) onSave,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        String input = '';
        return AlertDialog(
          title: Text(title),
          content: TextField(
            decoration: InputDecoration(labelText: hint),
            onChanged: (v) => input = v.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (input.isEmpty) return;
                Navigator.pop(ctx);
                await onSave(input);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  // ---------------- FIRESTORE: COLEGIOS ----------------

  // ---------------- FIRESTORE: COLEGIOS ----------------

  // Ya no usamos grados por defecto (lo dejamos por compatibilidad)
  List<String> _defaultGrades() => const <String>[];

  String _buildRoleLink(String schoolId, String module) {
    return 'https://edupro-8c4fd.web.app/#/eduproapp/$schoolId/$module';
  }

  // Wrapper por compatibilidad (si en algÃºn sitio aÃºn llaman este mÃ©todo)
  Future<void> _crearColegioFirestore(String nombre) async {
    await _crearColegioFirestoreV2(nombre: nombre);
  }

  Future<Map<String, dynamic>> _crearColegioFirestoreV2({
    required String nombre,
    String? officialName,
    String? planTier,
    int? adminsLimit,
    int? teachersLimit,
    int? studentsLimit,
    String? schoolType,
    String? country,
    String? timezone,
    String? regionalCode,
    String? regionalName,
    String? districtCode,
    String? districtName,
    String? province,
    String? municipality,
    String? sector,
    String? addressLine,
    double? latitude,
    double? longitude,
    String? contactName,
    String? contactRole,
    String? contactPhone,
    String? contactWhatsApp,
    String? contactEmail,
    String? adminEmail,
    DateTime? foundedAt,
  }) async {
    final cleanName = nombre.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Debes indicar el nombre del colegio.');
    }

    if (!EquipoEduProPermissions.canCreateSchools(_teamRole)) {
      throw StateError('El rol actual no tiene permiso para crear colegios.');
    }

    final plan = _trimOrNull(planTier) ?? 'base';
    final adminCap = adminsLimit ?? _defaultAdminsLimitForPlan(plan);
    final teacherCap = teachersLimit ?? _defaultTeachersLimitForPlan(plan);
    final studentCap = studentsLimit ?? _defaultStudentsLimitForPlan(plan);
    // Reauthentication above can change auth_time. Recheck the server's MFA
    // decision for the current session immediately before this privileged call.
    final sessionUser = _auth.currentUser;
    if (!mounted || sessionUser == null) {
      throw StateError('Debes iniciar sesion para crear el colegio.');
    }
    final verified = await EduProTwoFactorService.ensureVerified(
      context,
      audience: 'admin_general',
    );
    if (!mounted || !verified || _auth.currentUser?.uid != sessionUser.uid) {
      throw StateError(
        'Debes completar la verificacion para crear el colegio.',
      );
    }
    final callable = _fn.httpsCallable('createSchool');
    final result = await callable.call(<String, dynamic>{
      'nombre': cleanName,
      'officialName': officialName,
      'planTier': plan,
      'adminsLimit': adminCap,
      'teachersLimit': teacherCap,
      'studentsLimit': studentCap,
      'schoolType': schoolType,
      'country': country,
      'timezone': timezone,
      'regionalCode': regionalCode,
      'regionalName': regionalName,
      'districtCode': districtCode,
      'districtName': districtName,
      'province': province,
      'municipality': municipality,
      'sector': sector,
      'addressLine': addressLine,
      'latitude': latitude,
      'longitude': longitude,
      'contactName': contactName,
      'contactRole': contactRole,
      'contactPhone': contactPhone,
      'contactWhatsApp': contactWhatsApp,
      'contactEmail': contactEmail,
      'adminEmail': adminEmail,
      'foundedAtMillis': foundedAt?.millisecondsSinceEpoch,
      'curriculoDocs': _defaultCurriculoDocs,
    });

    final payload = Map<String, dynamic>.from(
      (result.data as Map?)?.cast<dynamic, dynamic>() ??
          const <dynamic, dynamic>{},
    );
    final code =
        (payload['schoolId'] ?? payload['code'] ?? '').toString().trim();

    if (payload['ok'] != true || code.isEmpty) {
      throw StateError('No se pudo confirmar la creación del colegio.');
    }
    return payload;
  }

  Future<void> _notifySchoolCreated(
    Map<String, dynamic> payload,
    String fallbackName,
    String? creatorUid,
  ) async {
    final pwd = (payload.remove('password') ?? '').toString();

    TeamSchoolAccessService.refresh();
    final schoolLabel =
        (payload['officialName'] ?? fallbackName).toString().trim();
    bool canViewSecret() =>
        mounted && creatorUid != null && _auth.currentUser?.uid == creatorUid;
    if (pwd.isNotEmpty && canViewSecret()) {
      ModalRoute<void>? secretRoute;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          secretRoute = ModalRoute.of<void>(dialogContext);
          return SchoolRegistrationSecretDialog(
            schoolName: schoolLabel,
            secret: pwd,
            canAccess: canViewSecret,
            accessChanges: _auth.authStateChanges().map(
              (user) => user != null && user.uid == creatorUid,
            ),
          );
        },
      );
      await secretRoute?.completed;
    }
    if (!canViewSecret()) return;
    final assignedAdminEmail = (payload['adminEmail'] ?? '').toString().trim();
    if (payload['adminAccountCreated'] == true &&
        assignedAdminEmail.isNotEmpty) {
      var emailSent = false;
      try {
        await _auth.sendPasswordResetEmail(email: assignedAdminEmail);
        emailSent = true;
      } catch (_) {
        // La escuela y su administrador ya existen; no reintentar createSchool.
      }
      if (!mounted) return;
      if (emailSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enviamos a $assignedAdminEmail un enlace para establecer su contraseña.',
            ),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('Administrador asignado'),
                content: Text(
                  'El colegio y la cuenta $assignedAdminEmail se crearon, pero no se pudo enviar el enlace para establecer la contraseña. Reintenta el envío sin volver a crear el colegio.',
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await _auth.sendPasswordResetEmail(
                          email: assignedAdminEmail,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enlace enviado al administrador.'),
                            ),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo enviar el enlace. Revisa la configuración de correo de Firebase Auth.',
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
    }
  }

  int _defaultAdminsLimitForPlan(String planTier) =>
      SchoolPlanValues.defaultsFor(planTier).adminsLimit;

  int _defaultTeachersLimitForPlan(String planTier) =>
      SchoolPlanValues.defaultsFor(planTier).teachersLimit;

  int _defaultStudentsLimitForPlan(String planTier) =>
      SchoolPlanValues.defaultsFor(planTier).studentsLimit;

  int _schoolLimitFromData(
    Map<String, dynamic> data,
    String key,
    int fallback,
  ) {
    final limitsRaw = data['planLimits'];
    if (limitsRaw is Map) {
      final limits = Map<String, dynamic>.from(limitsRaw);
      final raw = limits[key];
      if (raw is num) return raw.toInt();
    }

    final flatKey = switch (key) {
      'admins' => 'adminsLimit',
      'teachers' => 'teachersLimit',
      'students' => 'studentsLimit',
      _ => '',
    };
    if (flatKey.isNotEmpty) {
      final raw = data[flatKey];
      if (raw is num) return raw.toInt();
    }
    return fallback;
  }

  Future<void> _seedCurriculoDocsForSchool(String schoolId) async {
    final sid = schoolId.trim();
    if (sid.isEmpty) return;

    final col = _db.collection('schools').doc(sid).collection('curriculo_docs');
    final batch = _db.batch();
    final now = Timestamp.now();

    for (int i = 0; i < _defaultCurriculoDocs.length; i++) {
      final d = _defaultCurriculoDocs[i];
      final id = 'doc_${(i + 1).toString().padLeft(2, '0')}';
      batch.set(col.doc(id), {
        'title': (d['title'] ?? '').trim(),
        'category': (d['category'] ?? '').trim(),
        'url': (d['url'] ?? '').trim(),
        'order': i + 1,
        'active': true,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> _showCreateSchoolDialog() async {
    if (!EquipoEduProPermissions.canCreateSchools(_teamRole)) {
      _mostrarError('Tu rol actual no tiene permiso para crear colegios.');
      return;
    }

    final formKey = GlobalKey<FormState>();

    String nombre = '';
    String officialName = '';
    final planController = SchoolPlanController();
    Map<String, dynamic>? createdSchool;
    String? creatorUid;
    String schoolType = 'Privado';
    const String country = 'República Dominicana';
    const String timezone = 'America/Santo_Domingo';
    String regionalCode = '';
    String regionalName = '';
    String districtCode = '';
    String districtName = '';

    String province = '';
    String municipality = '';
    final provinceController = TextEditingController();
    final municipalityController = TextEditingController();
    String sector = '';
    String addressLine = '';
    SchoolLocationSelection? selectedLocation;

    String contactName = '';
    String contactRole = '';
    String contactPhone = '';
    String contactWhatsApp = '';
    String contactEmail = '';

    DateTime? foundedAt;
    ModalRoute<dynamic>? dialogRoute;

    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogRoute = ModalRoute.of(ctx);
          return SchoolCreationDialog(
            formKey: formKey,
            contentBuilder:
                (ctx, saving) => StatefulBuilder(
                  builder:
                      (ctx, setDialogState) => SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                          child: Form(
                            key: formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Datos del centro',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: const [
                                    SchoolNameCapitalizationFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre del colegio *',
                                    helperText:
                                        'Se escribe con mayúsculas automáticamente',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => nombre = v.trim(),
                                  validator:
                                      (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Requerido'
                                              : null,
                                ),
                                const SizedBox(height: 12),

                                TextFormField(
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: const [
                                    SchoolNameCapitalizationFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre oficial (opcional)',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => officialName = v.trim(),
                                ),
                                const SizedBox(height: 12),

                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final fieldWidth =
                                        constraints.maxWidth < 430
                                            ? constraints.maxWidth
                                            : (constraints.maxWidth - 20) / 3;
                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        SizedBox(
                                          width: fieldWidth,
                                          child: SchoolPlanSelector(
                                            controller: planController,
                                            editable:
                                                !saving &&
                                                EquipoEduProPermissions.canChangeSchoolPlansAndLimits(
                                                  _teamRole,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: fieldWidth,
                                          child: DropdownButtonFormField<
                                            String
                                          >(
                                            value: schoolType,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Tipo de centro',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'Privado',
                                                child: Text('Privado'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'Publico',
                                                child: Text('Publico'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'Semiprivado',
                                                child: Text('Semiprivado'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'Tecnico',
                                                child: Text('Tecnico'),
                                              ),
                                            ],
                                            onChanged:
                                                (v) =>
                                                    schoolType =
                                                        (v ?? 'Privado').trim(),
                                          ),
                                        ),
                                        SizedBox(
                                          width: fieldWidth,
                                          child: const InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: 'País',
                                              border: OutlineInputBorder(),
                                            ),
                                            child: Text(
                                              'República Dominicana',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),

                                SchoolPlanLimitFields(
                                  controller: planController,
                                  editable:
                                      !saving &&
                                      EquipoEduProPermissions.canChangeSchoolPlansAndLimits(
                                        _teamRole,
                                      ),
                                ),
                                const SizedBox(height: 10),

                                const InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Zona horaria',
                                    border: OutlineInputBorder(),
                                  ),
                                  child: Text('America/Santo_Domingo'),
                                ),
                                const SizedBox(height: 12),

                                InkWell(
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate:
                                          foundedAt ??
                                          DateTime(now.year - 10, 1, 1),
                                      firstDate: DateTime(1900, 1, 1),
                                      lastDate: now,
                                    );
                                    if (picked != null) {
                                      setDialogState(() => foundedAt = picked);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Fecha de fundacion (opcional)',
                                      border: OutlineInputBorder(),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          foundedAt == null
                                              ? 'Seleccionar fecha'
                                              : '${foundedAt!.day}/${foundedAt!.month}/${foundedAt!.year}',
                                        ),
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                const Divider(height: 30),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Ubicación',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Codigo regional (ej: 15)',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => regionalCode = v,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: const [
                                          SchoolNameCapitalizationFormatter(),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Nombre regional',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => regionalName = v,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9-]'),
                                          ),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Distrito educativo (ej: 15-02)',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => districtCode = v,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: const [
                                          SchoolNameCapitalizationFormatter(),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Nombre distrito',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => districtName = v,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final narrow = constraints.maxWidth < 430;
                                    final fieldWidth =
                                        narrow
                                            ? constraints.maxWidth
                                            : (constraints.maxWidth - 10) / 2;
                                    final provinceField = FormField<String>(
                                      validator:
                                          (_) =>
                                              !dominicanMunicipalitiesByProvince
                                                          .containsKey(
                                                            province,
                                                          ) ||
                                                      provinceController.text !=
                                                          province
                                                  ? 'Selecciona una provincia'
                                                  : null,
                                      builder:
                                          (field) => Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              DropdownMenu<String>(
                                                controller: provinceController,
                                                width: fieldWidth,
                                                enableFilter: true,
                                                requestFocusOnTap: true,
                                                menuHeight: 300,
                                                label: const Text(
                                                  'Provincia *',
                                                ),
                                                hintText: 'Busca una provincia',
                                                dropdownMenuEntries:
                                                    dominicanMunicipalitiesByProvince
                                                        .keys
                                                        .map(
                                                          (name) =>
                                                              DropdownMenuEntry(
                                                                value: name,
                                                                label: name,
                                                              ),
                                                        )
                                                        .toList(),
                                                onSelected: (value) {
                                                  setDialogState(() {
                                                    province = value ?? '';
                                                    provinceController.text =
                                                        province;
                                                    municipality = '';
                                                    municipalityController
                                                        .clear();
                                                  });
                                                  field.didChange(value);
                                                },
                                              ),
                                              if (field.hasError)
                                                Text(
                                                  field.errorText!,
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                  ),
                                                ),
                                            ],
                                          ),
                                    );
                                    final municipalityField = FormField<String>(
                                      key: ValueKey('municipality-$province'),
                                      validator:
                                          (_) =>
                                              !(dominicanMunicipalitiesByProvince[province] ??
                                                              const <String>[])
                                                          .contains(
                                                            municipality,
                                                          ) ||
                                                      municipalityController
                                                              .text !=
                                                          municipality
                                                  ? 'Selecciona un municipio'
                                                  : null,
                                      builder:
                                          (field) => Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              DropdownMenu<String>(
                                                controller:
                                                    municipalityController,
                                                key: ValueKey(
                                                  'municipality-menu-$province',
                                                ),
                                                width: fieldWidth,
                                                enabled: province.isNotEmpty,
                                                enableFilter: true,
                                                requestFocusOnTap: true,
                                                menuHeight: 300,
                                                label: const Text(
                                                  'Municipio *',
                                                ),
                                                hintText:
                                                    province.isEmpty
                                                        ? 'Elige una provincia'
                                                        : 'Busca un municipio',
                                                dropdownMenuEntries:
                                                    (dominicanMunicipalitiesByProvince[province] ??
                                                            const <String>[])
                                                        .map(
                                                          (name) =>
                                                              DropdownMenuEntry(
                                                                value: name,
                                                                label: name,
                                                              ),
                                                        )
                                                        .toList(),
                                                onSelected: (value) {
                                                  municipality = value ?? '';
                                                  municipalityController.text =
                                                      municipality;
                                                  field.didChange(value);
                                                },
                                              ),
                                              if (field.hasError)
                                                Text(
                                                  field.errorText!,
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                  ),
                                                ),
                                            ],
                                          ),
                                    );
                                    return narrow
                                        ? Column(
                                          children: [
                                            provinceField,
                                            const SizedBox(height: 10),
                                            municipalityField,
                                          ],
                                        )
                                        : Row(
                                          children: [
                                            Expanded(child: provinceField),
                                            const SizedBox(width: 10),
                                            Expanded(child: municipalityField),
                                          ],
                                        );
                                  },
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: const [
                                          SchoolNameCapitalizationFormatter(),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Sector (opcional)',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => sector = v,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: const [
                                          SchoolNameCapitalizationFormatter(),
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Direccion (linea)',
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (v) => addressLine = v,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                FormField<SchoolLocationSelection>(
                                  validator:
                                      (_) =>
                                          selectedLocation == null
                                              ? 'Selecciona la ubicación exacta del colegio.'
                                              : null,
                                  builder:
                                      (field) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: OutlinedButton.icon(
                                              onPressed: () async {
                                                final picked =
                                                    await showSchoolLocationPickerDialog(
                                                      ctx,
                                                      initialLatitude:
                                                          selectedLocation
                                                              ?.latitude,
                                                      initialLongitude:
                                                          selectedLocation
                                                              ?.longitude,
                                                    );
                                                if (picked == null ||
                                                    !ctx.mounted)
                                                  return;
                                                setDialogState(
                                                  () =>
                                                      selectedLocation = picked,
                                                );
                                                field.didChange(picked);
                                              },
                                              icon: const Icon(
                                                Icons.add_location_alt_outlined,
                                              ),
                                              label: Text(
                                                selectedLocation == null
                                                    ? 'Marcar ubicación exacta en el mapa *'
                                                    : 'Cambiar ubicación del colegio',
                                              ),
                                            ),
                                          ),
                                          if (field.hasError)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                field.errorText!,
                                                style: TextStyle(
                                                  color:
                                                      Theme.of(
                                                        ctx,
                                                      ).colorScheme.error,
                                                ),
                                              ),
                                            ),
                                          if (selectedLocation != null) ...[
                                            const SizedBox(height: 8),
                                            SchoolLocationPreviewMap(
                                              latitude:
                                                  selectedLocation!.latitude,
                                              longitude:
                                                  selectedLocation!.longitude,
                                              height: 150,
                                            ),
                                          ],
                                        ],
                                      ),
                                ),
                                const SizedBox(height: 12),

                                const Divider(height: 30),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Contacto',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: const [
                                    SchoolNameCapitalizationFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Contacto - Nombre',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => contactName = v,
                                ),
                                const SizedBox(height: 10),

                                TextFormField(
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: const [
                                    SchoolNameCapitalizationFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Contacto - Cargo',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => contactRole = v,
                                ),
                                const SizedBox(height: 10),

                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final fieldWidth =
                                        constraints.maxWidth < 430
                                            ? constraints.maxWidth
                                            : (constraints.maxWidth - 10) / 2;
                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        SizedBox(
                                          width: fieldWidth,
                                          child: TextFormField(
                                            inputFormatters: const [
                                              SchoolPhoneFormatter(),
                                            ],
                                            validator:
                                                SchoolPhoneFormatter.validate,
                                            decoration: const InputDecoration(
                                              labelText: 'Telefono',
                                              hintText: '(809) 555-1234',
                                              border: OutlineInputBorder(),
                                            ),
                                            keyboardType: TextInputType.phone,
                                            onChanged: (v) => contactPhone = v,
                                          ),
                                        ),
                                        SizedBox(
                                          width: fieldWidth,
                                          child: TextFormField(
                                            inputFormatters: const [
                                              SchoolPhoneFormatter(),
                                            ],
                                            validator:
                                                SchoolPhoneFormatter.validate,
                                            decoration: const InputDecoration(
                                              labelText: 'WhatsApp',
                                              hintText: '+1 (809) 555-1234',
                                              border: OutlineInputBorder(),
                                            ),
                                            keyboardType: TextInputType.phone,
                                            onChanged:
                                                (v) => contactWhatsApp = v,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),

                                TextFormField(
                                  decoration: InputDecoration(
                                    labelText:
                                        EquipoEduProPermissions.canAssignSchoolAdmin(
                                              _teamRole,
                                            )
                                            ? 'Correo del administrador escolar (opcional)'
                                            : 'Correo de contacto (opcional)',
                                    helperText:
                                        EquipoEduProPermissions.canAssignSchoolAdmin(
                                              _teamRole,
                                            )
                                            ? 'Si lo indicas, quedará asignado al colegio y podrá configurar su acceso.'
                                            : 'La asignación de acceso corresponde al superadministrador.',
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  validator: (value) {
                                    final email = (value ?? '').trim();
                                    if (email.isEmpty) return null;
                                    return RegExp(
                                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                        ).hasMatch(email)
                                        ? null
                                        : 'Correo no válido';
                                  },
                                  onChanged:
                                      (v) =>
                                          contactEmail = v.trim().toLowerCase(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
            onCreate: () async {
              final selectedPlan = planController.readValues();
              final confirmed = await _confirmSchoolCreationIdentity(
                schoolName:
                    officialName.trim().isNotEmpty
                        ? officialName.trim()
                        : nombre.trim(),
              );
              if (!confirmed || !mounted) return false;
              creatorUid = _auth.currentUser?.uid;
              createdSchool = await _crearColegioFirestoreV2(
                nombre: nombre,
                officialName: officialName,
                planTier: selectedPlan.planTier,
                adminsLimit: selectedPlan.adminsLimit,
                teachersLimit: selectedPlan.teachersLimit,
                studentsLimit: selectedPlan.studentsLimit,
                schoolType: schoolType,
                country: country,
                timezone: timezone,
                regionalCode: regionalCode,
                regionalName: regionalName,
                districtCode: districtCode,
                districtName: districtName,
                province: province,
                municipality: municipality,
                sector: sector,
                addressLine: addressLine,
                latitude: selectedLocation!.latitude,
                longitude: selectedLocation!.longitude,
                contactName: contactName,
                contactRole: contactRole,
                contactPhone: contactPhone,
                contactWhatsApp: contactWhatsApp,
                contactEmail: contactEmail,
                adminEmail:
                    EquipoEduProPermissions.canAssignSchoolAdmin(_teamRole)
                        ? contactEmail
                        : null,
                foundedAt: foundedAt,
              );
              return true;
            },
            errorMessage: _schoolCreationErrorMessage,
          );
        },
      );
    } finally {
      await dialogRoute?.completed;
      planController.dispose();
      provinceController.dispose();
      municipalityController.dispose();
    }
    // The school is already committed. Notification errors must not reopen the
    // form or offer another createSchool request for the same successful draft.
    if (createdSchool != null && mounted) {
      try {
        await _notifySchoolCreated(createdSchool!, nombre.trim(), creatorUid);
      } catch (_) {
        if (mounted)
          _mostrarError(
            'El colegio fue creado, pero no se pudo completar la notificación. Consulta el colegio en el menú.',
          );
      }
    }
  }

  String _schoolCreationErrorMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'No se autorizó la creación. Revisa los permisos y el horario de tu cuenta. Tus datos siguen aquí.';
        case 'unauthenticated':
          return 'No se pudo validar tu sesión. Vuelve a confirmar tu identidad; tus datos siguen aquí.';
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return 'No se pudo confirmar la creación. Comprueba tu conexión antes de volver a intentarlo. Tus datos siguen aquí.';
        case 'resource-exhausted':
          return 'Se alcanzó el límite de intentos. Espera un momento; tus datos siguen aquí.';
        case 'invalid-argument':
          return error.message ??
              'Revisa los datos del colegio antes de volver a intentarlo.';
        case 'failed-precondition':
          return 'No se pudo completar la verificación necesaria. Tus datos siguen aquí; vuelve a intentarlo.';
      }
    }
    if (error is StateError) return error.message.toString();
    if (error is ArgumentError) return error.message.toString();
    return 'No se pudo completar la creación. Tus datos siguen aquí; vuelve a intentarlo.';
  }

  Escuela _escuelaFromDoc(TeamSchoolRecord doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    final fecha = ts is Timestamp ? ts.toDate() : DateTime.now();

    final e = Escuela(
      id: doc.id, // âœ… NUEVO: Document ID real (ej: ZC6YVOBP)
      nombre: (d['name'] ?? '').toString(),
      adminLink: (d['adminLink'] ?? _buildRoleLink(doc.id, 'admin')).toString(),
      profLink: (d['profLink'] ?? '').toString(),
      alumLink: (d['alumLink'] ?? '').toString(),
      fecha: fecha,
      grados:
          (d['grades'] is List)
              ? (d['grades'] as List).map((x) => x.toString()).toList()
              : <String>[],
    );

    // si tu modelo tiene "activo" como var, lo seteamos
    try {
      e.activo = (d['active'] ?? true) == true;
    } catch (_) {}

    return e;
  }

  _SchoolMasterRecord _schoolRecordFromDoc(TeamSchoolRecord doc) {
    final d = doc.data();
    final escuela = _escuelaFromDoc(doc);
    final contact =
        (d['contact'] is Map)
            ? Map<String, dynamic>.from(d['contact'] as Map)
            : <String, dynamic>{};
    final location =
        (d['location'] is Map)
            ? Map<String, dynamic>.from(d['location'] as Map)
            : <String, dynamic>{};
    final modulesRaw = d['modulesEnabled'];
    final levelsRaw = d['levelsEnabled'];

    return _SchoolMasterRecord(
      escuela: escuela,
      officialName: (d['officialName'] ?? d['name'] ?? '').toString().trim(),
      institutionCode:
          (d['institutionCode'] ?? d['code'] ?? doc.id).toString().trim(),
      schoolType: (d['schoolType'] ?? 'No definido').toString().trim(),
      country: (d['country'] ?? 'No definido').toString().trim(),
      timezone: (d['timezone'] ?? 'No definida').toString().trim(),
      status: _schoolStatusFromData(d),
      lifecycleStage: (d['lifecycleStage'] ?? 'activa').toString().trim(),
      planTier: (d['planTier'] ?? 'base').toString().trim(),
      planPrice: ((d['planPrice'] as num?) ?? 0).toDouble(),
      maxUsers: (d['maxUsers'] as num?)?.toInt() ?? 0,
      adminsLimit: _schoolLimitFromData(
        d,
        'admins',
        _defaultAdminsLimitForPlan((d['planTier'] ?? 'base').toString()),
      ),
      teachersLimit: _schoolLimitFromData(
        d,
        'teachers',
        _defaultTeachersLimitForPlan((d['planTier'] ?? 'base').toString()),
      ),
      studentsLimit: _schoolLimitFromData(
        d,
        'students',
        _defaultStudentsLimitForPlan((d['planTier'] ?? 'base').toString()),
      ),
      contactName: (contact['name'] ?? '').toString().trim(),
      contactRole: (contact['role'] ?? '').toString().trim(),
      contactPhone: (contact['phone'] ?? '').toString().trim(),
      contactEmail: (contact['email'] ?? '').toString().trim(),
      addressLine: (location['addressLine'] ?? '').toString().trim(),
      province: (location['province'] ?? '').toString().trim(),
      municipality: (location['municipality'] ?? '').toString().trim(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      startedAt: (d['startedAt'] as Timestamp?)?.toDate(),
      billingDates: SchoolBillingDates.fromMap(d),
      modulesEnabled:
          modulesRaw is List
              ? modulesRaw.map((e) => e.toString()).toList()
              : const <String>[],
      levelsEnabled:
          levelsRaw is List
              ? levelsRaw.map((e) => e.toString()).toList()
              : const <String>[],
    );
  }

  Future<Map<String, dynamic>> _loadSchoolSummary(String id) async {
    final data = await TeamSchoolAccessService.call('getTeamSchoolSummary', {
      'schoolId': id,
    });
    // Validate inside the Future so malformed responses use the retry UI.
    _SchoolOperationalSnapshot.fromMap(data);
    return data;
  }

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    return TeamAccessGate(
      loadRole: _loadCurrentTeamRole,
      currentSessionId: () => _auth.currentUser?.uid,
      sessionChanges: _sessionChanges,
      onCheckStarted: () {
        _teamRole = EquipoEduProRoles.denied;
        _summaryCache.clear();
      },
      onExit: _signOutToLogin,
      allowedBuilder: (context, role) {
        _teamRole = role;
        _catalog = TeamSchoolAccessService.sharedCatalog(role: role);
        _catalog.ensureFresh();
        if (_teamRole == EquipoEduProRoles.billingAdmin) {
          return const TeamBillingScreen();
        }
        final isMobile = MediaQuery.of(context).size.width < 800;
        final currentRoute = widget.currentRoute;
        final routeContent = _routeContent(context, currentRoute, _teamRole);
        final routeTabLabel = _routeTabLabel(currentRoute);
        final routeTabIcon = _routeTabIcon(currentRoute);

        // Si no hay auth, tus rules van a denegar TODO.
        if (_auth.currentUser == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('EduPro')),
            body: const Center(
              child: Text(
                'No hay sesion iniciada.\n\nInicia sesion con tu cuenta del equipo para usar este panel.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return DefaultTabController(
          length: 1,
          child: Scaffold(
            drawer:
                isMobile
                    ? Drawer(
                      backgroundColor: _adminBlue,
                      child: _buildSidebar(currentRoute, _teamRole),
                    )
                    : null,
            appBar: AppBar(
              backgroundColor: _adminBlue,
              foregroundColor: Colors.white,
              leading:
                  currentRoute != '/panel' && !isMobile
                      ? TeamSectionNavigation.backButton(
                        context,
                        color: Colors.white,
                      )
                      : null,
              title: Text(EquipoEduProRoles.label(_teamRole)),
              actions: [
                if (currentRoute != '/panel' && isMobile)
                  TeamSectionNavigation.backButton(
                    context,
                    color: Colors.white,
                  ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: Container(
                  color: isMobile ? null : Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.amber,
                    labelColor: _adminBlue,
                    unselectedLabelColor: Colors.black87,
                    tabs: [Tab(text: routeTabLabel, icon: Icon(routeTabIcon))],
                  ),
                ),
              ),
            ),
            body:
                isMobile
                    ? TabBarView(
                      controller: _tabController,
                      children: [routeContent],
                    )
                    : Row(
                      children: [
                        Container(
                          width: 240,
                          color: _adminBlue,
                          child: _buildSidebar(currentRoute, _teamRole),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [routeContent],
                          ),
                        ),
                      ],
                    ),
          ),
        );
      },
    );
  }

  // ---------------- SIDEBAR ----------------

  Widget _buildSidebar(String currentRoute, String teamRole) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 40),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'EduPro',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 253, 253),
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(height: 30),
      _sidebarItem(Icons.dashboard, 'Panel principal', '/panel', currentRoute),
      if (EquipoEduProPermissions.canViewSchools(teamRole))
        _sidebarItem(Icons.school, 'Colegios', '/colegios', currentRoute),
      if (EquipoEduProPermissions.canViewInsights(teamRole))
        _sidebarItem(
          Icons.insights_rounded,
          'Analisis',
          '/analisis-general',
          currentRoute,
        ),
      if (EquipoEduProPermissions.canViewInsights(teamRole))
        _sidebarItem(
          Icons.public_rounded,
          'Red Escolar',
          '/red-escolar',
          currentRoute,
        ),
      if (EquipoEduProPermissions.canViewBilling(teamRole))
        _sidebarItem(
          Icons.receipt_long,
          'Facturacion',
          '/facturacion',
          currentRoute,
        ),
      if (EquipoEduProPermissions.canViewSensitiveConfig(teamRole))
        _sidebarItem(
          Icons.settings,
          'Configuracion',
          '/configuracion',
          currentRoute,
        ),
      const Divider(
        color: Colors.white24,
        height: 28,
        indent: 16,
        endIndent: 16,
      ),
      ListTile(
        leading: const Icon(Icons.logout_rounded, color: Colors.white),
        title: const Text(
          'Cerrar sesion',
          style: TextStyle(color: Colors.white),
        ),
        onTap: _confirmSignOut,
      ),
    ],
  );

  ListTile _sidebarItem(
    IconData icon,
    String label,
    String route,
    String currentRoute,
  ) => ListTile(
    leading: Icon(
      icon,
      color: route == currentRoute ? Colors.amber : Colors.white,
    ),
    title: Text(
      label,
      style: TextStyle(
        color: route == currentRoute ? Colors.amber : Colors.white,
        fontWeight: route == currentRoute ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    selected: route == currentRoute,
    selectedTileColor: const Color(0xFF243391),
    onTap:
        route == currentRoute
            ? null
            : () async {
              final nav = Navigator.of(context);
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                nav.pop();
                await Future<void>.delayed(const Duration(milliseconds: 70));
                if (!mounted) return;
              }
              Navigator.pushReplacementNamed(context, route);
            },
  );

  Widget _routeContent(
    BuildContext context,
    String currentRoute,
    String teamRole,
  ) {
    switch (currentRoute) {
      case '/analisis-general':
        return _buildAnalisisView(context, teamRole);
      case '/colegios':
      case '/panel':
      default:
        return _buildColegiosView(context, teamRole);
    }
  }

  String _routeTabLabel(String currentRoute) {
    switch (currentRoute) {
      case '/analisis-general':
        return 'Analisis';
      case '/colegios':
        return 'Colegios';
      case '/panel':
      default:
        return 'Panel principal';
    }
  }

  IconData _routeTabIcon(String currentRoute) {
    switch (currentRoute) {
      case '/analisis-general':
        return Icons.insights_rounded;
      case '/colegios':
        return Icons.school;
      case '/panel':
      default:
        return Icons.dashboard;
    }
  }

  // ---------------- VISTA COLEGIOS ----------------

  Widget _buildColegiosView(BuildContext context, String teamRole) {
    return AnimatedBuilder(
      animation: _catalog,
      builder: (ctx, _) {
        final schools = _catalog.records.map(_schoolRecordFromDoc).toList();

        final lista = schools;

        if (lista.isNotEmpty &&
            (_selectedSchoolId == null ||
                !lista.any((s) => s.escuela.id == _selectedSchoolId))) {
          _selectedSchoolId = lista.first.escuela.id;
        }

        _SchoolMasterRecord? selected;
        for (final item in lista) {
          if (item.escuela.id == _selectedSchoolId) {
            selected = item;
            break;
          }
        }
        final activeCount = _catalog.metrics?.active ?? '…';
        final suspendedCount = _catalog.metrics?.suspended ?? '…';
        final draftCount = _catalog.metrics?.draft ?? '…';

        final selectedSchool = selected;
        return SchoolMasterDetailLayout(
          key: const ValueKey('schools-workspace'),
          selectedSchoolId: selectedSchool?.escuela.id,
          headerBuilder:
              (context, width) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SchoolCatalogControls(controller: _catalog),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      if (EquipoEduProPermissions.canCreateSchools(teamRole))
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_business),
                          label: const Text('Nueva escuela'),
                          onPressed: _showCreateSchoolDialog,
                        ),
                      if (EquipoEduProPermissions.canViewSensitiveConfig(
                        teamRole,
                      ))
                        OutlinedButton.icon(
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Editar ayuda y legal'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => const AppInfoAdminEditorScreen(),
                              ),
                            );
                          },
                        ),
                      _summaryStatChip(
                        'Total de escuelas',
                        '${_catalog.metrics?.total ?? '…'}',
                        _adminBlue,
                      ),
                      _summaryStatChip('Activas', '$activeCount', Colors.green),
                      _summaryStatChip(
                        'Suspendidas',
                        '$suspendedCount',
                        Colors.orange,
                      ),
                      _summaryStatChip(
                        'Borrador',
                        '$draftCount',
                        Colors.blueGrey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Indicadores globales de todos los colegios; el listado muestra esta página.',
                  ),
                ],
              ),
          listBuilder:
              (context, openDetail) => SchoolCatalogStatus(
                controller: _catalog,
                child:
                    lista.isEmpty
                        ? Center(
                          child: Text(
                            (_catalog.metrics?.total ?? 0) == 0
                                ? 'No hay escuelas registradas'
                                : 'No hay escuelas que coincidan con tu búsqueda.',
                          ),
                        )
                        : _buildSchoolsMasterList(
                          lista,
                          onSchoolSelected: openDetail,
                        ),
              ),

          detailBuilder:
              (context) =>
                  selectedSchool == null
                      ? const Center(
                        child: Text(
                          'Selecciona una escuela para ver su detalle.',
                        ),
                      )
                      : _buildSchoolDetailPanel(selectedSchool, teamRole),
        );
      },
    );
  }

  Widget _buildAnalisisView(BuildContext context, String teamRole) {
    return AnimatedBuilder(
      animation: _catalog,
      builder: (ctx, _) {
        final schools = _catalog.records.map(_schoolRecordFromDoc).toList();

        final lista = schools;

        if (lista.isNotEmpty &&
            (_selectedSchoolId == null ||
                !lista.any((s) => s.escuela.id == _selectedSchoolId))) {
          _selectedSchoolId = lista.first.escuela.id;
        }

        _SchoolMasterRecord? selected;
        for (final item in lista) {
          if (item.escuela.id == _selectedSchoolId) {
            selected = item;
            break;
          }
        }

        final selectedSchool = selected;
        return SchoolMasterDetailLayout(
          key: const ValueKey('analysis-workspace'),
          selectedSchoolId: selectedSchool?.escuela.id,
          headerBuilder:
              (context, width) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SchoolCatalogControls(controller: _catalog),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _summaryStatChip(
                        'Total de escuelas',
                        '${_catalog.metrics?.total ?? '…'}',
                        _adminBlue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Indicadores globales de todos los colegios; el listado muestra esta página.',
                  ),
                ],
              ),
          listBuilder:
              (context, openDetail) => SchoolCatalogStatus(
                controller: _catalog,
                child:
                    lista.isEmpty
                        ? Center(
                          child: Text(
                            (_catalog.metrics?.total ?? 0) == 0
                                ? 'No hay escuelas disponibles para analizar'
                                : 'No hay escuelas que coincidan con tu búsqueda.',
                          ),
                        )
                        : _buildSchoolsMasterList(
                          lista,
                          onSchoolSelected: openDetail,
                        ),
              ),

          detailBuilder:
              (context) =>
                  selectedSchool == null
                      ? const Center(
                        child: Text(
                          'Selecciona una escuela para ver su detalle.',
                        ),
                      )
                      : ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child:
                            teamRole != EquipoEduProRoles.superAdmin
                                ? _buildLimitedSchoolDetail(selectedSchool)
                                : AReporteYAnalisis(
                                  key: ValueKey(selectedSchool.escuela.id),
                                  escuela: selectedSchool.escuela,
                                  embedded: true,
                                ),
                      ),
        );
      },
    );
  }

  Future<List<_SchoolAccessIpEntry>> _fetchSchoolAccessIps({
    required String schoolId,
    required String audience,
  }) async {
    final callable = _fn.httpsCallable('listSchoolAccessIps');
    final resp = await callable.call(<String, dynamic>{
      'schoolId': schoolId,
      'audience': audience,
      'limit': 150,
    });

    final raw = resp.data;
    if (raw is! Map) return const [];
    final items = raw['items'];
    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map((item) => _SchoolAccessIpEntry.fromMap(item))
        .toList();
  }

  Future<void> _unlockSchoolAccessIp({
    required String schoolId,
    required String audience,
    required String ipHash,
  }) async {
    final callable = _fn.httpsCallable('unlockSchoolAccessIp');
    await callable.call(<String, dynamic>{
      'schoolId': schoolId,
      'audience': audience,
      'ipHash': ipHash,
    });
  }

  String _accessAudienceLabel(String audience) {
    switch (audience) {
      case 'admin_escolar':
        return 'Admin escolar';
      case 'docentes':
        return 'Docentes';
      case 'alumnos':
        return 'Alumnos';
      default:
        return audience;
    }
  }

  String _fmtDateTimeMs(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $hh:$mm';
  }

  Future<void> _showSchoolAccessIpsDialog(_SchoolMasterRecord school) async {
    var audience = 'admin_escolar';
    var loading = true;
    String? error;
    var items = <_SchoolAccessIpEntry>[];
    var initialized = false;

    Future<void> load(StateSetter setDialogState) async {
      setDialogState(() {
        loading = true;
        error = null;
      });
      try {
        final result = await _fetchSchoolAccessIps(
          schoolId: school.escuela.id,
          audience: audience,
        );
        setDialogState(() {
          items = result;
        });
      } on FirebaseFunctionsException catch (e) {
        setDialogState(() {
          error = e.message ?? e.code;
        });
      } catch (e) {
        setDialogState(() {
          error = '$e';
        });
      } finally {
        setDialogState(() => loading = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              if (!initialized) {
                initialized = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  load(setDialogState);
                });
              }

              return Dialog(
                insetPadding: const EdgeInsets.all(24),
                child: Container(
                  width: 980,
                  constraints: const BoxConstraints(maxHeight: 720),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'IPs activas - ${school.officialName.isEmpty ? school.escuela.nombre : school.officialName}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Filtra por perfil para revisar IPs, saber si están bloqueadas y desbloquear cuando haga falta.',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Actualizar',
                            onPressed:
                                loading ? null : () => load(setDialogState),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in const [
                            'admin_escolar',
                            'docentes',
                            'alumnos',
                          ])
                            ChoiceChip(
                              label: Text(_accessAudienceLabel(option)),
                              selected: audience == option,
                              onSelected: (selected) {
                                if (!selected) return;
                                setDialogState(() => audience = option);
                                load(setDialogState);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child:
                            loading
                                ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                                : error != null
                                ? Center(
                                  child: Text(
                                    'No se pudo cargar la lista: $error',
                                  ),
                                )
                                : items.isEmpty
                                ? Center(
                                  child: Text(
                                    'Aún no hay IPs registradas para ${_accessAudienceLabel(audience)} en este colegio.',
                                  ),
                                )
                                : ListView.separated(
                                  itemCount: items.length,
                                  separatorBuilder:
                                      (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final blockedColor =
                                        item.blocked
                                            ? Colors.red
                                            : Colors.green;
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    SelectableText(
                                                      item.ipSample.isEmpty
                                                          ? item.ipHash
                                                          : item.ipSample,
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Perfil: ${_accessAudienceLabel(item.audience)}',
                                                      style: TextStyle(
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: blockedColor
                                                      .withOpacity(0.10),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: blockedColor
                                                        .withOpacity(0.25),
                                                  ),
                                                ),
                                                child: Text(
                                                  item.blocked
                                                      ? 'Bloqueada'
                                                      : 'Activa',
                                                  style: TextStyle(
                                                    color: blockedColor,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 14,
                                            runSpacing: 10,
                                            children: [
                                              _miniPill(
                                                'Última actividad: ${_fmtDateTimeMs(item.updatedAtMs)}',
                                                Colors.blueGrey,
                                              ),
                                              _miniPill(
                                                'Último éxito: ${_fmtDateTimeMs(item.lastSuccessAtMs)}',
                                                Colors.green,
                                              ),
                                              _miniPill(
                                                'Último fallo: ${_fmtDateTimeMs(item.lastFailureAtMs)}',
                                                Colors.orange,
                                              ),
                                              _miniPill(
                                                'Fallos: ${item.totalFailures}',
                                                Colors.deepOrange,
                                              ),
                                              _miniPill(
                                                'Éxitos: ${item.totalSuccesses}',
                                                Colors.green,
                                              ),
                                              if (item.lockUntilMs > 0)
                                                _miniPill(
                                                  'Bloqueo hasta: ${_fmtDateTimeMs(item.lockUntilMs)}',
                                                  Colors.red,
                                                ),
                                              if (item.audience ==
                                                  'admin_escolar')
                                                _miniPill(
                                                  'Escalera: etapa ${item.autoStage + 1}',
                                                  Colors.indigo,
                                                ),
                                            ],
                                          ),
                                          if (item.blockedReason
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              'Motivo: ${item.blockedReason}',
                                              style: TextStyle(
                                                color: Colors.grey.shade800,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                          if (item.blocked) ...[
                                            const SizedBox(height: 14),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: ElevatedButton.icon(
                                                onPressed: () async {
                                                  await _unlockSchoolAccessIp(
                                                    schoolId: school.escuela.id,
                                                    audience: item.audience,
                                                    ipHash: item.ipHash,
                                                  );
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'IP desbloqueada en ${_accessAudienceLabel(item.audience)}.',
                                                      ),
                                                    ),
                                                  );
                                                  await load(setDialogState);
                                                },
                                                icon: const Icon(
                                                  Icons.lock_open_rounded,
                                                ),
                                                label: const Text(
                                                  'Desbloquear',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cerrar'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _showEditSchoolLimitsDialog(_SchoolMasterRecord school) async {
    if (!EquipoEduProPermissions.canChangeSchoolPlansAndLimits(_teamRole)) {
      _mostrarError(
        'Solo el superadministrador puede cambiar planes y límites.',
      );
      return;
    }
    ModalRoute<bool>? dialogRoute;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogRoute = ModalRoute.of<bool>(dialogContext);
        return SchoolPlanEditDialog(
          schoolName: school.officialName,
          initialValues: SchoolPlanValues(
            school.planTier,
            school.adminsLimit,
            school.teachersLimit,
            school.studentsLimit,
          ),
          onSave: (values, reason) async {
            if (!await TeamActionVerification.confirm(dialogContext) ||
                !mounted ||
                !dialogContext.mounted)
              return false;
            final response =
                await TeamSchoolAccessService.call('updateSchoolPlanLimits', {
                  'schoolId': school.escuela.id,
                  'planTier': values.planTier,
                  'adminsLimit': values.adminsLimit,
                  'teachersLimit': values.teachersLimit,
                  'studentsLimit': values.studentsLimit,
                  'reason': reason,
                });
            if (response['success'] != true) {
              throw StateError('El servidor no confirmó el cambio.');
            }
            TeamSchoolAccessService.refresh();
            return true;
          },
          errorMessage: _schoolPlanChangeErrorMessage,
        );
      },
    );
    await dialogRoute?.completed;
    if (saved != true || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Plan y límites actualizados para ' + school.officialName + '.',
        ),
      ),
    );
  }

  String _schoolPlanChangeErrorMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'No se autorizó el cambio. Comprueba tus permisos de superadministrador y la verificación en dos pasos.';
        case 'unauthenticated':
          return 'Confirma nuevamente tu identidad para guardar. Tus cambios siguen aquí.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'No se pudo confirmar el guardado. Comprueba la conexión y el plan actual antes de reintentar.';
        case 'not-found':
          return 'El colegio ya no existe. Cierra el editor y actualiza la lista.';
        case 'invalid-argument':
          return 'Revisa el plan, los límites y la justificación (de 10 a 500 caracteres).';
        case 'failed-precondition':
          return 'No se completó la verificación de seguridad. Tus cambios siguen aquí.';
      }
    }
    return 'No se pudo confirmar el cambio de plan. Tus datos siguen aquí; revisa el plan actual antes de reintentar.';
  }

  Widget _summaryStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolsMasterList(
    List<_SchoolMasterRecord> schools, {
    VoidCallback? onSchoolSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        key: PageStorageKey('school-list-${widget.currentRoute}'),
        padding: const EdgeInsets.all(14),
        itemCount: schools.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final s = schools[index];
          final selected = s.escuela.id == _selectedSchoolId;
          final color = _statusColor(s.status);
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() => _selectedSchoolId = s.escuela.id);
              onSchoolSelected?.call();
            },
            onDoubleTap: () async {
              setState(() => _selectedSchoolId = s.escuela.id);
              await _showSchoolAccessIpsDialog(s);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? _adminBlueSoft : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      selected
                          ? _adminBlue.withOpacity(0.35)
                          : Colors.grey.shade200,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(Icons.school_rounded, color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.officialName.isEmpty
                                  ? s.escuela.nombre
                                  : s.officialName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s.institutionCode} • ${s.planTier.toUpperCase()}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _miniPill(s.status, color),
                      _miniPill(s.schoolType, Colors.deepPurple),
                      if (s.timezone.isNotEmpty)
                        _miniPill(s.timezone, Colors.teal),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.contactEmail.isNotEmpty
                        ? s.contactEmail
                        : (s.contactPhone.isNotEmpty
                            ? s.contactPhone
                            : 'Sin contacto principal'),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSchoolDetailPanel(_SchoolMasterRecord school, String teamRole) {
    if (teamRole != EquipoEduProRoles.superAdmin) {
      return _buildLimitedSchoolDetail(school);
    }
    final cacheKey =
        (_auth.currentUser?.uid ?? '') +
        ':' +
        teamRole +
        ':' +
        school.escuela.id;
    return SchoolSummaryLoader(
      key: ValueKey(cacheKey),
      cacheKey: cacheKey,
      cache: _summaryCache,
      load: () => _loadSchoolSummary(school.escuela.id),
      builder: (context, snap) {
        final ops =
            snap.hasData
                ? _SchoolOperationalSnapshot.fromMap(snap.data!)
                : null;
        final missing =
            ops != null
                ? 'Pendiente de cálculo'
                : snap.hasError
                ? 'No disponible'
                : 'Cargando…';
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: _statusColor(
                            school.status,
                          ).withOpacity(0.12),
                          child: Icon(
                            Icons.apartment_rounded,
                            color: _statusColor(school.status),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                school.officialName.isEmpty
                                    ? school.escuela.nombre
                                    : school.officialName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 28,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _miniPill(
                                    'Estado: ${school.status}',
                                    _statusColor(school.status),
                                  ),
                                  _miniPill(
                                    'Plan: ${school.planTier}',
                                    _adminBlue,
                                  ),
                                  _miniPill(
                                    'Renueva: ${_fmtDate(school.billingDates.renewalAt)}',
                                    Colors.indigo,
                                  ),
                                  _miniPill(
                                    'Limites: A${school.adminsLimit} • D${school.teachersLimit} • Al${school.studentsLimit}',
                                    Colors.orange,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _summaryStatChip(
                          'Docentes',
                          '${ops?.totalTeachers ?? missing}',
                          Colors.green,
                        ),
                        _summaryStatChip(
                          'Alumnos',
                          '${ops?.totalStudents ?? missing}',
                          Colors.orange,
                        ),
                        _summaryStatChip(
                          'Usuarios activos',
                          '${ops?.activeUsers ?? missing}',
                          _adminBlue,
                        ),
                        _summaryStatChip(
                          'Planes completos',
                          ops == null
                              ? missing
                              : '${ops.completedPlans ?? missing}/${ops.totalPlans}',
                          Colors.deepPurple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final twoCols = c.maxWidth > 1050;
                  final left = [
                    _detailSection('Ficha maestra', [
                      _detailRow('Nombre oficial', school.officialName),
                      _detailRow(
                        'Codigo institucional',
                        school.institutionCode,
                      ),
                      _detailRow('Tipo de centro', school.schoolType),
                      _detailRow('Pais', school.country),
                      _detailRow('Zona horaria', school.timezone),
                      _detailRow(
                        'Direccion',
                        [
                          school.addressLine,
                          school.municipality,
                          school.province,
                        ].where((e) => e.isNotEmpty).join(', '),
                      ),
                      _detailRow('Creada', _fmtDate(school.createdAt)),
                      _detailRow(
                        'Inicio del servicio',
                        _fmtDate(school.startedAt),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _detailSection('Cuenta y ciclo de vida', [
                      _detailRow('Estado actual', school.status),
                      _detailRow('Etapa', school.lifecycleStage),
                      _detailRow(
                        'Plan contratado',
                        '${school.planTier} • ${school.planPrice.toStringAsFixed(0)}',
                      ),
                      _detailRow(
                        'Renovación',
                        _fmtDate(school.billingDates.renewalAt),
                      ),
                      _detailRow(
                        'Limite admin escolar',
                        '${school.adminsLimit}',
                      ),
                      _detailRow('Limite docentes', '${school.teachersLimit}'),
                      _detailRow('Limite alumnos', '${school.studentsLimit}'),
                      _detailRow(
                        'Modulos habilitados',
                        school.modulesEnabled.isEmpty
                            ? 'Sin definir'
                            : school.modulesEnabled.join(', '),
                      ),
                      _detailRow(
                        'Niveles habilitados',
                        school.levelsEnabled.isEmpty
                            ? 'Sin definir'
                            : school.levelsEnabled.join(', '),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _detailSection('Accesos y responsables', [
                      _detailRow(
                        'Admin principal',
                        ops?.administrator.name ?? missing,
                      ),
                      _detailRow(
                        'Correo admin',
                        ops?.administrator.emailLabel ?? missing,
                      ),
                      _detailRow(
                        'Usuarios bloqueados',
                        ops == null
                            ? missing
                            : '${ops.blockedUsers ?? missing}',
                      ),
                      _detailRow(
                        'Ultimo acceso detectado',
                        _fmtDate(ops?.lastAccessAt),
                      ),
                      _detailRow(
                        'Contacto principal',
                        school.contactName.isEmpty
                            ? 'No definido'
                            : school.contactName,
                      ),
                      _detailRow('Correo administrativo', school.contactEmail),
                      _detailRow('Telefono', school.contactPhone),
                    ]),
                  ];

                  final right = [
                    _detailSection('Salud operativa', [
                      _detailRow(
                        'Docentes activos',
                        ops == null
                            ? missing
                            : '${ops.activeTeachers ?? missing}/${ops.totalTeachers}',
                      ),
                      _detailRow(
                        'Docentes pendientes',
                        ops == null
                            ? missing
                            : '${ops.pendingTeachers ?? missing}',
                      ),
                      _detailRow(
                        'Alumnos activos',
                        ops == null
                            ? missing
                            : '${ops.activeStudents ?? missing}/${ops.totalStudents}',
                      ),
                      _detailRow(
                        'Estudiantes sin grado',
                        ops == null
                            ? missing
                            : '${ops.studentWithoutGrade ?? missing}',
                      ),
                      _detailRow(
                        'Materias sin docente',
                        ops == null
                            ? missing
                            : '${ops.subjectsWithoutTeacher ?? missing}',
                      ),
                      _detailRow(
                        'Asignaturas registradas',
                        ops == null ? missing : '${ops.totalSubjects}',
                      ),
                      _detailRow(
                        'Grados registrados',
                        ops == null ? missing : '${ops.totalGrades}',
                      ),
                    ]),
                    const SizedBox(height: 16),
                    if (EquipoEduProPermissions.canViewBilling(teamRole)) ...[
                      _detailSection('Facturacion y soporte', [
                        _detailRow(
                          'Estado del último reporte',
                          ops?.paymentStatus ?? missing,
                        ),
                        _detailRow(
                          'Fecha del último reporte',
                          ops == null ? missing : _fmtDate(ops.lastPaymentAt),
                        ),
                        _detailRow(
                          'Último pago confirmado',
                          _fmtDate(school.billingDates.lastPaidAt),
                        ),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    _detailSection('Acciones rapidas', [
                      if (EquipoEduProPermissions.canUseSchoolQuickActions(
                        teamRole,
                      ))
                        _actionRow(
                          'Abrir administracion escolar',
                          Icons.admin_panel_settings_outlined,
                          () => Navigator.pushNamed(
                            context,
                            '/admincole',
                            arguments: school.escuela,
                          ),
                        ),
                      if (EquipoEduProPermissions.canUseSchoolQuickActions(
                        teamRole,
                      ))
                        _actionRow(
                          'Abrir docentes',
                          Icons.person_outline,
                          () => Navigator.pushNamed(
                            context,
                            '/docentes',
                            arguments: school.escuela,
                          ),
                        ),
                      if (EquipoEduProPermissions.canUseSchoolQuickActions(
                        teamRole,
                      ))
                        _actionRow(
                          'Abrir alumnos',
                          Icons.school_outlined,
                          () => Navigator.pushNamed(
                            context,
                            '/alumnos',
                            arguments: school.escuela,
                          ),
                        ),
                      if (EquipoEduProPermissions.canUseSchoolQuickActions(
                        teamRole,
                      ))
                        _actionRow(
                          'Ver IPs y bloqueos',
                          Icons.shield_outlined,
                          () => _showSchoolAccessIpsDialog(school),
                        ),
                      if (EquipoEduProPermissions.canUseSchoolQuickActions(
                        teamRole,
                      ))
                        _actionRow(
                          'Copiar link admin',
                          Icons.copy,
                          () => copiar(school.escuela.adminLink),
                        ),
                      if (EquipoEduProPermissions.canChangeSchoolPlansAndLimits(
                        teamRole,
                      ))
                        _actionRow(
                          'Editar plan y límites',
                          Icons.tune,
                          () => _showEditSchoolLimitsDialog(school),
                        ),
                    ]),
                  ];

                  if (!twoCols) {
                    return Column(children: [...left, ...right]);
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: left)),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: right)),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLimitedSchoolDetail(_SchoolMasterRecord school) {
    final id = school.escuela.id;
    final cacheKey =
        (_auth.currentUser?.uid ?? '') + ':' + _teamRole + ':' + id;
    return SchoolSummaryLoader(
      key: ValueKey(cacheKey),
      cacheKey: cacheKey,
      cache: _summaryCache,
      load: () => _loadSchoolSummary(id),
      builder:
          (context, snapshot) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                school.officialName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('Código: ${school.institutionCode}'),
              Text('Estado: ${school.status}'),
              Text('Plan: ${school.planTier}'),
              Text(
                [
                  school.addressLine,
                  school.municipality,
                  school.province,
                ].where((part) => part.isNotEmpty).join(', '),
              ),
              const SizedBox(height: 18),
              if (!snapshot.hasData)
                const Text(
                  'Los indicadores se mostrarán aquí cuando termine la consulta.',
                )
              else ...[
                const Text(
                  'Resumen operativo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final field
                    in const {
                      'totalTeachers': 'Docentes',
                      'totalStudents': 'Alumnos',
                      'totalUsers': 'Usuarios',
                      'totalSubjects': 'Asignaturas',
                      'totalGrades': 'Grados',
                      'totalPlans': 'Planificaciones',
                    }.entries)
                  ListTile(
                    dense: true,
                    title: Text(field.value),
                    trailing: Text(
                      '${snapshot.data![field.key] ?? 'Sin dato'}',
                    ),
                  ),
                Text(
                  'Administración: ${SchoolAdministratorDetails.fromMap(snapshot.data!).emailLabel}',
                ),
              ],
            ],
          ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) =>
      SchoolDetailRow(label: label, value: value);

  Widget _actionRow(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: _adminBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- WIDGET ESTADO ----------------

  Widget _stateCell({
    required bool activo,
    required void Function(bool) onChanged,
  }) => Row(
    children: [
      Switch(value: activo, onChanged: onChanged),
      Text(
        activo ? 'Activo' : 'Pausado',
        style: TextStyle(
          color: activo ? Colors.green : Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _SchoolMasterRecord {
  final Escuela escuela;
  final String officialName;
  final String institutionCode;
  final String schoolType;
  final String country;
  final String timezone;
  final String status;
  final String lifecycleStage;
  final String planTier;
  final double planPrice;
  final int maxUsers;
  final int adminsLimit;
  final int teachersLimit;
  final int studentsLimit;
  final String contactName;
  final String contactRole;
  final String contactPhone;
  final String contactEmail;
  final String addressLine;
  final String province;
  final String municipality;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final SchoolBillingDates billingDates;
  final List<String> modulesEnabled;
  final List<String> levelsEnabled;

  const _SchoolMasterRecord({
    required this.escuela,
    required this.officialName,
    required this.institutionCode,
    required this.schoolType,
    required this.country,
    required this.timezone,
    required this.status,
    required this.lifecycleStage,
    required this.planTier,
    required this.planPrice,
    required this.maxUsers,
    required this.adminsLimit,
    required this.teachersLimit,
    required this.studentsLimit,
    required this.contactName,
    required this.contactRole,
    required this.contactPhone,
    required this.contactEmail,
    required this.addressLine,
    required this.province,
    required this.municipality,
    required this.createdAt,
    required this.startedAt,
    required this.billingDates,
    required this.modulesEnabled,
    required this.levelsEnabled,
  });
}

class _SchoolAccessIpEntry {
  final String id;
  final String schoolId;
  final String audience;
  final String ipHash;
  final String ipSample;
  final bool blocked;
  final int lockUntilMs;
  final int updatedAtMs;
  final int lastSuccessAtMs;
  final int lastFailureAtMs;
  final int totalSuccesses;
  final int totalFailures;
  final String blockedReason;
  final int autoStage;

  const _SchoolAccessIpEntry({
    required this.id,
    required this.schoolId,
    required this.audience,
    required this.ipHash,
    required this.ipSample,
    required this.blocked,
    required this.lockUntilMs,
    required this.updatedAtMs,
    required this.lastSuccessAtMs,
    required this.lastFailureAtMs,
    required this.totalSuccesses,
    required this.totalFailures,
    required this.blockedReason,
    required this.autoStage,
  });

  factory _SchoolAccessIpEntry.fromMap(Map<dynamic, dynamic> map) {
    int asInt(dynamic value) => value is num ? value.toInt() : 0;

    return _SchoolAccessIpEntry(
      id: '${map['id'] ?? ''}',
      schoolId: '${map['schoolId'] ?? ''}',
      audience: '${map['audience'] ?? ''}',
      ipHash: '${map['ipHash'] ?? ''}',
      ipSample: '${map['ipSample'] ?? ''}',
      blocked: map['blocked'] == true,
      lockUntilMs: asInt(map['lockUntilMs']),
      updatedAtMs: asInt(map['updatedAtMs']),
      lastSuccessAtMs: asInt(map['lastSuccessAtMs']),
      lastFailureAtMs: asInt(map['lastFailureAtMs']),
      totalSuccesses: asInt(map['totalSuccesses']),
      totalFailures: asInt(map['totalFailures']),
      blockedReason: '${map['blockedReason'] ?? ''}',
      autoStage: asInt(map['autoStage']),
    );
  }
}

class _SchoolOperationalSnapshot {
  final SchoolAdministratorDetails administrator;
  final int totalTeachers;
  final int? activeTeachers;
  final int? pendingTeachers;
  final int totalStudents;
  final int? activeStudents;
  final int totalUsers;
  final int? activeUsers;
  final int? blockedUsers;
  final int totalSubjects;
  final int totalGrades;
  final int? completedPlans;
  final int totalPlans;
  final int? studentWithoutGrade;
  final int? subjectsWithoutTeacher;
  final DateTime? lastAccessAt;
  final String paymentStatus;
  final DateTime? lastPaymentAt;

  factory _SchoolOperationalSnapshot.fromMap(Map<String, dynamic> data) {
    int count(String key) {
      final value = data[key];
      if (value is! num || value < 0 || value != value.toInt()) {
        throw const FormatException('Resumen de indicadores inválido.');
      }
      return value.toInt();
    }

    int? optional(String key) => data[key] == null ? null : count(key);
    DateTime? date(String key) =>
        data[key] is num
            ? DateTime.fromMillisecondsSinceEpoch((data[key] as num).toInt())
            : null;
    return _SchoolOperationalSnapshot(
      totalTeachers: count('totalTeachers'),
      activeTeachers: optional('activeTeachers'),
      pendingTeachers: optional('pendingTeachers'),
      totalStudents: count('totalStudents'),
      activeStudents: optional('activeStudents'),
      totalUsers: count('totalUsers'),
      activeUsers: optional('activeUsers'),
      blockedUsers: optional('blockedUsers'),
      totalSubjects: count('totalSubjects'),
      totalGrades: count('totalGrades'),
      completedPlans: optional('completedPlans'),
      totalPlans: count('totalPlans'),
      studentWithoutGrade: optional('studentWithoutGrade'),
      subjectsWithoutTeacher: optional('subjectsWithoutTeacher'),
      administrator: SchoolAdministratorDetails.fromMap(data),
      lastAccessAt: date('lastAccessAt'),
      paymentStatus: (data['paymentStatus'] ?? 'Sin dato').toString(),
      lastPaymentAt: date('lastPaymentAt'),
    );
  }

  const _SchoolOperationalSnapshot({
    required this.administrator,
    required this.totalTeachers,
    required this.activeTeachers,
    required this.pendingTeachers,
    required this.totalStudents,
    required this.activeStudents,
    required this.totalUsers,
    required this.activeUsers,
    required this.blockedUsers,
    required this.totalSubjects,
    required this.totalGrades,
    required this.completedPlans,
    required this.totalPlans,
    required this.studentWithoutGrade,
    required this.subjectsWithoutTeacher,
    required this.lastAccessAt,
    required this.paymentStatus,
    required this.lastPaymentAt,
  });
}
