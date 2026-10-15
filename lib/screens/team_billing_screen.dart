import 'package:edupro/widgets/team_access_gate.dart';
import 'package:edupro/widgets/school_catalog_view.dart';
import 'package:edupro/services/team_school_catalog_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/school_billing_dates.dart';
import '../services/team_school_access_service.dart';
import '../widgets/sidebar_menu.dart';

/// Billing receives only the catalog and payment fields permitted by Firebase.
class TeamBillingScreen extends StatefulWidget {
  const TeamBillingScreen({super.key});

  @override
  State<TeamBillingScreen> createState() => _TeamBillingScreenState();
}

class _TeamBillingScreenState extends State<TeamBillingScreen> {
  late TeamSchoolCatalogController _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog = TeamSchoolAccessService.sharedCatalog(
      role: TeamAccessRoleScope.of(context),
    );
    _catalog.ensureFresh();
  }

  String _date(dynamic value) {
    final date =
        value is DateTime
            ? value
            : value is Timestamp
            ? value.toDate()
            : value is num
            ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
            : null;
    return date == null
        ? 'Sin registrar'
        : '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _payments(TeamSchoolRecord school) async {
    final future = TeamSchoolAccessService.call('getTeamSchoolBilling', {
      'schoolId': school.id,
    });
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Pagos · ${school.data()['name'] ?? school.id}'),
            content: SizedBox(
              width: 620,
              height: 420,
              child: FutureBuilder<Map<String, dynamic>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return const Text(
                      'No se pudieron consultar los pagos. Comprueba tu sesión e intenta nuevamente.',
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final payments = snapshot.data!['payments'] as List? ?? [];
                  if (payments.isEmpty)
                    return const Text(
                      'Este colegio no tiene pagos registrados.',
                    );
                  return ListView(
                    children: [
                      const Text('Últimos 50 pagos registrados'),
                      for (final payment in payments)
                        ListTile(
                          title: Text(
                            '${payment['amount'] ?? payment['monto'] ?? '-'} ${payment['currency'] ?? ''}',
                          ),
                          subtitle: Text(
                            '${payment['status'] ?? payment['estado'] ?? 'Sin estado'} · ${_date(payment['createdAt'])}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Facturación'),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: _catalog.refresh,
        ),
      ],
    ),
    drawer: Drawer(
      child: SidebarMenu(
        currentRoute: '/facturacion',
        onItemSelected: (route) {
          Navigator.pop(context);
          Navigator.pushReplacementNamed(context, route);
        },
      ),
    ),
    body: SchoolCatalogView(
      controller: _catalog,
      builder: (context) {
        final schools = _catalog.records;
        if (schools.isEmpty)
          return const Center(child: Text('No hay colegios registrados.'));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: schools.length,
          itemBuilder: (context, index) {
            final school = schools[index], data = school.data();
            return Card(
              child: ListTile(
                title: Text(
                  '${data['officialName'] ?? data['name'] ?? school.id}',
                ),
                subtitle: Text(
                  'Plan: ${data['planTier'] ?? 'Sin definir'} · Importe: ${data['planPrice'] ?? 'Sin definir'} ${data['currency'] ?? ''}\n'
                  'Vencimiento: ${_date(SchoolBillingDates.fromMap(data).renewalAt)}',
                ),
                trailing: const Icon(Icons.receipt_long),
                onTap: () => _payments(school),
              ),
            );
          },
        );
      },
    ),
  );
}
