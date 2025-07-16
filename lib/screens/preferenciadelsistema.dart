// lib/screens/preferenciadelsistema.dart

import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import 'package:edupro/widgets/config_menu.dart';

class PreferenciaDelSistemaScreen extends StatefulWidget {
  const PreferenciaDelSistemaScreen({Key? key}) : super(key: key);

  @override
  _PreferenciaDelSistemaScreenState createState() =>
      _PreferenciaDelSistemaScreenState();
}

class _PreferenciaDelSistemaScreenState
    extends State<PreferenciaDelSistemaScreen> {
  static const currentRoute = '/preferencias-sistema';
  static const selectedKey = 'sistema';

  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24 horas';
  String _language = 'Español';
  String _themeMode = 'Sistema';

  final _invoiceSubjectController =
      TextEditingController(text: 'Tu factura de EduPro');
  final _invoiceBodyController = TextEditingController(
      text: 'Estimado/a,\nAdjunto tu factura correspondiente...\n');
  final _meetingSubjectController =
      TextEditingController(text: 'Recordatorio: Reunión de Equipo');
  final _meetingBodyController = TextEditingController(
      text: 'Hola equipo,\nNo olvides nuestra reunión de seguimiento.\nSaludos.');
  final _reportSubjectController =
      TextEditingController(text: 'Entrega de Reporte Semanal');
  final _reportBodyController = TextEditingController(
      text: 'Adjunto encontrarás el reporte semanal de avances.\nGracias.');

  @override
  void dispose() {
    _invoiceSubjectController.dispose();
    _invoiceBodyController.dispose();
    _meetingSubjectController.dispose();
    _meetingBodyController.dispose();
    _reportSubjectController.dispose();
    _reportBodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final content = ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildDropdown(
          label: 'Formato de fecha',
          value: _dateFormat,
          items: const ['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'],
          onChanged: (v) => setState(() => _dateFormat = v!),
        ),
        _buildDropdown(
          label: 'Formato de hora',
          value: _timeFormat,
          items: const ['24 horas', '12 horas AM/PM'],
          onChanged: (v) => setState(() => _timeFormat = v!),
        ),
        _buildDropdown(
          label: 'Idioma de la plataforma',
          value: _language,
          items: const ['Español', 'Inglés'],
          onChanged: (v) => setState(() => _language = v!),
        ),
        const Divider(),
        const Text('Plantilla: Factura',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _invoiceSubjectController),
        _buildTextArea('Cuerpo', _invoiceBodyController),
        const Divider(),
        const Text('Plantilla: Reunión de Equipo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _meetingSubjectController),
        _buildTextArea('Cuerpo', _meetingBodyController),
        const Divider(),
        const Text('Plantilla: Entrega de Reporte Semanal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _reportSubjectController),
        _buildTextArea('Cuerpo', _reportBodyController),
        const Divider(),
        const Text('Tema de la aplicación',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        RadioListTile<String>(
          title: const Text('Claro'),
          value: 'Claro',
          groupValue: _themeMode,
          onChanged: (v) => setState(() => _themeMode = v!),
        ),
        RadioListTile<String>(
          title: const Text('Oscuro'),
          value: 'Oscuro',
          groupValue: _themeMode,
          onChanged: (v) => setState(() => _themeMode = v!),
        ),
        RadioListTile<String>(
          title: const Text('Sistema'),
          value: 'Sistema',
          groupValue: _themeMode,
          onChanged: (v) => setState(() => _themeMode = v!),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preferencias guardadas')),
              );
            },
            child: const Text('Guardar cambios'),
          ),
        ),
      ],
    );

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: SidebarMenu(
                currentRoute: currentRoute,
                onItemSelected: (route) =>
                    Navigator.pushReplacementNamed(context, route),
              ),
              backgroundColor: Colors.blue.shade900,
            )
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('Preferencias del sistema'))
          : PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                color: Colors.blue.shade900,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  'Configuración General',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
      body: isMobile
          ? Column(
              children: [
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (route) =>
                      Navigator.pushReplacementNamed(context, route),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) =>
                      Navigator.pushReplacementNamed(context, route),
                ),
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (route) =>
                      Navigator.pushReplacementNamed(context, route),
                ),
                const SizedBox(width: 24),
                Expanded(child: content),
              ],
            ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: value,
              items:
                  items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
              decoration:
                  const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // FIX: use correct enum
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: ctl,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextArea(String label, TextEditingController ctl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // FIXED
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: ctl,
              maxLines: 4,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}
