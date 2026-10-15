import 'package:edupro/widgets/team_access_gate.dart';
import 'package:edupro/screens/team_billing_screen.dart';
// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:edupro/services/app_check_bootstrap.dart';
import 'package:edupro/services/edupro_two_factor_service.dart';

// Import del servicio de  (para inicializar SharedPreferences si es necesario)
import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show sharedSubjectsService;

// Modelos y repositorios
import 'package:edupro/models/escuela.dart';
import 'package:edupro/data/escuela_repository.dart';

// ✅ NUEVO: para resolver el ID real (schoolId) de la escuela de forma consistente
import 'package:edupro/utils/school_utils.dart'
    show
        escuelaFromPublicMeta,
        lookupSchoolPublicMeta,
        normalizeSchoolIdFromEscuela;

// ✅ Login + Panel (super admin)
import 'package:edupro/screens/login_general.dart';
import 'package:edupro/screens/acceso_enlace_screen.dart';
import 'package:edupro/screens/admin_general.dart';
import 'package:edupro/screens/colegios.dart';
import 'package:edupro/screens/red_escolar_screen.dart';
import 'package:edupro/utils/equipo_edupro_access.dart';
import 'package:edupro/docentes/screens/asistencia.dart';
// Pantallas principales
import 'package:edupro/screens/configuracion.dart';
import 'package:edupro/screens/gestiondeacceso.dart';
import 'package:edupro/screens/seguridad.dart';
import 'package:edupro/screens/pagos_facturacion.dart';
import 'package:edupro/screens/coleAdmin.dart';

// Admin escolar
import 'package:edupro/admin_escolar/screens/admin_dashboard.dart' as admin;
import 'package:edupro/admin_escolar/screens/A_gestiondemaestros.dart';
import 'package:edupro/admin_escolar/screens/A_calendarioacademico.dart';

// Alumnos
import 'package:edupro/alumnos/screens/alumnos.dart';

// Docentes
import 'package:edupro/docentes/screens/docentes.dart';
import 'package:edupro/admin_escolar/screens/docentes_placeholder.dart';
import 'package:edupro/docentes/screens/evaluaciones.dart';
import 'package:edupro/docentes/screens/planificaciones.dart';
import 'package:edupro/docentes/screens/tarea.dart';
import 'package:edupro/docentes/screens/estrategias.dart';
import 'package:edupro/docentes/screens/curriculo.dart';
import 'package:edupro/docentes/screens/material_de_apoyo_docente.dart';
import 'package:edupro/docentes/screens/colocar_calificaciones.dart';

import 'package:intl/date_symbol_data_local.dart';

// Auth
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:edupro/alumnos/screens/chat_grado_screen.dart';
import 'package:edupro/docentes/screens/estudiantes.dart' as docente;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  try {
    await AppCheckBootstrap.activateIfConfigured();
  } catch (_) {
    debugPrint('[APP_CHECK] bootstrap_error');
    if (AppCheckBootstrap.strict) rethrow;
  }

  // (Opcional, recomendado si usas intl con fechas)
  try {
    await initializeDateFormatting('es_DO', null);
  } catch (_) {}

  // ✅ Init seguro para SubjectsService (si tiene init(), se ejecuta; si no, no rompe)
  try {
    final dynamic svc = sharedSubjectsService;
    final dynamic maybeInit = svc.init; // tear-off si existe
    if (maybeInit is Future<void> Function()) {
      await maybeInit();
    }
  } catch (e) {}

  runApp(const EduProApp());
}

/// ===============================================
/// Helpers: resolver escuela por ID real o link-code
/// ===============================================

Escuela _findEscuelaBySchoolIdOrThrow(String schoolId) {
  // Usa el "ID real" (normalizado) de la escuela
  return EscuelaRepository.escuelas.firstWhere((e) {
    try {
      return normalizeSchoolIdFromEscuela(e) == schoolId;
    } catch (_) {
      return false;
    }
  }, orElse: () => throw Exception('Escuela no encontrada'));
}

Escuela _findEscuelaByAlumCodeOrSchoolIdOrThrow(String codigoOrSchoolId) {
  // 1) Compatibilidad: primero intenta como lo hacías (alumLink termina con /<codigo>)
  for (final e in EscuelaRepository.escuelas) {
    final link = e.alumLink;
    if (link.endsWith('/$codigoOrSchoolId')) {
      return e;
    }
  }

  // 2) Fallback: si no era link-code, úsalo como schoolId real
  return _findEscuelaBySchoolIdOrThrow(codigoOrSchoolId);
}

