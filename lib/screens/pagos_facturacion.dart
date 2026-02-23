// lib/screens/pagos_facturacion.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart' as config;

// Repositorios / modelos — ajusta rutas si en tu proyecto están en otra carpeta
import '../data/escuela_repository.dart';
import '../models/escuela.dart';


class PagosFacturacionScreen extends StatefulWidget {
  const PagosFacturacionScreen({Key? key}) : super(key: key);

  @override
  _PagosFacturacionScreenState createState() => _PagosFacturacionScreenState();
}

class _PagosFacturacionScreenState extends State<PagosFacturacionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currency = NumberFormat.simpleCurrency();

  // ✅ Paleta igual a Colegios / Configuración
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  // Preferencias persistidas
  static const _prefsKey = 'pagos_facturacion_v1';

  // UI / datos
  List<String> _paymentMethods = ['PayPal', 'Stripe', 'Transferencia'];
  final TextEditingController _newMethodController = TextEditingController();

  final TextEditingController _templateController = TextEditingController(
    text: 'Encabezado de la factura\n\n'
        'Cliente: {cliente}\n'
        'Fecha: {fecha}\n\n'
        'Detalle de productos…\n\n'
        'Total: {total}\n\n'
        '¡Gracias por su preferencia!',
  );

  List<Map<String, String>> _taxConfigs = [
    {'name': 'IVA', 'value': '18%'},
  ];
  final TextEditingController _taxNameController = TextEditingController();
  final TextEditingController _taxValueController = TextEditingController();

  final List<String> _roles = ['Administrador', 'Contador', 'Usuario'];
  List<String> _selectedRoles = ['Administrador'];

  bool _notifyOverdue = true;
  bool _notifyReceived = true;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadPrefs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newMethodController.dispose();
    _templateController.dispose();
    _taxNameController.dispose();
    _taxValueController.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildTopBar({required bool isMobile}) {
    return AppBar(
      backgroundColor: _kEduProBlue,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: isMobile,
      iconTheme: const IconThemeData(color: Colors.white),
      title: isMobile
          ? const Text(
              'Pagos & Facturación',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            )
          : const SizedBox.shrink(),
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
        _paymentMethods =
            List<String>.from(data['paymentMethods'] ?? _paymentMethods);
        _templateController.text = data['template'] ?? _templateController.text;
        _taxConfigs = (data['taxConfigs'] as List<dynamic>?)
                ?.map((e) => Map<String, String>.from(e as Map))
                .toList() ??
            _taxConfigs;
        _selectedRoles =
            List<String>.from(data['selectedRoles'] ?? _selectedRoles);
        _notifyOverdue = data['notifyOverdue'] ?? _notifyOverdue;
        _notifyReceived = data['notifyReceived'] ?? _notifyReceived;
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
      'paymentMethods': _paymentMethods,
      'template': _templateController.text,
      'taxConfigs': _taxConfigs,
      'selectedRoles': _selectedRoles,
      'notifyOverdue': _notifyOverdue,
      'notifyReceived': _notifyReceived,
    };
    await prefs.setString(_prefsKey, jsonEncode(out));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes de pagos y facturación guardados')),
      );
    }
  }

  // --- Diseño de pestañas / widgets ---
  Widget _buildMetricsCard(String title, String value, {Color? color}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

/// Construye métricas solo con colegios
Widget _buildTopMetrics({required bool isMobile}) {
  final List<Escuela> escuelas = EscuelaRepository.escuelas;
  final totalColegios = escuelas.length;

  const montoColegio = 50.0;
  final expectedRevenue = totalColegios * montoColegio;

  if (isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _buildMetricsCard('Colegios registrados', '$totalColegios'),
          const SizedBox(height: 10),
          _buildMetricsCard(
            'Facturación estimada',
            _currency.format(expectedRevenue),
            color: Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: _buildMetricsCard('Colegios registrados', '$totalColegios'),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildMetricsCard(
            'Facturación estimada',
            _currency.format(expectedRevenue),
            color: Colors.green.shade700,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildPaymentMethodsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Métodos de Pago',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ListView.separated(
                  itemCount: _paymentMethods.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final m = _paymentMethods[i];
                    return ListTile(
                      title: Text(m),
                      leading: const Icon(Icons.payment),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showRenameMethodDialog(i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => _paymentMethods.removeAt(i)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newMethodController,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo método de pago',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                onPressed: () {
                  final text = _newMethodController.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    _paymentMethods.add(text);
                    _newMethodController.clear();
                  });
                },
                child: const Text('Añadir'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _savePrefs,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRenameMethodDialog(int index) {
    final controller = TextEditingController(text: _paymentMethods[index]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar método'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                setState(() => _paymentMethods[index] = val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Plantilla de Factura',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _templateController,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Diseña la plantilla de tus facturas aquí...',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                onPressed: _savePrefs,
                icon: const Icon(Icons.save),
                label: const Text('Guardar plantilla'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() => _templateController.text = ''),
                icon: const Icon(Icons.clear),
                label: const Text('Limpiar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taxsDataTable() {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Nombre')),
        DataColumn(label: Text('Valor')),
        DataColumn(label: Text('Acciones')),
      ],
      rows: List<DataRow>.generate(_taxConfigs.length, (i) {
        final t = _taxConfigs[i];
        return DataRow(cells: [
          DataCell(Text(t['name'] ?? '')),
          DataCell(Text(t['value'] ?? '')),
          DataCell(Row(
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _showEditTaxDialog(i),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => setState(() => _taxConfigs.removeAt(i)),
              ),
            ],
          )),
        ]);
      }),
    );
  }

  Widget _buildTaxTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Impuestos & Descuentos',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: _taxsDataTable(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _taxNameController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _taxValueController,
                            decoration: const InputDecoration(
                              labelText: 'Valor (ej. 18% o 50)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _kEduProBlue),
                          onPressed: () {
                            final name = _taxNameController.text.trim();
                            final value = _taxValueController.text.trim();
                            if (name.isEmpty || value.isEmpty) return;
                            setState(() {
                              _taxConfigs.add({'name': name, 'value': value});
                              _taxNameController.clear();
                              _taxValueController.clear();
                            });
                          },
                          child: const Text('Añadir'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _savePrefs,
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditTaxDialog(int index) {
    final t = Map<String, String>.from(_taxConfigs[index]);
    final nameCtrl = TextEditingController(text: t['name']);
    final valCtrl = TextEditingController(text: t['value']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar impuesto/descuento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valCtrl,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final val = valCtrl.text.trim();
              if (name.isEmpty || val.isEmpty) return;
              setState(() => _taxConfigs[index] = {'name': name, 'value': val});
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Permisos de Facturación',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ListView(
                  children: _roles.map((role) {
                    final selected = _selectedRoles.contains(role);
                    return CheckboxListTile(
                      title: Text(role),
                      value: selected,
                      activeColor: _kEduProBlue,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            if (!_selectedRoles.contains(role)) {
                              _selectedRoles.add(role);
                            }
                          } else {
                            _selectedRoles.remove(role);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _selectedRoles = ['Administrador']),
                child: const Text('Restaurar por defecto'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                onPressed: _savePrefs,
                child: const Text('Guardar permisos'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Notificaciones',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Notificar facturas vencidas'),
                    value: _notifyOverdue,
                    activeColor: _kEduProBlue,
                    onChanged: (v) => setState(() => _notifyOverdue = v),
                  ),
                  SwitchListTile(
                    title: const Text('Notificar pago recibido'),
                    value: _notifyReceived,
                    activeColor: _kEduProBlue,
                    onChanged: (v) => setState(() => _notifyReceived = v),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton(onPressed: _savePrefs, child: const Text('Guardar')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                        onPressed: () {
                          setState(() {
                            _notifyOverdue = true;
                            _notifyReceived = true;
                          });
                        },
                        child: const Text('Restaurar por defecto'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute =
        ModalRoute.of(context)?.settings.name ?? '/pagos-facturacion';

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    void go(String r) => Navigator.pushReplacementNamed(context, r);

    // Pestañas (contenido principal) — una sola TabBar (sin duplicar)
    final pageContent = Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: _kEduProBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _kEduProBlue,
            tabs: const [
              Tab(text: 'Métodos'),
              Tab(text: 'Plantillas'),
              Tab(text: 'Impuestos'),
              Tab(text: 'Permisos'),
              Tab(text: 'Notificaciones'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPaymentMethodsTab(),
              _buildTemplateTab(),
              _buildTaxTab(),
              _buildPermissionsTab(),
              _buildNotificationsTab(),
            ],
          ),
        ),
      ],
    );

    Widget wrappedMainCard(Widget child) {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 16,
          vertical: isMobile ? 16 : 8,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: child,
      );
    }

    // ✅ Mobile
    if (isMobile) {
      return Scaffold(
        backgroundColor: _kPageBg,
        appBar: _buildTopBar(isMobile: true),
        drawer: Drawer(
          backgroundColor: _kEduProBlue,
          child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
        ),
        body: Column(
          children: [
            // ✅ ConfigMenu con iconos arriba (móvil)
            config.ConfigMenu(selectedKey: 'pagos-facturacion', onItemSelected: go),
            _buildTopMetrics(isMobile: true),
            Expanded(child: wrappedMainCard(pageContent)),
          ],
        ),
      );
    }

    // ✅ Desktop / Web
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: false),
      body: Row(
        children: [
          // Sidebar global azul
          Container(
            width: 260,
            color: _kEduProBlue,
            child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
          ),

          // Borde azul + submenú blanco (igual a otras pantallas)
          Container(
            width: 286, // 6px borde + 280 menu
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: _kEduProBlue, width: 6)),
            ),
            child: config.ConfigMenu(
              selectedKey: 'pagos-facturacion',
              onItemSelected: go,
            ),
          ),

          const SizedBox(width: 24),

          // Contenido
          Expanded(
            child: Column(
              children: [
                _buildTopMetrics(isMobile: false),
                Expanded(child: wrappedMainCard(pageContent)),
              ],
            ),
          ),

          const SizedBox(width: 24),
        ],
      ),
    );
  }
}
