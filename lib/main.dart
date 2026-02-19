// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Import del servicio de  (para inicializar SharedPreferences si es necesario)
import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show sharedSubjectsService;

// Modelos y repositorios
import 'package:edupro/models/escuela.dart';
import 'package:edupro/data/escuela_repository.dart';

// ✅ Login + Panel (super admin)
import 'package:edupro/screens/login_general.dart';
import 'package:edupro/screens/admin_general.dart';

// Pantallas principales
import 'package:edupro/screens/colegios.dart';
import 'package:edupro/screens/freelancers.dart';
import 'package:edupro/screens/facturacion.dart';
import 'package:edupro/screens/configuracion.dart';
import 'package:edupro/screens/gestiondeacceso.dart' hide User;
import 'package:edupro/screens/preferenciadelsistema.dart';
import 'package:edupro/screens/seguridad.dart';
import 'package:edupro/screens/notificaciones.dart';
import 'package:edupro/screens/pagos_facturacion.dart';
import 'package:edupro/screens/branding_y_apariencia.dart';
import 'package:edupro/screens/freelancer_detail.dart';
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
import 'package:edupro/docentes/screens/periodos_y_boletin.dart';
import 'package:edupro/docentes/screens/estrategias.dart';
import 'package:edupro/docentes/screens/curriculo.dart';
import 'package:edupro/docentes/screens/estudiantes.dart';
import 'package:edupro/docentes/screens/chat_screen.dart';
import 'package:edupro/docentes/screens/planificacion_docente.dart';
import 'package:edupro/docentes/screens/colocar_calificaciones.dart';

import 'package:intl/date_symbol_data_local.dart';

// Auth
import 'package:firebase_auth/firebase_auth.dart' as fa;

import 'package:edupro/docentes/screens/estudiantes.dart' as docente;


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
  } catch (e) {
    debugPrint('SubjectsService init error: $e');
  }

  runApp(const EduProApp());
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
        '/panel': (_) => const AdminGeneralScreen(),

        '/colegios': (_) => const ColegiosScreen(),
        '/freelancers': (_) => const FreelancersScreen(),
        '/facturacion': (_) => const FacturacionScreen(),
        '/configuracion': (_) => const ConfiguracionScreen(),
        '/pagos-facturacion': (_) => const PagosFacturacionScreen(),
        '/gestion-accesos': (_) => const GestionDeAccesoScreen(),
        '/preferencias-sistema': (_) => const PreferenciaDelSistemaScreen(),
        '/branding': (_) => const BrandingYAparienciaScreen(),
        '/seguridad': (_) => const SeguridadScreen(),
        '/notificaciones': (_) => const NotificacionesScreen(),
        '/freelancerDetalle': (_) => const FreelancerDetailScreen(),
        '/coleAdmin': (_) => const ColeAdminScreen(),
      },

      onGenerateRoute: (RouteSettings settings) {
        final uri = Uri.parse(settings.name ?? '');
        final args = settings.arguments;

        // Ruta tipo /alum/<código>
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'alum') {
          final codigo = uri.pathSegments[1];
          final escuela = EscuelaRepository.escuelas.firstWhere(
            (e) => (e.alumLink ?? '').endsWith('/$codigo'),
            orElse: () => throw Exception('Escuela no encontrada'),
          );
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

            case '/periodos':
              return MaterialPageRoute(
                builder: (_) => PeriodosYBoletinScreen(escuela: args),
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
                builder: (_) => ChatScreen(escuela: args),
                settings: settings,
              );

            case '/planificacionDocente':
              return MaterialPageRoute(
                builder: (_) => PlanificacionDocenteScreen(escuela: args),
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
          builder: (_) => const Scaffold(
            body: Center(child: Text('Página no encontrada')),
          ),
          settings: settings,
        );
      },

      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Página no encontrada')),
        ),
        settings: settings,
      ),
    );
  }
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

        final user = snap.data;

        // No logueado => Login
        if (user == null) {
          return const LoginGeneralScreen();
        }

        // Logueado => Panel
        return const AdminGeneralScreen();
      },
    );
  }
}