class EduProApp extends StatelessWidget {
  const EduProApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduPro Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color.fromARGB(255, 244, 248, 245),
      ),
      // ✅ En vez de home: AdminGeneralScreen() directo,
      // usamos un AuthGate para decidir: Login o Panel.
      home: const _AuthGate(),

      // Rutas estáticas
      routes: {
        // ✅ login super admin
        '/login': (_) => const LoginGeneralScreen(),

        // ✅ panel super admin
        '/panel':
            (_) => const _TeamFeatureGate(
              route: '/panel',
              child: AdminGeneralScreen(
                initialTabIndex: 0,
                currentRoute: '/panel',
              ),
              featureName: 'panel general',
            ),

        '/colegios':
            (_) => const _TeamFeatureGate(
              route: '/colegios',
              child: ColegiosScreen(),
              featureName: 'colegios',
            ),
        '/analisis-general':
            (_) => const _TeamFeatureGate(
              route: '/analisis-general',
              child: AdminGeneralScreen(
                initialTabIndex: 1,
                currentRoute: '/analisis-general',
              ),
              featureName: 'analisis general',
            ),
        '/red-escolar':
            (_) => const _TeamFeatureGate(
              route: '/red-escolar',
              child: const RedEscolarScreen(),
              featureName: 'red escolar',
            ),
        '/facturacion':
            (_) => const _TeamFeatureGate(
              route: '/facturacion',
              child: TeamBillingScreen(),
              featureName: 'facturación',
            ),
        '/configuracion':
            (_) => const _TeamFeatureGate(
              route: '/configuracion',
              child: ConfiguracionScreen(),
              featureName: 'configuración',
            ),
        '/pagos-facturacion':
            (_) => const _TeamFeatureGate(
              route: '/pagos-facturacion',
              child: PagosFacturacionScreen(),
              featureName: 'pagos y facturacion',
            ),
        '/gestion-accesos':
            (_) => const _TeamFeatureGate(
              route: '/gestion-accesos',
              child: GestionDeAccesoScreen(),
              featureName: 'roles y permisos',
            ),
        '/seguridad':
            (_) => const _TeamFeatureGate(
              route: '/seguridad',
              child: SeguridadScreen(),
              featureName: 'seguridad',
            ),
        '/coleAdmin':
            (_) => const _TeamFeatureGate(
              route: '/coleAdmin',
              child: ColeAdminScreen(),
              featureName: 'administracion de cuentas escolares',
            ),
      },

      onGenerateRoute: (RouteSettings settings) {
        final uri = Uri.parse(settings.name ?? '');
        final args = settings.arguments;

        // ==========================================================
        // ✅ NUEVO: Deep links por ID real con prefijo "eduproapp"
        //
        // Soporta:
        //   1) /eduproapp/<schoolId>/<modulo>
        //   2) eduproapp://<schoolId>/<modulo>
        //
        // Módulos soportados aquí:
        //   - alum | alumnos
        //   - docentes | doc
        //   - admin | admincole
        // ==========================================================
        String? deepSchoolId;
        List<String> tail = const [];

        // Caso scheme: eduproapp://<schoolId>/...
        if (uri.scheme.toLowerCase() == 'eduproapp' && uri.host.isNotEmpty) {
          deepSchoolId = uri.host;
          tail = uri.pathSegments;
        }

        // Caso path: /eduproapp/<schoolId>/...
        if (deepSchoolId == null &&
            uri.pathSegments.isNotEmpty &&
            uri.pathSegments.first.toLowerCase() == 'eduproapp' &&
            uri.pathSegments.length >= 2) {
          deepSchoolId = uri.pathSegments[1];
          tail = uri.pathSegments.length > 2 ? uri.pathSegments.sublist(2) : [];
        }

        if (deepSchoolId != null) {
          final modulo = tail.isNotEmpty ? tail.first.toLowerCase() : '';
          return MaterialPageRoute(
            settings: settings,
            builder:
                (_) => FutureBuilder<Escuela?>(
                  future: _fetchEscuelaBySchoolId(deepSchoolId!),
                  builder: (context, schoolSnap) {
                    if (schoolSnap.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final escuela = schoolSnap.data;
                    if (escuela == null) {
                      return const Scaffold(
                        body: Center(child: Text('Escuela no encontrada')),
                      );
                    }
                    switch (modulo) {
                      case 'alum':
                      case 'alumnos':
                        return AlumnosScreen(escuela: escuela);
                      case 'docentes':
                      case 'doc':
                        return DocentesScreen(escuela: escuela);
                      case 'admin':
                      case 'admincole':
                        return admin.AdminDashboard(escuela: escuela);
                      default:
                        return const Scaffold(
                          body: Center(child: Text('Pagina no encontrada')),
                        );
                    }
                  },
                ),
          );
        }

        // Ruta tipo /alum/<código>
        // ✅ Se mantiene, pero ahora acepta:
        //   - el código viejo basado en alumLink
        //   - O el schoolId real (fallback)
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'alum') {
          final codigo = uri.pathSegments[1];
          final escuela = _findEscuelaByAlumCodeOrSchoolIdOrThrow(codigo);
          return MaterialPageRoute(
            builder: (_) => AlumnosScreen(escuela: escuela),
            settings: settings,
          );
        }

        // /docentes con Escuela como argumento
        if (settings.name == '/docentes') {
          if (args is Escuela) {
            return MaterialPageRoute(
              builder: (_) => DocentesScreen(escuela: args),
              settings: settings,
            );
          } else {
            return MaterialPageRoute(
              builder: (_) => const DocentesPlaceholder(),
              settings: settings,
            );
          }
        }

        // Rutas que usan Escuela como argumento
        if (args is Escuela) {
          switch (settings.name) {
            case '/alumnos':
              return MaterialPageRoute(
                builder: (_) => AlumnosScreen(escuela: args),
                settings: settings,
              );
            case '/asistencia':
              return MaterialPageRoute(
                builder: (_) => const AsistenciaScreen(),
                settings: settings,
              );

            case '/admincole':
              return MaterialPageRoute(
                builder: (_) => admin.AdminDashboard(escuela: args),
                settings: settings,
              );

            case '/evaluaciones':
              return MaterialPageRoute(
                builder: (_) => EvaluacionesScreen(escuela: args),
                settings: settings,
              );

            case '/calendario':
              return MaterialPageRoute(
                builder: (_) => ACalendarioAcademico(escuela: args),
                settings: settings,
              );

            case '/planificaciones':
              return MaterialPageRoute(
                builder: (_) => PlanificacionesScreen(escuela: args),
                settings: settings,
              );

            case '/tarea':
              return MaterialPageRoute(
                builder: (_) => TareaScreen(escuela: args),
                settings: settings,
              );

            case '/estrategias':
              return MaterialPageRoute(
                builder: (_) => EstrategiasScreen(escuela: args),
                settings: settings,
              );

            case '/curriculo':
              return MaterialPageRoute(
                builder: (_) => CurriculoScreen(escuela: args),
                settings: settings,
              );

            case '/estudiantes':
              return MaterialPageRoute(
                builder: (_) => docente.DocenteEstudiantesScreen(escuela: args),
                settings: settings,
              );

            case '/chat':
              return MaterialPageRoute(
                builder: (_) => ChatGradoScreen(escuela: args),
                settings: settings,
              );

            case '/planificacionDocente':
              return MaterialPageRoute(
                builder: (_) => MaterialDeApoyoDocenteScreen(escuela: args),
                settings: settings,
              );

            case '/colocarCalificaciones':
              return MaterialPageRoute(
                builder: (_) => ColocarCalificacionesScreen(escuela: args),
                settings: settings,
              );

            case '/admin/gestion-maestros':
              return MaterialPageRoute(
                builder: (_) => AGestionDeMaestros(escuela: args),
                settings: settings,
              );
          }
        }

        // Fallback interno
        return MaterialPageRoute(
          builder:
              (_) => const Scaffold(
                body: Center(child: Text('Página no encontrada')),
              ),
          settings: settings,
        );
      },

      onUnknownRoute:
          (settings) => MaterialPageRoute(
            builder:
                (_) => const Scaffold(
                  body: Center(child: Text('Página no encontrada')),
                ),
            settings: settings,
          ),
    );
  }
}

