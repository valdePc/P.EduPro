// lib/screens/facturacion.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';           // ← aquí
import '../widgets/sidebar_menu.dart';

class FacturacionScreen extends StatefulWidget {
  const FacturacionScreen({Key? key}) : super(key: key);

  @override
  _FacturacionScreenState createState() => _FacturacionScreenState();
}

class _FacturacionScreenState extends State<FacturacionScreen> {
  String _typeFilter = 'Todos';
  String _statusFilter = 'Todos';
  DateTimeRange? _dateRange;
  final _searchController = TextEditingController();

  final List<Map<String, String>> _invoices = [
    {
      'nombre': 'Colegio San José',
      'tipo': 'Colegio',
      'monto': '\$50 USD',
      'fecha': '10/05/2024',
      'estado': 'Pagado',
    },
    {
      'nombre': 'Juan Pérez',
      'tipo': 'Freelancer',
      'monto': '\$10 USD',
      'fecha': '05/05/2024',
      'estado': 'Pendiente',
    },
    {
      'nombre': 'Instituto Moderno',
      'tipo': 'Colegio',
      'monto': '\$50 USD',
      'fecha': '20/04/2024',
      'estado': 'Vencido',
    },
    {
      'nombre': 'Ana Górnez',
      'tipo': 'Freelancer',
      'monto': '\$10 USD',
      'fecha': '01/04/2024',
      'estado': 'Pagado',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute = ModalRoute.of(context)!.settings.name ?? '/facturacion';

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: Colors.blue.shade900,
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) => Navigator.pushReplacementNamed(context, route),
                ),
              ),
            )
          
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('Facturación'))
          : PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                color: Colors.blue.shade900,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  '...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
      body: isMobile
          ? Column(
              children: [
                _buildFilters(context, isMobile),
                const Divider(height: 1),
                Expanded(child: _buildBody(isMobile)),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.blue.shade900,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) => Navigator.pushReplacementNamed(context, route),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        _buildMetrics(isMobile),
                        const SizedBox(height: 24),
                        _buildFilters(context, isMobile),
                        const SizedBox(height: 16),
                        Expanded(child: _buildBody(isMobile)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Acción para nueva factura
        },
        backgroundColor: const Color.fromARGB(255, 235, 150, 4), 
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMetrics(bool isMobile) {
    final total = _invoices.fold<double>(
        0,
        (sum, inv) => sum +
            double.parse(inv['monto']!.replaceAll(RegExp(r'[^\d.]'), '')));
    final pendientes =
        _invoices.where((i) => i['estado'] == 'Pendiente').length;
    final vencidas = _invoices.where((i) => i['estado'] == 'Vencido').length;

    Widget card(String label, String value, Color color) {
      return Expanded(
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
        ),
      );
    }

    final cards = [
      card('Total facturado', NumberFormat.simpleCurrency().format(total),
          Colors.green.shade900,),
      const SizedBox(width: 12),
      card('Pendientes', '$pendientes', const Color.fromARGB(191, 240, 216, 0)),
      const SizedBox(width: 12),
      card('Vencidas', '$vencidas', Colors.red),
    ];

    return isMobile
        ? Column(children: cards.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 12), child: w)).toList())
        : Row(children: cards);
  }

  Widget _buildFilters(BuildContext context, bool isMobile) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 0),
      child: Wrap(
        runSpacing: 12,
        spacing: 12,
        alignment: WrapAlignment.start,
        children: [
          DropdownButton<String>(
            value: _typeFilter,
            items: ['Todos', 'Colegio', 'Freelancer']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _typeFilter = v!),
            hint: const Text('Tipo'),
          ),
          DropdownButton<String>(
            value: _statusFilter,
            items: ['Todos', 'Pagado', 'Pendiente', 'Vencido']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _statusFilter = v!),
            hint: const Text('Estado'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 1),
                lastDate: now,
              );
              if (picked != null) setState(() => _dateRange = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text(_dateRange == null
                ? 'Rango de fechas'
                : '${DateFormat.yMd().format(_dateRange!.start)} - ${DateFormat.yMd().format(_dateRange!.end)}'),
          ),
          SizedBox(
            width: isMobile ? double.infinity : 200,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isMobile) {
    final filtered = _invoices.where((inv) {
      final matchType = _typeFilter == 'Todos' || inv['tipo'] == _typeFilter;
      final matchStatus =
          _statusFilter == 'Todos' || inv['estado'] == _statusFilter;
      final matchSearch = _searchController.text.isEmpty ||
       inv.values.any((v) => v.toLowerCase()

              .contains(_searchController.text.toLowerCase()));
      final matchDate = _dateRange == null ||
          (DateFormat('dd/MM/yyyy')
                  .parse(inv['fecha']!)
                  .isAfter(_dateRange!.start.subtract(const Duration(days: 1))) &&
              DateFormat('dd/MM/yyyy')
                  .parse(inv['fecha']!)
                  .isBefore(_dateRange!.end.add(const Duration(days: 1))));
      return matchType && matchStatus && matchSearch && matchDate;
    }).toList();

    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final inv = filtered[i];
          Color estadoColor;
          switch (inv['estado']) {
            case 'Pagado':
              estadoColor = Colors.green.shade100;
              break;
            case 'Pendiente':
              estadoColor = Colors.yellow.shade100;
              break;
            default:
              estadoColor = Colors.red.shade100;
          }
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(inv['nombre']!),
              subtitle: Text('${inv['fecha']} • ${inv['estado']}'),
              trailing: Text(inv['monto']!),
              tileColor: estadoColor,
              onTap: () {},
            ),
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Nombre')),
          DataColumn(label: Text('Tipo')),
          DataColumn(label: Text('Monto')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Acciones')),
        ],
        rows: filtered.map((inv) {
          return DataRow(cells: [
            DataCell(Text(inv['nombre']!)),
            DataCell(Text(inv['tipo']!)),
            DataCell(Text(inv['monto']!)),
            DataCell(Text(inv['fecha']!)),
            DataCell(Text(inv['estado']!)),
            DataCell(Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_red_eye, size: 18),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 18),
                  onPressed: () {},
                ),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }
}
