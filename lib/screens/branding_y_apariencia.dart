// lib/screens/branding_y_apariencia.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class BrandingYAparienciaScreen extends StatefulWidget {
  const BrandingYAparienciaScreen({Key? key}) : super(key: key);

  @override
  State<BrandingYAparienciaScreen> createState() =>
      _BrandingYAparienciaScreenState();
}

class _BrandingYAparienciaScreenState extends State<BrandingYAparienciaScreen> {
  static const String currentRoute = '/branding';
  static const String selectedKey = 'branding';

  // ✅ Paleta igual a Colegios / Configuración
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  // Persistencia
  static const _prefsKey = 'branding_v1';

  // Valores editables
  String? _logoUrl;
  String? _faviconUrl;
  final _logoController = TextEditingController();
  final _faviconController = TextEditingController();

  Color _primaryColor = const Color(0xFF0B5FFF);
  Color _secondaryColor = const Color(0xFF00BFA6);
  Color _accentColor = const Color(0xFFF39C12);

  String _fontFamily = 'Roboto';
  final _fonts = ['Roboto', 'Open Sans', 'Lato', 'Montserrat', 'Inter'];

  final _palette = [
    const Color(0xFF0B5FFF),
    const Color(0xFF1976D2),
    const Color(0xFF00897B),
    const Color(0xFF4CAF50),
    const Color(0xFFFFA000),
    const Color(0xFFD32F2F),
    const Color(0xFF6A1B9A),
    const Color(0xFF37474F),
  ];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _faviconController.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildTopBar({required bool isMobile}) {
    return AppBar(
      backgroundColor: _kEduProBlue,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: isMobile,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const SizedBox.shrink(),
      actions: const [
        Center(
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Text(
              'Configuración General',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadPrefs() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(raw);
        _logoUrl = data['logoUrl'] as String?;
        _faviconUrl = data['faviconUrl'] as String?;
        _logoController.text = _logoUrl ?? '';
        _faviconController.text = _faviconUrl ?? '';
        _primaryColor = Color(data['primaryColor'] ?? _primaryColor.value);
        _secondaryColor =
            Color(data['secondaryColor'] ?? _secondaryColor.value);
        _accentColor = Color(data['accentColor'] ?? _accentColor.value);
        _fontFamily = data['fontFamily'] ?? _fontFamily;
      }
    } catch (_) {
      // defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final out = {
      'logoUrl': _logoUrl,
      'faviconUrl': _faviconUrl,
      'primaryColor': _primaryColor.value,
      'secondaryColor': _secondaryColor.value,
      'accentColor': _accentColor.value,
      'fontFamily': _fontFamily,
    };
    await prefs.setString(_prefsKey, jsonEncode(out));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Branding guardado')));
    }
  }

  Future<void> _exportConfig() async {
    final map = {
      'logoUrl': _logoUrl,
      'faviconUrl': _faviconUrl,
      'primaryColor': _primaryColor.value,
      'secondaryColor': _secondaryColor.value,
      'accentColor': _accentColor.value,
      'fontFamily': _fontFamily,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración copiada al portapapeles')),
      );
    }
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Portapapeles vacío')));
      }
      return;
    }
    try {
      final Map<String, dynamic> map = jsonDecode(text);
      setState(() {
        _logoUrl = map['logoUrl'] as String?;
        _faviconUrl = map['faviconUrl'] as String?;
        _logoController.text = _logoUrl ?? '';
        _faviconController.text = _faviconUrl ?? '';
        _primaryColor = Color(map['primaryColor'] ?? _primaryColor.value);
        _secondaryColor =
            Color(map['secondaryColor'] ?? _secondaryColor.value);
        _accentColor = Color(map['accentColor'] ?? _accentColor.value);
        _fontFamily = map['fontFamily'] ?? _fontFamily;
      });
      await _savePrefs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('JSON inválido')));
      }
    }
  }

  bool _isValidUrl(String u) =>
      u.startsWith('http://') || u.startsWith('https://');

  void _showUrlDialog(
    BuildContext ctx,
    String title,
    TextEditingController ctl,
    void Function(String) onSave,
  ) {
    showDialog(
      context: ctx,
      builder: (dCtx) {
        return AlertDialog(
          title: Text('Ingresar URL de $title'),
          content: TextField(
            controller: ctl,
            decoration: const InputDecoration(hintText: 'https://...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: () {
                final url = ctl.text.trim();
                if (!_isValidUrl(url)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Por favor, ingresa una URL válida')),
                  );
                  return;
                }
                onSave(url);
                Navigator.pop(dCtx);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
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
            children: _palette
                .map(
                  (c) => GestureDetector(
                    onTap: () {
                      onSelect(c);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          )
        ],
      ),
    );
  }

  Widget _buildColorPicker(
    String label,
    Color current,
    void Function(Color) onSelect,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _showColorDialog(onSelect),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: current,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: _palette
                .map(
                  (c) => GestureDetector(
                    onTap: () => onSelect(c),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        )
      ],
    );
  }

  Widget _buildPreviewCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_logoUrl != null && _logoUrl!.isNotEmpty)
              Image.network(
                _logoUrl!,
                height: 48,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.image_not_supported,
                  size: 48,
                  color: _primaryColor,
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.school, color: _primaryColor),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EduPro',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: _fontFamily,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vista previa de la identidad visual',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: _savePrefs,
              child: const Text('Aplicar marca'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'Branding & Apariencia',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),

        const Text('Logo Institucional',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Center(
          child: (_logoUrl == null || _logoUrl!.isEmpty)
              ? const Icon(Icons.image, size: 84, color: Colors.grey)
              : Image.network(
                  _logoUrl!,
                  height: 84,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.broken_image, size: 84, color: _primaryColor),
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _logoController,
                decoration: const InputDecoration(
                  labelText: 'URL de logo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: () => _showUrlDialog(
                context,
                'Logo',
                _logoController,
                (url) => setState(() => _logoUrl = url),
              ),
              child: const Text('Probar'),
            ),
          ],
        ),

        const SizedBox(height: 20),
        const Text('Favicon',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _faviconController,
                decoration: const InputDecoration(
                  labelText: 'URL de favicon',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: () => _showUrlDialog(
                context,
                'Favicon',
                _faviconController,
                (url) => setState(() => _faviconUrl = url),
              ),
              child: const Text('Probar'),
            ),
          ],
        ),

        const SizedBox(height: 24),
        const Text('Colores de Marca',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildColorPicker('Color primario', _primaryColor,
            (c) => setState(() => _primaryColor = c)),
        const SizedBox(height: 12),
        _buildColorPicker('Color secundario', _secondaryColor,
            (c) => setState(() => _secondaryColor = c)),
        const SizedBox(height: 12),
        _buildColorPicker('Color de acento', _accentColor,
            (c) => setState(() => _accentColor = c)),

        const SizedBox(height: 24),
        const Text('Tipografía',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _fontFamily,
          items: _fonts
              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
              .toList(),
          onChanged: (v) => setState(() => _fontFamily = v ?? _fontFamily),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),

        const SizedBox(height: 24),
        const Text('Vista Previa',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildPreviewCard(),

        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: _savePrefs,
              child: const Text('Guardar cambios'),
            ),
            OutlinedButton(
              onPressed: () async {
                setState(() {
                  _logoUrl = null;
                  _faviconUrl = null;
                  _logoController.clear();
                  _faviconController.clear();
                  _primaryColor = const Color(0xFF0B5FFF);
                  _secondaryColor = const Color(0xFF00BFA6);
                  _accentColor = const Color(0xFFF39C12);
                  _fontFamily = 'Roboto';
                });
                await _savePrefs();
              },
              child: const Text('Restaurar por defecto'),
            ),
            PopupMenuButton<String>(
              onSelected: (t) async {
                if (t == 'export') await _exportConfig();
                if (t == 'import') await _importConfigFromClipboard();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('Exportar configuración')),
                PopupMenuItem(value: 'import', child: Text('Importar desde portapapeles')),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Más'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    void go(String r) => Navigator.pushReplacementNamed(context, r);

    Widget wrappedContent() {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 0,
          vertical: isMobile ? 16 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: _buildFormContent(),
      );
    }

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: isMobile),
      drawer: isMobile
          ? Drawer(
              backgroundColor: _kEduProBlue,
              child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
            )
          : null,
      body: isMobile
          ? Column(
              children: [
                // ✅ Menú de configuración arriba en móvil (con iconos)
                ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                Expanded(child: wrappedContent()),
              ],
            )
          : Row(
              children: [
                // ✅ Sidebar global azul fijo
                Container(
                  width: 260,
                  color: _kEduProBlue,
                  child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
                ),

                // ✅ Borde azul + submenú blanco (como tu captura)
                Container(
                  width: 286, // 6px borde + 280 menu
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: _kEduProBlue, width: 6)),
                  ),
                  child: ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                ),

                const SizedBox(width: 24),

                // ✅ Contenido en card
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: wrappedContent(),
                  ),
                ),
              ],
            ),
    );
  }
}