Future<Escuela?> _fetchEscuelaBySchoolId(String schoolId) async {
  final sid = schoolId.trim();
  if (sid.isEmpty) return null;

  Escuela _placeholder(String id) => Escuela(
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
    final lookup = await lookupSchoolPublicMeta(
      FirebaseFirestore.instance,
      sid,
    );
    if (lookup != null) {
      return escuelaFromPublicMeta(
        schoolId: lookup.schoolId,
        data: lookup.data,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') {
      return _placeholder(sid);
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
      final data = snap.data() ?? <String, dynamic>{};
      return escuelaFromPublicMeta(schoolId: snap.id, data: data);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Si las rules bloquean lectura pre-login, seguimos con placeholder para abrir login por enlace.
        return _placeholder(sid);
      }
      continue;
    } catch (_) {
      continue;
    }
  }

  // Último fallback: continuar con el schoolId del enlace para no bloquear el flujo.
  return _placeholder(sid);
}

class _DeepLinkTarget {
  final String schoolId;
  final String module;
  const _DeepLinkTarget({required this.schoolId, required this.module});
}

_DeepLinkTarget? _extractDeepLinkTarget(Uri uri) {
  List<String> segments = uri.pathSegments;

  // Soporta hash-routing web: http://host/#/eduproapp/<schoolId>/<module>
  if (segments.isEmpty && uri.fragment.isNotEmpty) {
    final frag =
        uri.fragment.startsWith('/') ? uri.fragment.substring(1) : uri.fragment;
    segments = Uri.parse('/$frag').pathSegments;
  }

  // /eduproapp/<schoolId>/<module>
  if (segments.isNotEmpty &&
      segments.first.toLowerCase() == 'eduproapp' &&
      segments.length >= 3) {
    return _DeepLinkTarget(
      schoolId: segments[1],
      module: segments[2].toLowerCase(),
    );
  }

  // eduproapp://<schoolId>/<module>
  if (uri.scheme.toLowerCase() == 'eduproapp' &&
      uri.host.isNotEmpty &&
      uri.pathSegments.isNotEmpty) {
    return _DeepLinkTarget(
      schoolId: uri.host,
      module: uri.pathSegments.first.toLowerCase(),
    );
  }

  return null;
}

