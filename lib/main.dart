import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // <<– ¡no lo olvides!

// Modelos y repositorios
import 'package:edupro/models/escuela.dart';
import 'package:edupro/data/escuela_repository.dart';

// Pantallas principales
import 'package:edupro/screens/admin_general.dart';
import 'package:edupro/screens/colegios.dart';
import 'package:edupro/screens/freelancers.dart';
import 'package:edupro/screens/facturacion.dart';
import 'package:edupro/screens/configuracion.dart';
import 'package:edupro/screens/gestiondeacceso.dart';
import 'package:edupro/screens/preferenciadelsistema.dart';
import 'package:edupro/screens/seguridad.dart';
import 'package:edupro/screens/notificaciones.dart';
import 'package:edupro/screens/pagos_facturacion.dart';
import 'package:edupro/screens/branding_y_apariencia.dart';

// Admin escolar
import 'package:edupro/admin_escolar/screens/admin_dashboard.dart' as admin;

// Alumnos
import 'package:edupro/alumnos/screens/alumnos.dart';

// Docentes
import 'package:edupro/docentes/screens/docentes.dart';
import 'package:edupro/docentes/screens/evaluaciones.dart';
import 'package:edupro/docentes/screens/calendario.dart';
import 'package:edupro/docentes/screens/planificaciones.dart';
import 'package:edupro/docentes/screens/periodos_y_boletin.dart';
import 'package:edupro/docentes/screens/estrategias.dart';
import 'package:edupro/docentes/screens/curriculo.dart';
import 'package:edupro/docentes/screens/estudiantes.dart';
import 'package:edupro/docentes/screens/chat_screen.dart';
import 'package:edupro/docentes/screens/planificacion_docente.dart';
import 'package:edupro/docentes/screens/colocar_calificaciones.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      home: const AdminGeneralScreen(),

      // 2️⃣ Rutas estáticas
      routes: {
        '/panel':           (_) => const AdminGeneralScreen(),
        '/colegios':        (_) => const ColegiosScreen(),
        '/freelancers':     (_) => const FreelancersScreen(),
        '/facturacion':     (_) => const FacturacionScreen(),
        '/configuracion':   (_) => const ConfiguracionScreen(),
        '/pagos-facturacion':(_) => const PagosFacturacionScreen(),
        '/gestion-accesos': (_) => const GestionDeAccesoScreen(),
        '/preferencias-sistema':(_) => const PreferenciaDelSistemaScreen(),
        '/branding':        (_) => const BrandingYAparienciaScreen(),
        '/seguridad':       (_) => const SeguridadScreen(),
        '/notificaciones':  (_) => const NotificacionesScreen(),
      },

      // 3️⃣ Manejo dinámico de rutas con argumentos
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        // Ruta tipo /alum/<código>
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'alum') {
          final codigo = uri.pathSegments[1];
          final escuela = EscuelaRepository.escuelas.firstWhere(
            (e) => e.alumLink.endsWith('/$codigo'),
            orElse: () => throw Exception('Escuela no encontrada'),
          );
          return MaterialPageRoute(
            builder: (_) => AlumnosScreen(escuela: escuela),
            settings: settings,
          );
        }

        // Rutas que reciben un objeto Escuela
        final args = settings.arguments;
        if (args is Escuela) {
          switch (settings.name) {
            case '/alumnos':
              return MaterialPageRoute(
                  builder: (_) => AlumnosScreen(escuela: args));
            case '/docentes':
              return MaterialPageRoute(
                  builder: (_) => DocentesScreen(escuela: args));
            case '/admincole':
              return MaterialPageRoute(
                  builder: (_) => admin.AdminDashboard(escuela: args));
            case '/evaluaciones':
              return MaterialPageRoute(
                  builder: (_) => EvaluacionesScreen(escuela: args));
            case '/calendario':
              return MaterialPageRoute(
                  builder: (_) => CalendarioScreen(escuela: args));
            case '/planificaciones':
              return MaterialPageRoute(
                  builder: (_) => PlanificacionesScreen(escuela: args));
            case '/periodos':
              return MaterialPageRoute(
                  builder: (_) => PeriodosYBoletinScreen(escuela: args));
            case '/estrategias':
              return MaterialPageRoute(
                  builder: (_) => EstrategiasScreen(escuela: args));
            case '/curriculo':
              return MaterialPageRoute(
                  builder: (_) => CurriculoScreen(escuela: args));
            case '/estudiantes':
              return MaterialPageRoute(
                  builder: (_) => EstudiantesScreen(escuela: args));
            case '/chat':
              return MaterialPageRoute(
                  builder: (_) => ChatScreen(escuela: args));
            case '/planificacionDocente':
              return MaterialPageRoute(
                  builder: (_) => PlanificacionDocenteScreen(escuela: args));
            case '/colocarCalificaciones':
              return MaterialPageRoute(
                  builder: (_) => ColocarCalificacionesScreen(escuela: args));
          }
        }

        // 4️⃣ Fallback interno 404
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Página no encontrada')),
          ),
        );
      },

      // 5️⃣ Fallback global 404
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Página no encontrada')),
        ),
      ),
    );
  }
}
