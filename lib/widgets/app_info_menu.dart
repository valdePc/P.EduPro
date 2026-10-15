import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppInfoSection {
  privacy,
  terms,
  support,
  deleteData,
  permissions,
  version,
  faq,
  roleNotices,
}

class _AppInfoMenuEntry {
  final AppInfoSection section;
  final String label;
  final IconData icon;

  const _AppInfoMenuEntry({
    required this.section,
    required this.label,
    required this.icon,
  });
}

const List<_AppInfoMenuEntry> _appInfoMenuEntries = [
  _AppInfoMenuEntry(
    section: AppInfoSection.privacy,
    label: 'Politica de privacidad',
    icon: Icons.privacy_tip_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.terms,
    label: 'Terminos y condiciones',
    icon: Icons.rule_folder_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.support,
    label: 'Soporte y contacto',
    icon: Icons.support_agent_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.deleteData,
    label: 'Eliminar cuenta / datos',
    icon: Icons.delete_forever_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.permissions,
    label: 'Permisos solicitados',
    icon: Icons.admin_panel_settings_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.version,
    label: 'Version y responsable',
    icon: Icons.info_outline,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.faq,
    label: 'Centro de ayuda / FAQ',
    icon: Icons.quiz_outlined,
  ),
  _AppInfoMenuEntry(
    section: AppInfoSection.roleNotices,
    label: 'Avisos especiales por rol',
    icon: Icons.groups_outlined,
  ),
];