/// ✅ Decide si mostrar Login o Panel según la sesión
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fa.User?>(
      stream: fa.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✅ Si llegó por deep link de módulo, abrimos ese módulo directo.
        final deep = _extractDeepLinkTarget(Uri.base);
        if (deep != null) {
          return FutureBuilder<Escuela?>(
            future: _fetchEscuelaBySchoolId(deep.schoolId),
            builder: (context, schoolSnap) {
              if (schoolSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final escuela = schoolSnap.data;
              if (escuela == null) {
                return const Scaffold(
                  body: Center(
                    child: Text(
                      'Escuela no encontrada para el enlace recibido.',
                    ),
                  ),
                );
              }
              switch (deep.module) {
                case 'alum':
                case 'alumnos':
                  return AlumnosScreen(escuela: escuela);
                case 'doc':
                case 'docentes':
                  return DocentesScreen(escuela: escuela);
                case 'admin':
                case 'admincole':
                  return admin.AdminDashboard(escuela: escuela);
                default:
                  return const Scaffold(
                    body: Center(child: Text('Módulo de enlace no válido.')),
                  );
              }
            },
          );
        }

        final user = snap.data;

        // No logueado => Login
        if (user == null) {
          return const AccesoEnlaceScreen();
        }

        return _CheckedTeamAccess(
          allowedBuilder:
              (context, role) =>
                  _TeamSessionGate(child: _TeamHomeSwitch(teamRole: role)),
          deniedBuilder: (context) {
            scheduleDeniedTeamSessionSignOut(
              context,
              access: const AsyncSnapshot.withData(ConnectionState.done, false),
              expectedUid: user.uid,
              currentUid: () => fa.FirebaseAuth.instance.currentUser?.uid,
              signOut: () => fa.FirebaseAuth.instance.signOut(),
            );
            return const AccesoEnlaceScreen();
          },
        );
      },
    );
  }
}

/// Checks the live route and identity when the deferred action runs, so a
/// hidden or obsolete gate cannot sign out a login happening on another route.
@visibleForTesting
void scheduleDeniedTeamSessionSignOut(
  BuildContext context, {
  required AsyncSnapshot<bool> access,
  required String expectedUid,
  required String? Function() currentUid,
  required Future<void> Function() signOut,
}) {
  // An unavailable permission read is not an authoritative access rejection.
  if (access.connectionState != ConnectionState.done ||
      access.hasError ||
      access.data != false) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        currentUid() != expectedUid) {
      return;
    }
    await signOut();
  });
}

