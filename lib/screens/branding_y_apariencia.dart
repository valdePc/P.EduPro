// lib/screens/branding_y_apariencia.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class BrandingYAparienciaScreen extends StatefulWidget {
  const BrandingYAparienciaScreen({Key? key}) : super(key: key);

  @override
  State<BrandingYAparienciaScreen> createState() => _BrandingYAparienciaScreenState();
}

class _BrandingYAparienciaScreenState extends State<BrandingYAparienciaScreen> {
  static const currentRoute = '/branding';
  static const selectedKey = 'branding';

  String? _logoUrl;
  String? _faviconUrl;
  final _logoController = TextEditingController();
  final _faviconController = TextEditingController();

  Color _primaryColor = Colors.blue;
  Color _secondaryColor = Colors.teal;
  Color _accentColor = Colors.orange;

  String _fontFamily = 'Roboto';
  final _fonts = ['Roboto', 'Open Sans', 'Lato', 'Montserrat'];

  final _palette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  void dispose() {
    _logoController.dispose();
    _faviconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    Widget content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Logo Institucional',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Center(
          child: _logoUrl == null
              ? const Icon(Icons.image, size: 80, color: Colors.grey)
              : Image.network(_logoUrl!, height: 80),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _showUrlDialog(context, 'Logo', _logoController, (url) {
            setState(() => _logoUrl = url);
          }),
          child: const Text('Ingresar URL de Logo'),
        ),

        const Divider(height: 32),

        const Text('Favicon',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Center(
          child: _faviconUrl == null
              ? const Icon(Icons.adb, size: 40, color: Colors.grey)
              : Image.network(_faviconUrl!, height: 40),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _showUrlDialog(context, 'Favicon', _faviconController, (url) {
            setState(() => _faviconUrl = url);
          }),
          child: const Text('Ingresar URL de Favicon'),
        ),

        const Divider(height: 32),

        const Text('Colores de Marca',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildColorPicker('Primario', _primaryColor, (c) => setState(() => _primaryColor = c)),
        const SizedBox(height: 8),
        _buildColorPicker('Secundario', _secondaryColor,
            (c) => setState(() => _secondaryColor = c)),
        const SizedBox(height: 8),
        _buildColorPicker('Acento', _accentColor,
            (c) => setState(() => _accentColor = c)),

        const Divider(height: 32),

        const Text('Tipografía',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _fontFamily,
          items: _fonts
              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
              .toList(),
          onChanged: (v) => setState(() => _fontFamily = v!),
          decoration: const InputDecoration(
              border: OutlineInputBorder(), isDense: true),
        ),

        const Divider(height: 32),

        const Text('Vista Previa',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _secondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_logoUrl != null)
                Image.network(_logoUrl!, height: 40)
              else
                Icon(Icons.image, size: 40, color: _primaryColor),
              const SizedBox(width: 12),
              Text(
                'EduPro',
                style: TextStyle(
                  fontSize: 24,
                  fontFamily: _fontFamily,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        Center(
          child: ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Branding guardado')),
              );
            },
               style: ElevatedButton.styleFrom(
               backgroundColor: _accentColor,
             ),

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
                onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
              ),
              backgroundColor: Colors.blue.shade900,
            )
          : null,
   appBar: isMobile
  ? AppBar(title: const Text('Branding & Apariencia'))
  : PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        color: Colors.blue.shade700,
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
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                Expanded(child: content),
              ],
            ),
    );
  }

  Widget _buildColorPicker(
      String label, Color current, void Function(Color) onSelect) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _showColorDialog(onSelect),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: current,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

void _showUrlDialog(BuildContext context, String title,
    TextEditingController ctl, void Function(String) onSave) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Ingresa URL de $title'),
      content: TextField(
        controller: ctl,
        decoration: const InputDecoration(hintText: 'https://...'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final url = ctl.text.trim();
            if (!url.startsWith('http')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Por favor, ingresa una URL válida')),
              );
              return;
            }
            onSave(url);
            Navigator.pop(context);
          },
          child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showColorDialog(void Function(Color) onSelect) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selecciona un color'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette.map((c) {
              return GestureDetector(
                onTap: () {
                  onSelect(c);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}