Future<void> showAppInfoMenuSheet(
  BuildContext context, {
  String title = 'Ayuda y legal',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ..._appInfoMenuEntries.map(
              (entry) => ListTile(
                leading: Icon(entry.icon),
                title: Text(entry.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppInfoDetailScreen(section: entry.section),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class AppInfoMenuButton extends StatelessWidget {
  final Color iconColor;

  const AppInfoMenuButton({
    super.key,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppInfoSection>(
      tooltip: 'Ayuda y legal',
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (section) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AppInfoDetailScreen(section: section),
          ),
        );
      },
      itemBuilder: (context) => _appInfoMenuEntries
          .map(
            (entry) => PopupMenuItem<AppInfoSection>(
              value: entry.section,
              child: Row(
                children: [
                  Icon(entry.icon, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(entry.label)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class StudentInfoMenuButton extends AppInfoMenuButton {
  const StudentInfoMenuButton({
    super.key,
    super.iconColor,
  });
}

class AppInfoDetailScreen extends StatelessWidget {
  final AppInfoSection section;

  const AppInfoDetailScreen({
    super.key,
    required this.section,
  });

  static const Color _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: _blue,
        title: Text(AppInfoContentRepository.titleFor(section)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: AppInfoContentRepository.load(),
        builder: (context, snap) {
          final content = snap.data ?? AppInfoContentRepository.defaults();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: _buildSectionContent(
              AppInfoContentRepository.sectionData(content, section),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildSectionContent(Map<String, dynamic> data) {
    final intro = (data['intro'] ?? '').toString().trim();
    final items = AppInfoContentRepository.stringList(data['items']);

    switch (section) {
      case AppInfoSection.support:
      case AppInfoSection.version:
        final cards = AppInfoContentRepository.contactRows(data['cards']);
        return [
          if (intro.isNotEmpty) _introCard(intro),
          ...cards.map(
            (row) => _infoTile(
              AppInfoContentRepository.iconForCard(row['icon']),
              row['label'] ?? '',
              row['value'] ?? '',
            ),
          ),
          if (items.isNotEmpty) _note(items.join('\n')),
        ];
      case AppInfoSection.permissions:
        final cards = AppInfoContentRepository.contactRows(data['cards']);
        return [
          if (intro.isNotEmpty) _introCard(intro),
          ...cards.map(
            (row) => _permissionTile(
              row['label'] ?? '',
              row['value'] ?? '',
            ),
          ),
          ...items.map(_bullet),
        ];
      case AppInfoSection.faq:
        final cards = AppInfoContentRepository.contactRows(data['cards']);
        return [
          if (intro.isNotEmpty) _introCard(intro),
          ...cards.map(
            (row) => _faqTile(
              row['label'] ?? '',
              row['value'] ?? '',
            ),
          ),
          ...items.map(_bullet),
        ];
      case AppInfoSection.roleNotices:
        final cards = AppInfoContentRepository.contactRows(data['cards']);
        return [
          if (intro.isNotEmpty) _introCard(intro),
          ...cards.map(
            (row) => _roleNotice(
              row['label'] ?? '',
              row['value'] ?? '',
            ),
          ),
          ...items.map(_bullet),
        ];
      case AppInfoSection.privacy:
      case AppInfoSection.terms:
      case AppInfoSection.deleteData:
        return [
          if (intro.isNotEmpty) _introCard(intro),
          ...items.map(_bullet),
        ];
    }
  }

  Widget _introCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: const TextStyle(height: 1.45)),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8, color: _blue),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: _blue),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }

  Widget _permissionTile(String title, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(height: 1.45)),
          ],
        ),
      ),
    );
  }

  Widget _faqTile(String question, String answer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(answer, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }

  Widget _roleNotice(String role, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _blue,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(height: 1.45)),
    );
  }
}

class AppInfoAdminEditorScreen extends StatefulWidget {
  const AppInfoAdminEditorScreen({super.key});

  @override
  State<AppInfoAdminEditorScreen> createState() => _AppInfoAdminEditorScreenState();
}

class _AppInfoAdminEditorScreenState extends State<AppInfoAdminEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  String _debugStatus = 'Sin intentar guardar todavia.';
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      'privacyIntro': TextEditingController(),
      'privacyItems': TextEditingController(),
      'termsIntro': TextEditingController(),
      'termsItems': TextEditingController(),
      'supportIntro': TextEditingController(),
      'supportCards': TextEditingController(),
      'supportItems': TextEditingController(),
      'deleteIntro': TextEditingController(),
      'deleteItems': TextEditingController(),
      'permissionsIntro': TextEditingController(),
      'permissionsCards': TextEditingController(),
      'versionIntro': TextEditingController(),
      'versionCards': TextEditingController(),
      'faqIntro': TextEditingController(),
      'faqCards': TextEditingController(),
      'roleIntro': TextEditingController(),
      'roleCards': TextEditingController(),
    };
    _load();
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final data = await AppInfoContentRepository.load();
    _controllers['privacyIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.privacy)['intro']?.toString() ?? '';
    _controllers['privacyItems']!.text = AppInfoContentRepository.stringList(
      AppInfoContentRepository.sectionData(data, AppInfoSection.privacy)['items'],
    ).join('\n');
    _controllers['termsIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.terms)['intro']?.toString() ?? '';
    _controllers['termsItems']!.text = AppInfoContentRepository.stringList(
      AppInfoContentRepository.sectionData(data, AppInfoSection.terms)['items'],
    ).join('\n');
    _controllers['supportIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.support)['intro']?.toString() ?? '';
    _controllers['supportCards']!.text = AppInfoContentRepository.encodeCards(
      AppInfoContentRepository.sectionData(data, AppInfoSection.support)['cards'],
    );
    _controllers['supportItems']!.text = AppInfoContentRepository.stringList(
      AppInfoContentRepository.sectionData(data, AppInfoSection.support)['items'],
    ).join('\n');
    _controllers['deleteIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.deleteData)['intro']?.toString() ?? '';
    _controllers['deleteItems']!.text = AppInfoContentRepository.stringList(
      AppInfoContentRepository.sectionData(data, AppInfoSection.deleteData)['items'],
    ).join('\n');
    _controllers['permissionsIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.permissions)['intro']?.toString() ?? '';
    _controllers['permissionsCards']!.text = AppInfoContentRepository.encodeCards(
      AppInfoContentRepository.sectionData(data, AppInfoSection.permissions)['cards'],
    );
    _controllers['versionIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.version)['intro']?.toString() ?? '';
    _controllers['versionCards']!.text = AppInfoContentRepository.encodeCards(
      AppInfoContentRepository.sectionData(data, AppInfoSection.version)['cards'],
    );
    _controllers['faqIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.faq)['intro']?.toString() ?? '';
    _controllers['faqCards']!.text = AppInfoContentRepository.encodeCards(
      AppInfoContentRepository.sectionData(data, AppInfoSection.faq)['cards'],
    );
    _controllers['roleIntro']!.text =
        AppInfoContentRepository.sectionData(data, AppInfoSection.roleNotices)['intro']?.toString() ?? '';
    _controllers['roleCards']!.text = AppInfoContentRepository.encodeCards(
      AppInfoContentRepository.sectionData(data, AppInfoSection.roleNotices)['cards'],
    );
    await _refreshDebugStatus();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _refreshDebugStatus() async {
    if (!kDebugMode) return;
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid ?? 'sin uid';
    final email = authUser?.email ?? 'sin email';

    String source = 'ninguno';
    Map<String, dynamic>? userData;

    try {
      final usersDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (usersDoc.exists) {
        source = 'users';
        userData = usersDoc.data();
      } else {
        final usersCapsDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
        if (usersCapsDoc.exists) {
          source = 'Users';
          userData = usersCapsDoc.data();
        }
      }
    } catch (e) {
      source = 'error leyendo users';
      debugPrint('[help_center] Error leyendo perfil actual: $e');
    }

    final role = (userData?['role'] ?? '').toString();
    final enabled = userData?['enabled'];
    final teamRole = (userData?['teamRole'] ?? '').toString();

    final text =
        'uid: $uid\nemail: $email\nsource: $source\nrole: $role\nenabled: $enabled\nteamRole: $teamRole';

    if (!mounted) return;
    setState(() => _debugStatus = text);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _refreshDebugStatus();

      final payload = {
        'privacy': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.privacy),
          'intro': _controllers['privacyIntro']!.text.trim(),
          'items': AppInfoContentRepository.lines(_controllers['privacyItems']!.text),
        },
        'terms': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.terms),
          'intro': _controllers['termsIntro']!.text.trim(),
          'items': AppInfoContentRepository.lines(_controllers['termsItems']!.text),
        },
        'support': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.support),
          'intro': _controllers['supportIntro']!.text.trim(),
          'cards': AppInfoContentRepository.decodeCards(_controllers['supportCards']!.text),
          'items': AppInfoContentRepository.lines(_controllers['supportItems']!.text),
        },
        'deleteData': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.deleteData),
          'intro': _controllers['deleteIntro']!.text.trim(),
          'items': AppInfoContentRepository.lines(_controllers['deleteItems']!.text),
        },
        'permissions': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.permissions),
          'intro': _controllers['permissionsIntro']!.text.trim(),
          'cards': AppInfoContentRepository.decodeCards(_controllers['permissionsCards']!.text),
        },
        'version': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.version),
          'intro': _controllers['versionIntro']!.text.trim(),
          'cards': AppInfoContentRepository.decodeCards(_controllers['versionCards']!.text),
        },
        'faq': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.faq),
          'intro': _controllers['faqIntro']!.text.trim(),
          'cards': AppInfoContentRepository.decodeCards(_controllers['faqCards']!.text),
        },
        'roleNotices': {
          'title': AppInfoContentRepository.titleFor(AppInfoSection.roleNotices),
          'intro': _controllers['roleIntro']!.text.trim(),
          'cards': AppInfoContentRepository.decodeCards(_controllers['roleCards']!.text),
        },
        'updatedAt': Timestamp.now(),
      };


      await AppInfoContentRepository.save(payload);
      debugPrint('[help_center] Guardado exitoso');
      if (!mounted) return;
      setState(() {
        _debugStatus = 'Guardado OK\n$_debugStatus';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayuda y legal actualizada.')),
      );
    } on FirebaseException catch (e) {
      debugPrint('[help_center] save_error code=${e.code}');
      if (!mounted) return;
      setState(() {
        _debugStatus = 'FirebaseException: ${e.code}\n${e.message ?? ''}\n$_debugStatus';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar en Firebase: ${e.code}',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[help_center] No se pudo guardar.');
      if (kDebugMode) {
        debugPrint('$st');
      }
      if (!mounted) return;
      setState(() {
        _debugStatus = 'Error: $e\n$_debugStatus';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la configuracion: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar ayuda y legal'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? 'Guardando...' : 'Guardar',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: Icon(_saving ? Icons.sync : Icons.save_outlined),
              label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _hintCard(),
                if (kDebugMode) _debugCard(),
                _editorCard('Politica de privacidad', 'privacyIntro', 'privacyItems', 'Puntos (una linea por punto)'),
                _editorCard('Terminos y condiciones', 'termsIntro', 'termsItems', 'Reglas (una linea por punto)'),
                _editorCard('Soporte y contacto', 'supportIntro', 'supportCards', 'Filas tipo "Etiqueta|Valor|icono"'),
                _simpleCard('Notas extra de soporte', 'supportItems', 'Una linea por nota'),
                _editorCard('Eliminar cuenta / datos', 'deleteIntro', 'deleteItems', 'Puntos (una linea por punto)'),
                _editorCard('Permisos solicitados', 'permissionsIntro', 'permissionsCards', 'Filas tipo "Permiso|Descripcion"'),
                _editorCard('Version y responsable', 'versionIntro', 'versionCards', 'Filas tipo "Etiqueta|Valor|icono"'),
                _editorCard('FAQ', 'faqIntro', 'faqCards', 'Filas tipo "Pregunta|Respuesta"'),
                _editorCard('Avisos por rol', 'roleIntro', 'roleCards', 'Filas tipo "Rol|Aviso"'),
              ],
            ),
    );
  }

  Widget _debugCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagnostico de guardado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _debugStatus,
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _refreshDebugStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar diagnostico'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Todo se guarda en app_config/help_center. '
          'Para filas usa una linea por item. Ejemplo: Correo|valdeymse@gmail.com|email',
          style: TextStyle(color: Colors.grey.shade800, height: 1.45),
        ),
      ),
    );
  }

  Widget _editorCard(String title, String introKey, String bodyKey, String bodyLabel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _controllers[introKey],
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Introduccion',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controllers[bodyKey],
              maxLines: 8,
              decoration: InputDecoration(
                labelText: bodyLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleCard(String title, String key, String label) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _controllers[key],
              maxLines: 4,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppInfoContentRepository {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('app_config').doc('help_center');

  static Future<Map<String, dynamic>> load() async {
    try {
      final snap = await _ref.get();
      final data = snap.data();
      if (data == null || data.isEmpty) return defaults();
      return _mergeDefaults(data);
    } catch (_) {
      return defaults();
    }
  }

  static Future<void> save(Map<String, dynamic> data) {
    return _ref.set(data);
  }

  static String titleFor(AppInfoSection section) {
    switch (section) {
      case AppInfoSection.privacy:
        return 'Politica de privacidad';
      case AppInfoSection.terms:
        return 'Terminos y condiciones';
      case AppInfoSection.support:
        return 'Soporte y contacto';
      case AppInfoSection.deleteData:
        return 'Eliminar cuenta o datos';
      case AppInfoSection.permissions:
        return 'Permisos solicitados';
      case AppInfoSection.version:
        return 'Version y responsable';
      case AppInfoSection.faq:
        return 'Centro de ayuda / FAQ';
      case AppInfoSection.roleNotices:
        return 'Avisos por rol';
    }
  }

  static Map<String, dynamic> sectionData(Map<String, dynamic> content, AppInfoSection section) {
    final key = _keyFor(section);
    final raw = content[key];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return defaults()[key] as Map<String, dynamic>;
  }

  static List<String> stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  static List<Map<String, String>> contactRows(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value?.toString() ?? '')))
        .toList();
  }

  static List<String> lines(String raw) {
    return raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static List<Map<String, String>> decodeCards(String raw) {
    return lines(raw)
        .map((line) {
          final parts = line.split('|').map((e) => e.trim()).toList();
          return {
            'label': parts.isNotEmpty ? parts[0] : '',
            'value': parts.length > 1 ? parts[1] : '',
            'icon': parts.length > 2 ? parts[2] : '',
          };
        })
        .where((row) => (row['label'] ?? '').isNotEmpty)
        .toList();
  }

  static String encodeCards(dynamic raw) {
    return contactRows(raw)
        .map((row) {
          final label = row['label'] ?? '';
          final value = row['value'] ?? '';
          final icon = row['icon'] ?? '';
          return icon.isEmpty ? '$label|$value' : '$label|$value|$icon';
        })
        .join('\n');
  }

  static IconData iconForCard(String? key) {
    switch ((key ?? '').trim().toLowerCase()) {
      case 'email':
        return Icons.email_outlined;
      case 'phone':
        return Icons.phone_outlined;
      case 'schedule':
        return Icons.schedule_outlined;
      case 'apps':
        return Icons.apps_outlined;
      case 'verified':
        return Icons.verified_outlined;
      case 'apartment':
        return Icons.apartment_outlined;
      default:
        return Icons.info_outline;
    }
  }

  static Map<String, dynamic> defaults() {
    return {
      'privacy': {
        'title': titleFor(AppInfoSection.privacy),
        'intro':
            'Protegemos la informacion academica y personal del alumno con acceso limitado segun el rol del usuario.',
        'items': [
          'Solo se muestra la informacion necesaria para el seguimiento escolar autorizado.',
          'Los datos se utilizan para funciones academicas, administrativas y de comunicacion escolar.',
          'Se registran accesos o cambios relevantes cuando es necesario para seguridad y seguimiento.',
          'El usuario puede solicitar correccion o eliminacion de datos por los canales oficiales.',
        ],
      },
      'terms': {
        'title': titleFor(AppInfoSection.terms),
        'intro': '',
        'items': [
          'La app debe usarse solo para fines educativos y escolares autorizados.',
          'No se deben compartir cuentas, claves ni informacion privada de otros alumnos.',
          'El contenido ofensivo, falso o fuera del contexto escolar puede generar restricciones.',
          'La institucion puede actualizar reglas de uso cuando sea necesario para seguridad u operacion.',
        ],
      },
      'support': {
        'title': titleFor(AppInfoSection.support),
        'intro': '',
        'cards': [
          {'label': 'Correo', 'value': 'valdeymse@gmail.com', 'icon': 'email'},
          {'label': 'Telefono', 'value': '+49 157 56052305', 'icon': 'phone'},
          {'label': 'Atencion', 'value': 'Consulta disponibilidad por correo o WhatsApp.', 'icon': 'schedule'},
        ],
        'items': [
          'Usa soporte para acceso, errores, dudas de uso o incidencias con tu cuenta.',
        ],
      },
      'deleteData': {
        'title': titleFor(AppInfoSection.deleteData),
        'intro': '',
        'items': [
          'Puedes solicitar eliminacion de cuenta o borrado de datos por correo de soporte.',
          'La solicitud debe incluir identificacion basica, centro educativo y cuenta asociada.',
          'Antes del borrado se puede validar identidad o revisar obligaciones escolares vigentes.',
          'Canal de contacto: valdeymse@gmail.com',
        ],
      },
      'permissions': {
        'title': titleFor(AppInfoSection.permissions),
        'intro': '',
        'cards': [
          {'label': 'Internet', 'value': 'Para iniciar sesion, sincronizar datos y mostrar informacion escolar.'},
          {'label': 'Notificaciones', 'value': 'Para avisos, recordatorios y comunicados importantes.'},
          {'label': 'Camara o galeria', 'value': 'Solo cuando el usuario sube imagenes, evidencias o archivos visuales.'},
          {'label': 'Archivos', 'value': 'Para descargar documentos o adjuntar archivos cuando la funcion lo requiera.'},
        ],
      },
      'version': {
        'title': titleFor(AppInfoSection.version),
        'intro': '',
        'cards': [
          {'label': 'Aplicacion', 'value': 'EduPro', 'icon': 'apps'},
          {'label': 'Version', 'value': '1.0.0+1', 'icon': 'verified'},
          {'label': 'Responsable', 'value': 'Valde Pie Cenpues', 'icon': 'apartment'},
        ],
      },
      'faq': {
        'title': titleFor(AppInfoSection.faq),
        'intro': '',
        'cards': [
          {'label': 'No puedo entrar a mi cuenta', 'value': 'Verifica tu correo, acceso activo y datos de inicio de sesion.'},
          {'label': 'No veo mis datos o documentos', 'value': 'Algunas vistas dependen del rol, permisos y datos cargados por el centro educativo.'},
          {'label': 'No recibo notificaciones', 'value': 'Revisa permisos del dispositivo y configuracion de avisos en la app.'},
          {'label': 'Quiero reportar un error', 'value': 'Comparte una descripcion breve, la pantalla afectada y los pasos para reproducirlo.'},
        ],
      },
      'roleNotices': {
        'title': titleFor(AppInfoSection.roleNotices),
        'intro': '',
        'cards': [
          {'label': 'Alumno', 'value': 'Consulta solo informacion propia y no compartas tus credenciales.'},
          {'label': 'Padre / tutor', 'value': 'El acceso debe enfocarse en el seguimiento del estudiante vinculado.'},
          {'label': 'Docente', 'value': 'La informacion academica debe usarse con confidencialidad y fines pedagogicos.'},
          {'label': 'Administracion', 'value': 'Los accesos y cambios sensibles deben realizarse bajo criterios institucionales.'},
        ],
      },
    };
  }

  static Map<String, dynamic> _mergeDefaults(Map<String, dynamic> remote) {
    final base = defaults();
    for (final entry in remote.entries) {
      base[entry.key] = entry.value;
    }
    return base;
  }

  static String _keyFor(AppInfoSection section) {
    switch (section) {
      case AppInfoSection.privacy:
        return 'privacy';
      case AppInfoSection.terms:
        return 'terms';
      case AppInfoSection.support:
        return 'support';
      case AppInfoSection.deleteData:
        return 'deleteData';
      case AppInfoSection.permissions:
        return 'permissions';
      case AppInfoSection.version:
        return 'version';
      case AppInfoSection.faq:
        return 'faq';
      case AppInfoSection.roleNotices:
        return 'roleNotices';
    }
  }
}