/// One bounded access check shared by the home and direct team routes.
class _CheckedTeamAccess extends StatelessWidget {
  const _CheckedTeamAccess({required this.allowedBuilder, this.deniedBuilder});
  final Widget Function(BuildContext, String) allowedBuilder;
  final WidgetBuilder? deniedBuilder;

  @override
  Widget build(BuildContext context) {
    final auth = fa.FirebaseAuth.instance;
    return TeamAccessGate(
      currentSessionId: () => auth.currentUser?.uid,
      sessionChanges: auth.authStateChanges().map((user) => user?.uid),
      loadRole: () async {
        final user = auth.currentUser;
        if (user == null) return EquipoEduProRoles.denied;
        return EquipoEduProAccess.currentTeamRole(user);
      },
      onCheckStarted: () {},
      onExit: () async {
        try {
          await auth.signOut();
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo cerrar sesión. Intenta nuevamente.'),
            ),
          );
        }
      },
      allowedBuilder: allowedBuilder,
      deniedBuilder: deniedBuilder,
    );
  }
}

class _TeamHomeSwitch extends StatelessWidget {
  const _TeamHomeSwitch({required this.teamRole});
  final String teamRole;

  @override
  Widget build(BuildContext context) {
    switch (EquipoEduProRoles.defaultRoute(teamRole)) {
      case '/facturacion':
        return const TeamBillingScreen();
      case '/panel':
        return const AdminGeneralScreen(
          initialTabIndex: 0,
          currentRoute: '/panel',
        );
      default:
        return const AccesoEnlaceScreen();
    }
  }
}

class _TeamFeatureGate extends StatelessWidget {
  final String route;
  final Widget child;
  final String featureName;

  const _TeamFeatureGate({
    required this.route,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    final user = fa.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AccesoEnlaceScreen();
    }

    return _CheckedTeamAccess(
      allowedBuilder: (context, role) {
        if (EquipoEduProPermissions.canAccessRoute(role, route)) {
          return _TeamSessionGate(child: child);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('EduPro')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56),
                    const SizedBox(height: 14),
                    const Text(
                      'Acceso restringido',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu rol actual (${EquipoEduProRoles.label(role)}) no tiene acceso a $featureName.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Rechecks restored and directly opened team sessions with the server before
/// rendering protected screens. Firestore/Storage rules remain authoritative.
class _TeamSessionGate extends StatefulWidget {
  final Widget child;
  const _TeamSessionGate({required this.child});

  @override
  State<_TeamSessionGate> createState() => _TeamSessionGateState();
}

class _TeamSessionGateState extends State<_TeamSessionGate> {
  StreamSubscription<fa.User?>? _authSubscription;
  bool _verified = false;
  bool _denied = false;
  bool _checking = false;
  String? _sessionUid;

  @override
  void initState() {
    super.initState();
    _sessionUid = fa.FirebaseAuth.instance.currentUser?.uid;
    _authSubscription = fa.FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (user?.uid != _sessionUid && mounted) {
        setState(() {
          _verified = false;
          _denied = true;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A login route can cover the home route while Auth emits a new user.
    // Only the visible route may start a challenge dialog.
    if (!_checking &&
        !_verified &&
        !_denied &&
        ModalRoute.of(context)?.isCurrent == true) {
      _checking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifySession());
    }
  }

  Future<void> _verifySession() async {
    if (!mounted) return;
    bool allowed = false;
    try {
      final user = fa.FirebaseAuth.instance.currentUser;
      if (user != null && user.uid == _sessionUid) {
        final denial = await EquipoEduProAccess.validateUser(user);
        if (denial == null && mounted) {
          allowed = await EduProTwoFactorService.ensureVerified(
            context,
            audience: 'admin_general',
          );
        }
      }
    } catch (_) {
      allowed = false;
    }
    if (!mounted) return;
    allowed =
        allowed &&
        _sessionUid != null &&
        fa.FirebaseAuth.instance.currentUser?.uid == _sessionUid;
    setState(() {
      _verified = allowed;
      _denied = !allowed;
    });
    if (!allowed && fa.FirebaseAuth.instance.currentUser?.uid == _sessionUid) {
      await fa.FirebaseAuth.instance.signOut();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_verified) return widget.child;
    if (_denied) return const AccesoEnlaceScreen();
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
