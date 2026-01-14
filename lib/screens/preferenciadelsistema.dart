// lib/screens/preferenciadelsistema.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class PreferenciaDelSistemaScreen extends StatefulWidget {
  const PreferenciaDelSistemaScreen({Key? key}) : super(key: key);

  @override
  _PreferenciaDelSistemaScreenState createState() =>
      _PreferenciaDelSistemaScreenState();
}

class _PreferenciaDelSistemaScreenState
    extends State<PreferenciaDelSistemaScreen> {
  static const currentRoute = '/preferencias-sistema';
  static const selectedKey = 'preferencias-sistema';

  // Valores por defecto
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24 horas';
  String _language = 'Español';
  String _themeMode = 'Sistema';

  final TextEditingController _invoiceSubjectController =
      TextEditingController(text: 'Tu factura de EduPro');
  final TextEditingController _invoiceBodyController = TextEditingController(
      text: 'Estimado/a,\nAdjunto tu factura correspondiente...\n');
  final TextEditingController _meetingSubjectController =
      TextEditingController(text: 'Recordatorio: Reunión de Equipo');
  final TextEditingController _meetingBodyController = TextEditingController(
      text: 'Hola equipo,\nNo olvides nuestra reunión de seguimiento.\nSaludos.');
  final TextEditingController _reportSubjectController =
      TextEditingController(text: 'Entrega de Reporte Semanal');
  final TextEditingController _reportBodyController = TextEditingController(
      text: 'Adjunto encontrarás el reporte semanal de avances.\nGracias.');

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _dateFormat = prefs.getString('pref_dateFormat') ?? _dateFormat;
        _timeFormat = prefs.getString('pref_timeFormat') ?? _timeFormat;
        _language = prefs.getString('pref_language') ?? _language;
        _themeMode = prefs.getString('pref_themeMode') ?? _themeMode;

        _invoiceSubjectController.text =
            prefs.getString('pref_invoiceSubject') ?? _invoiceSubjectController.text;
        _invoiceBodyController.text =
            prefs.getString('pref_invoiceBody') ?? _invoiceBodyController.text;
        _meetingSubjectController.text =
            prefs.getString('pref_meetingSubject') ?? _meetingSubjectController.text;
        _meetingBodyController.text =
            prefs.getString('pref_meetingBody') ?? _meetingBodyController.text;
        _reportSubjectController.text =
            prefs.getString('pref_reportSubject') ?? _reportSubjectController.text;
        _reportBodyController.text =
            prefs.getString('pref_reportBody') ?? _reportBodyController.text;

        _loading = false;
      });
    } catch (e) {
      // Si falla, solo continua con los valores por defecto
      setState(() => _loading = false);
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_dateFormat', _dateFormat);
      await prefs.setString('pref_timeFormat', _timeFormat);
      await prefs.setString('pref_language', _language);
      await prefs.setString('pref_themeMode', _themeMode);

      await prefs.setString('pref_invoiceSubject', _invoiceSubjectController.text);
      await prefs.setString('pref_invoiceBody', _invoiceBodyController.text);
      await prefs.setString('pref_meetingSubject', _meetingSubjectController.text);
      await prefs.setString('pref_meetingBody', _meetingBodyController.text);
      await prefs.setString('pref_reportSubject', _reportSubjectController.text);
      await prefs.setString('pref_reportBody', _reportBodyController.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferencias guardadas')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error guardando preferencias')),
      );
    }
  }

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

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final content = ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Preferencias del sistema',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // Formatos básicos
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
        const Divider(height: 36),

        // Plantillas
        const Text('Plantilla: Factura',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _invoiceSubjectController),
        _buildTextArea('Cuerpo', _invoiceBodyController),
        const Divider(height: 36),

        const Text('Plantilla: Reunión de Equipo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _meetingSubjectController),
        _buildTextArea('Cuerpo', _meetingBodyController),
        const Divider(height: 36),

        const Text('Plantilla: Entrega de Reporte Semanal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildTextField('Asunto', _reportSubjectController),
        _buildTextArea('Cuerpo', _reportBodyController),
        const Divider(height: 36),

        // Tema
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

        const SizedBox(height: 18),
        // Acciones
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                // Restaurar valores por defecto en memoria (no borra SharedPreferences)
                setState(() {
                  _dateFormat = 'DD/MM/YYYY';
                  _timeFormat = '24 horas';
                  _language = 'Español';
                  _themeMode = 'Sistema';

                  _invoiceSubjectController.text = 'Tu factura de EduPro';
                  _invoiceBodyController.text = 'Estimado/a,\nAdjunto tu factura correspondiente...\n';
                  _meetingSubjectController.text = 'Recordatorio: Reunión de Equipo';
                  _meetingBodyController.text = 'Hola equipo,\nNo olvides nuestra reunión de seguimiento.\nSaludos.';
                  _reportSubjectController.text = 'Entrega de Reporte Semanal';
                  _reportBodyController.text = 'Adjunto encontrarás el reporte semanal de avances.\nGracias.';
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valores restablecidos (temporales)')));
              },
              child: const Text('Restaurar valores por defecto'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _savePreferences,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text('Guardar cambios'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),
      ],
    );

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: SidebarMenu(
                currentRoute: currentRoute,
                onItemSelected: (route) => Navigator.pushReplacementNamed(context, route),
              ),
              backgroundColor: Colors.blue.shade900,
            )
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('Preferencias del sistema'), backgroundColor: Colors.blue.shade900)
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
                  onItemSelected: (route) => Navigator.pushReplacementNamed(context, route),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                // Sidebar principal
                SizedBox(width: 240, child: SidebarMenu(currentRoute: currentRoute, onItemSelected: (route) => Navigator.pushReplacementNamed(context, route))),
                // Submenu
                ConfigMenu(selectedKey: selectedKey, onItemSelected: (route) => Navigator.pushReplacementNamed(context, route)),
                const SizedBox(width: 24),
                Expanded(child: Card(margin: const EdgeInsets.only(right: 24), child: Padding(padding: const EdgeInsets.all(16), child: content))),
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
          SizedBox(width: 180, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: value,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: ctl,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: ctl,
              maxLines: 5,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}
