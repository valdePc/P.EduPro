// lib/screens/pagos_facturacion.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart' as config;
import '../widgets/config_header.dart';

class PagosFacturacionScreen extends StatefulWidget {
  const PagosFacturacionScreen({Key? key}) : super(key: key);

  @override
  _PagosFacturacionScreenState createState() =>
      _PagosFacturacionScreenState();
}

class _PagosFacturacionScreenState extends State<PagosFacturacionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
    {'name': 'Descuento', 'value': '5%'},
  ];
  final TextEditingController _taxNameController = TextEditingController();
  final TextEditingController _taxValueController = TextEditingController();

  List<String> _roles = ['Administrador', 'Contador', 'Usuario'];
  List<String> _selectedRoles = ['Administrador'];

  bool _notifyOverdue = true;
  bool _notifyReceived = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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

  Widget _buildPaymentMethodsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Métodos de Pago',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: _paymentMethods.map((m) {
                return ListTile(
                  title: Text(m),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () =>
                        setState(() => _paymentMethods.remove(m)),
                  ),
                );
              }).toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newMethodController,
                  decoration:
                      const InputDecoration(labelText: 'Nuevo método'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final text = _newMethodController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _paymentMethods.add(text);
                      _newMethodController.clear();
                    });
                  }
                },
                child: const Text('Añadir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Plantilla de Factura',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _templateController,
              maxLines: null,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              // Guardar plantilla
            },
            child: const Text('Guardar plantilla'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impuestos & Descuentos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: _taxConfigs.map((t) {
                return ListTile(
                  title: Text('${t['name']}: ${t['value']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => setState(() => _taxConfigs.remove(t)),
                  ),
                );
              }).toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taxNameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _taxValueController,
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final name = _taxNameController.text.trim();
                  final value = _taxValueController.text.trim();
                  if (name.isNotEmpty && value.isNotEmpty) {
                    setState(() {
                      _taxConfigs.add({'name': name, 'value': value});
                      _taxNameController.clear();
                      _taxValueController.clear();
                    });
                  }
                },
                child: const Text('Añadir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Permisos de Facturación',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: _roles.map((role) {
                return CheckboxListTile(
                  title: Text(role),
                  value: _selectedRoles.contains(role),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedRoles.add(role);
                    } else {
                      _selectedRoles.remove(role);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notificaciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Facturas vencidas'),
            value: _notifyOverdue,
            onChanged: (v) => setState(() => _notifyOverdue = v),
          ),
          SwitchListTile(
            title: const Text('Pago recibido'),
            value: _notifyReceived,
            onChanged: (v) => setState(() => _notifyReceived = v),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute =
        ModalRoute.of(context)?.settings.name ?? '/pagos-facturacion';

    // Definimos el contenido de las pestañas
    final pageContent = Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
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

    if (isMobile) {
      return DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Pagos & Facturación'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Métodos'),
                Tab(text: 'Plantillas'),
                Tab(text: 'Impuestos'),
                Tab(text: 'Permisos'),
                Tab(text: 'Notificaciones'),
              ],
            ),
          ),
          drawer: Drawer(
            child: SidebarMenu(
              currentRoute: currentRoute,
              onItemSelected: (r) =>
                  Navigator.pushReplacementNamed(context, r),
            ),
          ),
          body: pageContent,
        ),
      );
    }

    // Versión escritorio: banda azul fija encima de todo
    return Scaffold(
      body: Column(
        children: [
          // 1) Banda azul completa arriba
          const ConfigHeader(title: 'Configuración General'),

          // 2) Resto de la pantalla: sidebar + submenú + contenido
          Expanded(
            child: Row(
              children: [
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (r) =>
                      Navigator.pushReplacementNamed(context, r),
                ),
                config.ConfigMenu(
                  selectedKey: 'pagos-facturacion',
                  onItemSelected: (r) =>
                      Navigator.pushReplacementNamed(context, r),
                ),
                Expanded(child: pageContent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
