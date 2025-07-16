import 'package:flutter/material.dart';
import '../screens/admin_general.dart';


class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
  case '/admin':
  return MaterialPageRoute(builder: (_) => const AdminGeneralScreen());

      case '/clases':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Clases'));
      case '/tareas':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Tareas'));
      case '/calificaciones':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Calificaciones'));
      case '/asistencia':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Asistencia'));
      case '/mensajes':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Mensajes'));
      case '/configuracion':
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Configuración'));

      default:
        return MaterialPageRoute(builder: (_) => PlaceholderWidget('Ruta no encontrada'));
    }
  }
}

class PlaceholderWidget extends StatelessWidget {
  final String title;
  const PlaceholderWidget(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('Pantalla: $title')),
    );
  }
}
