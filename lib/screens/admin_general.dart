// lib/screens/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/models/freelancer.dart';
import 'package:edupro/data/escuela_repository.dart';


class AdminGeneralScreen extends StatefulWidget {
  const AdminGeneralScreen({Key? key}) : super(key: key);

  @override
  State<AdminGeneralScreen> createState() => _AdminGeneralScreenState();
}

class _AdminGeneralScreenState extends State<AdminGeneralScreen>
    with SingleTickerProviderStateMixin {
  final List<Escuela> escuelas = [];
  final List<Freelancer> freelancers = [];
  String filtroColegio = '';
  String filtroFreelancer = '';
  final String adminPassword = 'emma';
   final Set<int> _visiblePasswordRows = {};
  late final TabController _tabController;
  final Set<int> _visibleFreelancerRows = {}; // controlar visibilidad fila por índice

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _genCode() {
    final rnd = Random();
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, input), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  void _mostrarError() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('❌ Contraseña incorrecta')));
  }


void agregarFreelancer(String nombre) {
  final codeTeacher = _genCode();  // primer código
  final codeStudent = _genCode();  // segundo código
  final pwd = _genCode();          // 🔐 nueva contraseña

  setState(() {
    freelancers.add(Freelancer(
      nombre: nombre,
      teacherLink: 'https://edupro.app/freelancer/maestro/$codeTeacher',
      studentLink: 'https://edupro.app/freelancer/estudiante/$codeStudent',
      fecha: DateTime.now(),
      password: pwd, // ✅ aquí agregas el password
    ));
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Contraseña para $nombre: $pwd')),
  );

  Clipboard.setData(ClipboardData(text: pwd));
}
void agregarColegio(String nombre) {
  final code = _genCode();
  final pwd  = _genCode();

  final nueva = Escuela(
    nombre: nombre,
    adminLink:   'https://edupro.app/admin/$code',
    profLink:    'https://edupro.app/profesores/$code',
    alumLink:    'https://edupro.app/alumnos/$code',
    fecha:       DateTime.now(),
    password:    pwd,
    grados: [
      '1ro','2do','3ro','4to','5to','6to',
      '1ro de secundaria','2do de secundaria','3ro de secundaria',
      '4to de secundaria','5to de secundaria','6to de secundaria',
    ],
  );

  setState(() => escuelas.add(nueva));
  EscuelaRepository.escuelas.add(nueva);

  ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text('Contraseña para $nombre: $pwd')));
  Clipboard.setData(ClipboardData(text: pwd));
}


  void copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copiado: $texto')));
  }

  void _showAddDialog({
    required String title,
    required String hint,
    required void Function(String) onSave,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        String input = '';
        return AlertDialog(
          title: Text(title),
          content: TextField(
            decoration: InputDecoration(labelText: hint),
            onChanged: (v) => input = v,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (input.isNotEmpty) {
                  onSave(input);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }


@override
Widget build(BuildContext context) {
  final isMobile = MediaQuery.of(context).size.width < 800;
  const currentRoute = '/panel';

  return DefaultTabController(
    length: 2,
    child: Scaffold(
      drawer: isMobile
          ? Drawer(
              backgroundColor: Colors.blue.shade900,
              child: _buildSidebar(currentRoute),
            )
          : null,
      appBar: AppBar(
        backgroundColor: isMobile ? null : Colors.blue.shade900,
        title: const Text('...'), // ✅ Texto fijo
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Container(
            color: isMobile ? null : Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              tabs: const [
                Tab(text: 'Colegios', icon: Icon(Icons.school)),
                Tab(text: 'Freelancers', icon: Icon(Icons.person)),
              ],
            ),
          ),
        ),
      ),
      body: isMobile
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildColegiosView(context, isMobile),
                _buildFreelancersView(context, isMobile),
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
                      _buildColegiosView(context, isMobile),
                      _buildFreelancersView(context, isMobile),
                    ],
                  ),
                ),
              ],
            ),
    ),
  );
}

  Widget _buildSidebar(String currentRoute) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 40),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('EduPro',
                style: TextStyle(color: Color.fromARGB(255, 255, 253, 253), fontSize: 26, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 30),
          _sidebarItem(Icons.dashboard, 'Panel principal', '/panel', currentRoute),
          _sidebarItem(Icons.school, 'Colegios', '/colegios', currentRoute),
          _sidebarItem(Icons.person, 'Freelancers', '/freelancers', currentRoute),
          _sidebarItem(Icons.receipt_long, 'Facturación', '/facturacion', currentRoute),
          _sidebarItem(Icons.settings, 'Configuración', '/configuracion', currentRoute),
        ],
      );

  ListTile _sidebarItem(IconData icon, String label, String route, String currentRoute) =>
      ListTile(
        leading: Icon(icon, color: route == currentRoute ? Colors.amber : Colors.white),
        title: Text(label,
            style: TextStyle(
                color: route == currentRoute ? Colors.amber : Colors.white,
                fontWeight: route == currentRoute ? FontWeight.bold : FontWeight.normal)),
        selected: route == currentRoute,
        selectedTileColor: Colors.blue.shade800,
        onTap: route == currentRoute ? null : () => Navigator.pushReplacementNamed(context, route),
      );

 Widget _buildColegiosView(BuildContext context, bool isMobile) {
final List<Escuela> lista = escuelas.where((c) => c.nombre.toLowerCase().contains(filtroColegio.toLowerCase())).toList();


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
             onChanged: (v) => setState(() => filtroColegio = v),

              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business),
              label: const Text('Colegio'),
              onPressed: () => _showAddDialog(
                title: 'Nuevo colegio',
                hint: 'Nombre del colegio',
                onSave: agregarColegio,
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
                    headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                    columns: const [
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Colegio')),
                      DataColumn(label: Text('Admin')),
                      DataColumn(label: Text('Profesores')),
                      DataColumn(label: Text('Estudiantes')),
                      DataColumn(label: Text('Contraseña')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Eliminar')),
                      

                    ],
rows: List.generate(lista.length, (i) {
  final c = lista[i];
  return DataRow(cells: [
       // Fecha
    DataCell(Text('${c.fecha.day}/${c.fecha.month}/${c.fecha.year}')),

    // Colegio
    DataCell(Text(c.nombre)),
 
    // Admin
DataCell(
  IconButton(
    icon: const Icon(Icons.admin_panel_settings, color: Colors.blue),
    onPressed: () async {
      final pass = await _solicitarPassword('Contraseña / Admin');
      if (pass != null && (pass.toLowerCase() == adminPassword || pass == c.password)) {
        Navigator.pushNamed(context, '/admincole', arguments: c);
      } else if (pass != null) {
        _mostrarError();
      }
    },
  ),
),

    // Docentes
   DataCell(
  IconButton(
    icon: const Icon(Icons.person_outline, color: Colors.green),
    onPressed: () async {
      final pass = await _solicitarPassword('Contraseña  / Docentes');
      if (pass != null && (pass.toLowerCase() == adminPassword || pass == c.password)) {
        Navigator.pushNamed(context, '/docentes', arguments: c);
      } else if (pass != null) {
        _mostrarError();
      }
    },
  ),
),

    // Alumnos
DataCell(
  IconButton(
    icon: const Icon(Icons.school, color: Colors.orange),
    onPressed: () async {
      final pass = await _solicitarPassword('Contraseña / Estudiantes');
      if (pass != null && (pass.toLowerCase() == adminPassword || pass == c.password)) {
        Navigator.pushNamed(context, '/alumnos', arguments: c);
      } else if (pass != null) {
        _mostrarError();
      }
    },
  ),
),

   // Contraseña con botón ojo
    DataCell(Row(
      children: [
        Text(
          _visiblePasswordRows.contains(i) ? c.password : '••••••••',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        IconButton(
          icon: Icon(
            _visiblePasswordRows.contains(i)
              ? Icons.visibility_off
              : Icons.visibility,
          ),
          onPressed: () {
            setState(() {
              if (_visiblePasswordRows.contains(i))
                _visiblePasswordRows.remove(i);
              else
                _visiblePasswordRows.add(i);
            });
          },
        ),
      ],
    )),
    // Estado con switch
    DataCell(_stateCell(
      activo: c.activo,
      onChanged: (v) async {
        final pass = await _solicitarPassword('Confirmar estado');
        if (pass == adminPassword) setState(() => c.activo = v);
        else if (pass != null) _mostrarError();
      },
    )),

    // Eliminar
    DataCell(
      IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red),
        onPressed: () async {
          final pass = await _solicitarPassword('Confirmar eliminación');
          if (pass == adminPassword) {
            setState(() => escuelas.remove(c));
          } else if (pass != null) {
            _mostrarError();
          }
        },
      ),
    ),
  ]);
}).toList(),
                  ),
                ),
        ),
      ],
    ),
  );
}
Widget _buildFreelancersView(BuildContext context, bool isMobile) {
  final lista = freelancers
      .where((f) => f.nombre.toLowerCase().contains(filtroFreelancer.toLowerCase()))
      .toList();

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
                  labelText: 'Buscar freelancer...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => filtroFreelancer = v),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Freelancer'),
              onPressed: () => _showAddDialog(
                title: 'Nuevo freelancer',
                hint: 'Nombre del freelancer',
                onSave: agregarFreelancer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('No hay freelancers registrados'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    headingRowColor:
                        MaterialStateProperty.all(Colors.blue.shade50),
                    columns: const [
                      DataColumn(label: Text('Freelancer')),
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Contraseña')),
                      DataColumn(label: Text('Maestro')),
                      DataColumn(label: Text('Estudiante')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Eliminar')),
                    ],
                    rows: List.generate(lista.length, (i) {
                      final f = lista[i];
                      return DataRow(cells: [
                        // Nombre
                        DataCell(Text(f.nombre)),
                        // Fecha
                        DataCell(Text(
                            '${f.fecha.day}/${f.fecha.month}/${f.fecha.year}')),

                   // Contraseña con botón ojo
DataCell(Row(
  children: [
    Text(
      _visibleFreelancerRows.contains(i) ? f.password : '••••••••',
      style: const TextStyle(fontFamily: 'monospace'),
    ),
    IconButton(
      icon: Icon(
        _visibleFreelancerRows.contains(i)
            ? Icons.visibility_off
            : Icons.visibility,
      ),
      onPressed: () {
        setState(() {
          if (_visibleFreelancerRows.contains(i)) {
            _visibleFreelancerRows.remove(i);
          } else {
            _visibleFreelancerRows.add(i);
          }
        });
      },
    ),
  ],
)),


                        // Enlace Maestro (icono + copia al portapapeles)
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.person, color: Colors.blue),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: f.teacherLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enlace Maestro copiado')),
                              );
                            },
                          ),
                        ),

                        // Enlace Estudiante (icono + copia)
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.person_outline, color: Colors.green),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: f.studentLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enlace Estudiante copiado')),
                              );
                            },
                          ),
                        ),

                        // Estado con switch
                        DataCell(_stateCell(
                          activo: f.activo,
                          onChanged: (v) async {
                            final pass = await _solicitarPassword('Confirmar estado');
                            if (pass == adminPassword) setState(() => f.activo = v);
                            else if (pass != null) _mostrarError();
                          },
                        )),

                        // Eliminar
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            onPressed: () async {
                              final pass = await _solicitarPassword('Confirmar eliminación');
                              if (pass == adminPassword) {
                                setState(() => freelancers.remove(f));
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
}
 // Widget _linkCell(String url) => Row(
    //    children: [
//          Expanded(
   //         child: Text(url, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
   //       ),
  //        IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => copiar(url)),
   //     ],
 //     );

  Widget _stateCell({
    required bool activo,
    required void Function(bool) onChanged,
  }) =>
      Row(children: [
        Switch(value: activo, onChanged: onChanged),
        Text(activo ? 'Activo' : 'Pausado',
            style: TextStyle(color: activo ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
      ]);
}

