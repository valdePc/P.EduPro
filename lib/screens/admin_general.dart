// lib/screens/admin_general.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';

class AdminGeneralScreen extends StatefulWidget {
  const AdminGeneralScreen({Key? key}) : super(key: key);

  @override
  State<AdminGeneralScreen> createState() => _AdminGeneralScreenState();
}

class _AdminGeneralScreenState extends State<AdminGeneralScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String filtroColegio = '';

  // ✅ FIX: prefijo de docs internos que NO deben mostrarse como “colegios”
  static const String _adminPrefix = 'eduproapp_admin_';

  // OJO: esto es solo “doble confirmación” UI. La seguridad real la ponen las Rules.
  final String adminPassword = 'emma';

  // Mejor que por índice (porque cambia con streams)
  final Set<String> _visibleSchoolPasswords = {};

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _genCode() {
    final rnd = Random.secure();
    return List.generate(8, (_) => rnd.nextInt(36).toRadixString(36))
        .join()
        .toUpperCase();
  }

  Future<String?> _solicitarPassword(String titulo) async {
    String input = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Contraseña'),
          onChanged: (v) => input = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, input),
              child: const Text('Confirmar')),
        ],
      ),
    );
  }

  void _mostrarError([String msg = '❌ Contraseña incorrecta']) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado: $texto')),
    );
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
                child: const Text('Cancelar')),
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

  List<String> _defaultGrades() => const [
        '1ro',
        '2do',
        '3ro',
        '4to',
        '5to',
        '6to',
        '1ro de secundaria',
        '2do de secundaria',
        '3ro de secundaria',
        '4to de secundaria',
        '5to de secundaria',
        '6to de secundaria',
      ];

  Future<void> _crearColegioFirestore(String nombre) async {
    final code = _genCode();
    final pwd = _genCode();

    final data = <String, dynamic>{
      'name': nombre,
      'code': code,
      'adminLink': 'https://edupro.app/admin/$code',
      'profLink': 'https://edupro.app/profesores/$code',
      'alumLink': 'https://edupro.app/alumnos/$code',
      'password': pwd, // ⚠️ por ahora (solo superAdmin lo lee). Luego lo hacemos más pro.
      'grades': _defaultGrades(),
      'active': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'createdByUid': _auth.currentUser?.uid,
    };

    await _db.collection('schools').doc(code).set(data);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Contraseña para $nombre: $pwd')),
    );
    Clipboard.setData(ClipboardData(text: pwd));
  }

  Future<void> _toggleColegioActivo(String code, bool activo) async {
    await _db.collection('schools').doc(code).update({
      'active': activo,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> _deleteColegio(String code) async {
    await _db.collection('schools').doc(code).delete();
  }

  Escuela _escuelaFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['createdAt'];
    final fecha = ts is Timestamp ? ts.toDate() : DateTime.now();

    final e = Escuela(
      nombre: (d['name'] ?? '').toString(),
      adminLink:
          (d['adminLink'] ?? 'https://edupro.app/admin/${doc.id}').toString(),
      profLink: (d['profLink'] ?? '').toString(),
      alumLink: (d['alumLink'] ?? '').toString(),
      fecha: fecha,
      password: (d['password'] ?? '').toString(),
      grados: (d['grades'] is List)
          ? (d['grades'] as List).map((x) => x.toString()).toList()
          : <String>[],
    );

    // si tu modelo tiene "activo" como var, lo seteamos
    try {
      e.activo = (d['active'] ?? true) == true;
    } catch (_) {}

    return e;
  }

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    const currentRoute = '/panel';

    // Si no hay auth, tus rules van a denegar TODO.
    if (_auth.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('EduPro')),
        body: const Center(
          child: Text(
            'No hay sesión iniciada.\n\nInicia sesión con tu super admin para usar este panel.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        drawer: isMobile
            ? Drawer(
                backgroundColor: Colors.blue.shade900,
                child: _buildSidebar(currentRoute),
              )
            : null,
        appBar: AppBar(
          backgroundColor: isMobile ? null : Colors.blue.shade900,
          title: const Text('...'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: Container(
              color: isMobile ? null : Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.amber,
                tabs: const [
                  Tab(text: 'Colegios', icon: Icon(Icons.school)),
                ],
              ),
            ),
          ),
        ),
        body: isMobile
            ? TabBarView(
                controller: _tabController,
                children: [
                  _buildColegiosView(context),
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 240,
                    color: Colors.blue.shade900,
                    child: _buildSidebar(currentRoute),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildColegiosView(context),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---------------- SIDEBAR ----------------

  Widget _buildSidebar(String currentRoute) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 40),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'EduPro',
              style: TextStyle(
                  color: Color.fromARGB(255, 255, 253, 253),
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 30),
          _sidebarItem(Icons.dashboard, 'Panel principal', '/panel', currentRoute),
          _sidebarItem(Icons.school, 'Colegios', '/colegios', currentRoute),
          _sidebarItem(Icons.receipt_long, 'Facturación', '/facturacion', currentRoute),
          _sidebarItem(Icons.settings, 'Configuración', '/configuracion', currentRoute),
        ],
      );

  ListTile _sidebarItem(
          IconData icon, String label, String route, String currentRoute) =>
      ListTile(
        leading: Icon(icon,
            color: route == currentRoute ? Colors.amber : Colors.white),
        title: Text(
          label,
          style: TextStyle(
            color: route == currentRoute ? Colors.amber : Colors.white,
            fontWeight:
                route == currentRoute ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: route == currentRoute,
        selectedTileColor: Colors.blue.shade800,
        onTap: route == currentRoute
            ? null
            : () => Navigator.pushReplacementNamed(context, route),
      );

  // ---------------- VISTA COLEGIOS ----------------

  Widget _buildColegiosView(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('schools').snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error leyendo colegios: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // ✅ FIX: aquí está la solución del duplicado en Admin General
        final docs = snap.data!.docs
            .where((d) => !d.id.startsWith(_adminPrefix))
            .toList();

        final escuelas = docs.map(_escuelaFromDoc).toList();

        final lista = escuelas
            .where((c) => c.nombre
                .toLowerCase()
                .contains(filtroColegio.trim().toLowerCase()))
            .toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar colegio...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setState(() => filtroColegio = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_business),
                    label: const Text('Colegio'),
                    onPressed: () => _showAddDialog(
                      title: 'Nuevo colegio',
                      hint: 'Nombre del colegio',
                      onSave: _crearColegioFirestore,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: lista.isEmpty
                    ? const Center(child: Text('No hay colegios registrados'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 18,
                          headingRowColor:
                              MaterialStateProperty.all(Colors.blue.shade50),
                          columns: const [
                            DataColumn(label: Text('Fechas')),
                            DataColumn(label: Text('Colegios')),
                            DataColumn(label: Text('Administración')),
                            DataColumn(label: Text('Docentes')),
                            DataColumn(label: Text('Estudiantes')),
                            DataColumn(label: Text('Contraseñas')),
                            DataColumn(label: Text('Estados')),
                            DataColumn(label: Text('Eliminar')),
                          ],
                          rows: List.generate(lista.length, (i) {
                            final c = lista[i];
                            final code =
                                c.adminLink.split('/').last.toUpperCase();

                            return DataRow(cells: [
                              DataCell(Text(
                                  '${c.fecha.day}/${c.fecha.month}/${c.fecha.year}')),
                              DataCell(Text(c.nombre)),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.admin_panel_settings,
                                      color: Colors.blue),
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/admincole',
                                        arguments: c);
                                  },
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.person_outline,
                                      color: Colors.green),
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/docentes',
                                        arguments: c);
                                  },
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.school,
                                      color: Colors.orange),
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/alumnos',
                                        arguments: c);
                                  },
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    Text(
                                      _visibleSchoolPasswords.contains(code)
                                          ? c.password
                                          : '••••••••',
                                      style: const TextStyle(
                                          fontFamily: 'monospace'),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _visibleSchoolPasswords.contains(code)
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (_visibleSchoolPasswords
                                              .contains(code)) {
                                            _visibleSchoolPasswords.remove(code);
                                          } else {
                                            _visibleSchoolPasswords.add(code);
                                          }
                                        });
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Copiar contraseña',
                                      icon: const Icon(Icons.copy),
                                      onPressed: () => copiar(c.password),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                _stateCell(
                                  activo: c.activo,
                                  onChanged: (v) async {
                                    final pass = await _solicitarPassword(
                                        'Confirmar estado');
                                    if (pass == adminPassword) {
                                      await _toggleColegioActivo(code, v);
                                    } else if (pass != null) {
                                      _mostrarError();
                                    }
                                  },
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.delete_forever,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final pass = await _solicitarPassword(
                                        'Confirmar eliminación');
                                    if (pass == adminPassword) {
                                      await _deleteColegio(code);
                                    } else if (pass != null) {
                                      _mostrarError();
                                    }
                                  },
                                ),
                              ),
                            ]);
                          }),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- WIDGET ESTADO ----------------

  Widget _stateCell({
    required bool activo,
    required void Function(bool) onChanged,
  }) =>
      Row(
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