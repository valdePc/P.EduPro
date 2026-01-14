// lib/screens/facturacion.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../widgets/sidebar_menu.dart';

class FacturacionScreen extends StatefulWidget {
  const FacturacionScreen({Key? key}) : super(key: key);

  @override
  State<FacturacionScreen> createState() => _FacturacionScreenState();
}

class _FacturacionScreenState extends State<FacturacionScreen> {
  final _db = FirebaseFirestore.instance;

  String _typeFilter = 'Todos';
  String _statusFilter = 'Todos';
  DateTimeRange? _dateRange;
  final _searchController = TextEditingController();

  bool _loadingRole = true;

  // ✅ En vez de "staff", trabajamos con permisos reales:
  bool _canSeeBilling = false; // puede entrar a Facturación
  bool _canReviewPayments = false; // puede verificar/rechazar pagos

  // Fallbacks si algún colegio no tiene planPrice todavía
  static const double tarifaPorAlumno = 1.0;
  static const double tarifaBaseColegio = 50.0;
  static const double tarifaBaseFreelancer = 10.0;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normRole(dynamic v) =>
      (v ?? '').toString().trim().toLowerCase().replaceAll(' ', '');

  Future<void> _loadRole() async {
    final u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      setState(() {
        _canSeeBilling = false;
        _canReviewPayments = false;
        _loadingRole = false;
      });
      return;
    }

    final uid = u.uid.trim();
    final email = (u.email ?? '').trim().toLowerCase();

    bool enabled = true;
    bool isSuperAdmin = false;
    bool isStaffAdmin = false;

    // 1) ✅ Fuente principal: users/{uid} (como tu imagen)
    try {
      final userSnap = await _db.collection('users').doc(uid).get();
      final data = userSnap.data() ?? {};

      // enabled por defecto true si no existe
      final enabledRaw = data['enabled'];
      if (enabledRaw is bool) enabled = enabledRaw;

      final role = _normRole(data['role']); // "superAdmin" -> "superadmin"
      isSuperAdmin = role == 'superadmin';

      // "staffAdmin: true" (tu campo)
      isStaffAdmin = (data['staffAdmin'] == true);

      // Compatibilidad por si tienes cosas viejas:
      // isStaff / admin / staff
      final legacyRole = role;
      if (!isStaffAdmin) {
        isStaffAdmin = (data['isStaff'] == true) ||
            legacyRole == 'staff' ||
            legacyRole == 'admin';
      }
    } catch (_) {
      // Si falla leer users/{uid}, no rompemos todo.
      // (Pero ojo: si esto falla por reglas, no podremos autorizar por este método.)
    }

    // 2) (Opcional) fallback por app_config/billing (NO debe tumbar el flujo si da permission-denied)
    bool isListedByAppConfig = false;
    try {
      final billingDoc = await _db.collection('app_config').doc('billing').get();
      final billing = billingDoc.data() ?? {};

      // OJO: tú dijiste "staffemail" (minúscula). Soporto ambos.
      final staffEmailsRaw = billing['staffEmail'] ?? billing['staffemail'];
      final staffEmails = (staffEmailsRaw is List)
          ? staffEmailsRaw
              .whereType<String>()
              .map((e) => e.trim().toLowerCase())
              .toList()
          : <String>[];

      final staffUidsRaw = billing['staffUids'];
      final staffUids = (staffUidsRaw is List)
          ? staffUidsRaw.whereType<String>().map((e) => e.trim()).toList()
          : <String>[];

      final byEmail = email.isNotEmpty && staffEmails.contains(email);
      final byUid = uid.isNotEmpty && staffUids.contains(uid);

      isListedByAppConfig = byEmail || byUid;
    } catch (_) {
      // Si no tienes permiso de leer app_config/billing, no pasa nada.
    }

    // ✅ Política final
    final canSee = enabled && (isSuperAdmin || isStaffAdmin || isListedByAppConfig);

    // ✅ Quien puede verificar/rechazar pagos:
    // (si quieres que solo SUPERADMIN pueda, cambia a: enabled && isSuperAdmin)
    final canReview = enabled && (isSuperAdmin || isStaffAdmin);

    setState(() {
      _canSeeBilling = canSee;
      _canReviewPayments = canReview;
      _loadingRole = false;
    });
  }

  // Barra azul superior (Desktop)
  Widget _buildTopBlueBar() {
    return Container(
      color: Colors.blue.shade900,
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onPressed: () {},
              tooltip: 'Más',
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  String _fmtDate(DateTime d) => DateFormat.yMd().format(d);

  bool _isPastDue(DateTime? due) {
    if (due == null) return false;
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(due.year, due.month, due.day);
    return b.isBefore(a);
  }

  int _detectStudentCount(Map<String, dynamic> data) {
    for (final key in [
      'alumnos',
      'alumnosCount',
      'estudiantes',
      'totalAlumnos',
      'cantidadAlumnos',
      'students',
      'studentsCount',
    ]) {
      final v = data[key];
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v.replaceAll(RegExp(r'[^\d]'), ''));
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  double _calcSchoolAmount(Map<String, dynamic> school) {
    final planPrice = school['planPrice'];
    if (planPrice is num) return planPrice.toDouble();

    final alumnos = _detectStudentCount(school);
    final monto = alumnos > 0
        ? max(tarifaBaseColegio, alumnos * tarifaPorAlumno)
        : tarifaBaseColegio;
    return monto;
  }

  double _calcFreelancerAmount(Map<String, dynamic> freelancer) {
    final planPrice = freelancer['planPrice'];
    if (planPrice is num) return planPrice.toDouble();
    return tarifaBaseFreelancer;
  }

  String _schoolStatus(Map<String, dynamic> school) {
    final due = _tsToDate(school['billingNextDueAt']);
    final lastPaid = _tsToDate(school['billingLastPaidAt']);

    if (due == null) return 'Pendiente';
    if (_isPastDue(due)) return 'Vencido';
    return (lastPaid != null) ? 'Pagado' : 'Pagado';
  }

  String _freelancerStatus(Map<String, dynamic> freelancer) {
    final due = _tsToDate(freelancer['billingNextDueAt']);
    final lastPaid = _tsToDate(freelancer['billingLastPaidAt']);

    if (due == null) return 'Pendiente';
    if (_isPastDue(due)) return 'Vencido';
    return (lastPaid != null) ? 'Pagado' : 'Pagado';
  }

  Future<void> _openPaymentsSheet({
    required String schoolId,
    required String schoolName,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SchoolPaymentsSheet(
        schoolId: schoolId,
        schoolName: schoolName,
        canReviewPayments: _canReviewPayments,
      ),
    );
  }

  Widget _buildMetrics(bool isMobile, List<_BillingRow> rows) {
    final total = rows.fold<double>(0, (sum, r) => sum + r.monto);
    final pendientes = rows.where((r) => r.estado == 'Pendiente').length;
    final vencidas = rows.where((r) => r.estado == 'Vencido').length;

    Widget card(String label, String value, Color color) {
      return Expanded(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ]),
          ),
        ),
      );
    }

    final money = NumberFormat.currency(symbol: '');
    final cards = [
      card('Total (estimado)', money.format(total), Colors.green.shade900),
      const SizedBox(width: 12),
      card('Pendientes', '$pendientes', const Color.fromARGB(191, 240, 216, 0)),
      const SizedBox(width: 12),
      card('Vencidas', '$vencidas', Colors.red),
    ];

    return isMobile
        ? Column(
            children: cards
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: w,
                    ))
                .toList(),
          )
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
          ),
          DropdownButton<String>(
            value: _statusFilter,
            items: ['Todos', 'Pagado', 'Pendiente', 'Vencido']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _statusFilter = v!),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _dateRange = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text(
              _dateRange == null
                  ? 'Rango de fechas'
                  : '${DateFormat.yMd().format(_dateRange!.start)} - ${DateFormat.yMd().format(_dateRange!.end)}',
            ),
          ),
          SizedBox(
            width: isMobile ? double.infinity : 220,
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

  List<_BillingRow> _applyFilters(List<_BillingRow> rows) {
    final currencyFmt = NumberFormat.currency(symbol: '');

    final filtered = rows.where((r) {
      final matchType = _typeFilter == 'Todos' || r.tipo == _typeFilter;
      final matchStatus = _statusFilter == 'Todos' || r.estado == _statusFilter;

      final search = _searchController.text.trim().toLowerCase();
      final matchSearch = search.isEmpty ||
          r.nombre.toLowerCase().contains(search) ||
          r.tipo.toLowerCase().contains(search) ||
          r.estado.toLowerCase().contains(search) ||
          currencyFmt.format(r.monto).toLowerCase().contains(search) ||
          r.currency.toLowerCase().contains(search);

      final matchDate = _dateRange == null ||
          ((_dateRange!.start.isBefore(r.fecha.add(const Duration(days: 1))) ||
                  _dateRange!.start.isAtSameMomentAs(r.fecha)) &&
              (_dateRange!.end.isAfter(r.fecha.subtract(const Duration(days: 1))) ||
                  _dateRange!.end.isAtSameMomentAs(r.fecha)));

      return matchType && matchStatus && matchSearch && matchDate;
    }).toList();

    filtered.sort((a, b) => b.fecha.compareTo(a.fecha));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/facturacion';

    if (_loadingRole) {
      return Scaffold(
        appBar: isMobile
            ? AppBar(
                backgroundColor: Colors.blue.shade900,
                elevation: 0,
                title: const SizedBox.shrink(),
                systemOverlayStyle: SystemUiOverlayStyle.light,
              )
            : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // ✅ Solo superAdmin/staffAdmin (según users/{uid}) puede ver
    if (!_canSeeBilling) {
      return Scaffold(
        appBar: isMobile
            ? AppBar(
                backgroundColor: Colors.blue.shade900,
                elevation: 0,
                title: const SizedBox.shrink(),
                systemOverlayStyle: SystemUiOverlayStyle.light,
              )
            : null,
        body: const Center(
          child: Text('No tienes permisos para ver Facturación (solo superAdmin/staffAdmin).'),
        ),
      );
    }

    final schoolsStream = _db.collection('schools').snapshots();
    final freelancersStream = _db.collection('freelancers').snapshots();

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
          ? AppBar(
              backgroundColor: Colors.blue.shade900,
              elevation: 0,
              title: const SizedBox.shrink(),
              systemOverlayStyle: SystemUiOverlayStyle.light,
              actions: [
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {})),
                IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
              ],
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: schoolsStream,
        builder: (context, schoolSnap) {
          if (schoolSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (schoolSnap.hasError) {
            return Center(child: Text('Error leyendo colegios: ${schoolSnap.error}'));
          }
          final schoolDocs = schoolSnap.data?.docs ?? [];

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: freelancersStream,
            builder: (context, freeSnap) {
              if (freeSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (freeSnap.hasError) {
                return Center(child: Text('Error leyendo freelancers: ${freeSnap.error}'));
              }

              final freeDocs = freeSnap.data?.docs ?? [];
              final rows = <_BillingRow>[];

              for (final d in schoolDocs) {
                final data = d.data();
                final nombre = (data['nombre'] ?? data['name'] ?? 'Colegio').toString();
                final currency = (data['billingCurrency'] ?? 'DOP').toString();
                final due = _tsToDate(data['billingNextDueAt']);
                final fecha = due ?? DateTime.now();

                rows.add(
                  _BillingRow(
                    id: d.id,
                    nombre: nombre,
                    tipo: 'Colegio',
                    monto: _calcSchoolAmount(data),
                    currency: currency,
                    fecha: fecha,
                    estado: _schoolStatus(data),
                  ),
                );
              }

              for (final d in freeDocs) {
                final data = d.data();
                final nombre = (data['nombre'] ?? data['name'] ?? 'Freelancer').toString();
                final currency = (data['billingCurrency'] ?? 'DOP').toString();
                final due = _tsToDate(data['billingNextDueAt']);
                final fecha = due ?? DateTime.now();

                rows.add(
                  _BillingRow(
                    id: d.id,
                    nombre: nombre,
                    tipo: 'Freelancer',
                    monto: _calcFreelancerAmount(data),
                    currency: currency,
                    fecha: fecha,
                    estado: _freelancerStatus(data),
                  ),
                );
              }

              final filtered = _applyFilters(rows);

              Widget bodyContent() {
                if (isMobile) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final r = filtered[i];
                      final money = NumberFormat.simpleCurrency(name: r.currency);

                      Color estadoColor;
                      switch (r.estado) {
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
                          title: Text(r.nombre),
                          subtitle: Text('${_fmtDate(r.fecha)} • ${r.estado}'),
                          trailing: Text(money.format(r.monto)),
                          tileColor: estadoColor,
                          onTap: r.tipo == 'Colegio'
                              ? () => _openPaymentsSheet(schoolId: r.id, schoolName: r.nombre)
                              : null,
                        ),
                      );
                    },
                  );
                }

                final money = NumberFormat.currency(symbol: '');
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Tipo')),
                      DataColumn(label: Text('Monto')),
                      DataColumn(label: Text('Fecha (Due)')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: filtered.map((r) {
                      return DataRow(cells: [
                        DataCell(Text(r.nombre)),
                        DataCell(Text(r.tipo)),
                        DataCell(Text('${money.format(r.monto)} ${r.currency}')),
                        DataCell(Text(_fmtDate(r.fecha))),
                        DataCell(Text(r.estado)),
                        DataCell(
                          Row(
                            children: [
                              if (r.tipo == 'Colegio')
                                IconButton(
                                  icon: const Icon(Icons.receipt_long, size: 18),
                                  tooltip: 'Ver reportes de pago',
                                  onPressed: () => _openPaymentsSheet(
                                    schoolId: r.id,
                                    schoolName: r.nombre,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                );
              }

              return isMobile
                  ? Column(
                      children: [
                        _buildFilters(context, isMobile),
                        const Divider(height: 1),
                        Expanded(child: bodyContent()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildTopBlueBar(),
                        Expanded(
                          child: Row(
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
                                      _buildMetrics(isMobile, rows),
                                      const SizedBox(height: 24),
                                      _buildFilters(context, isMobile),
                                      const SizedBox(height: 16),
                                      Expanded(child: bodyContent()),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
            },
          );
        },
      ),
    );
  }
}

class _BillingRow {
  final String id;
  final String nombre;
  final String tipo;
  final double monto;
  final String currency;
  final DateTime fecha;
  final String estado;

  _BillingRow({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.monto,
    required this.currency,
    required this.fecha,
    required this.estado,
  });
}

class _SchoolPaymentsSheet extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final bool canReviewPayments;

  const _SchoolPaymentsSheet({
    required this.schoolId,
    required this.schoolName,
    required this.canReviewPayments,
  });

  @override
  State<_SchoolPaymentsSheet> createState() => _SchoolPaymentsSheetState();
}

class _SchoolPaymentsSheetState extends State<_SchoolPaymentsSheet> {
  final _db = FirebaseFirestore.instance;
  bool _saving = false;

  DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  DateTime _addOneMonth(DateTime d) {
    final y = d.year + (d.month == 12 ? 1 : 0);
    final m = d.month == 12 ? 1 : d.month + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = min(d.day, lastDay);
    return DateTime(y, m, day, d.hour, d.minute, d.second);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setStatus({
    required String paymentId,
    required Map<String, dynamic> payment,
    required String newStatus,
  }) async {
    if (!widget.canReviewPayments) {
      _toast('Solo superAdmin/staffAdmin puede verificar o rechazar pagos.');
      return;
    }
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final payRef = _db
          .collection('schools')
          .doc(widget.schoolId)
          .collection('payments')
          .doc(paymentId);

      final schoolRef = _db.collection('schools').doc(widget.schoolId);

      final paidAt = _tsToDate(payment['paidAt']) ?? DateTime.now();

      await _db.runTransaction((tx) async {
        final paySnap = await tx.get(payRef);
        if (!paySnap.exists) return;

        tx.update(payRef, {
          'status': newStatus,
          if (newStatus == 'verified') 'verifiedAt': FieldValue.serverTimestamp(),
          if (newStatus == 'rejected') 'rejectedAt': FieldValue.serverTimestamp(),
          'reviewedByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
        });

        if (newStatus == 'verified') {
          tx.update(schoolRef, {
            'billingLastPaidAt': Timestamp.fromDate(paidAt),
            'billingNextDueAt': Timestamp.fromDate(_addOneMonth(paidAt)),
          });
        }
      });

      _toast(newStatus == 'verified' ? 'Pago verificado ✅' : 'Pago rechazado ❌');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _db
        .collection('schools')
        .doc(widget.schoolId)
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .limit(30);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    'Reportes de pago — ${widget.schoolName}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }

                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No hay pagos reportados.'));
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final m = d.data();
                        final status = (m['status'] ?? 'submitted').toString();
                        final method = (m['method'] ?? '—').toString();
                        final ref = (m['reference'] ?? '').toString();
                        final amount = (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0;
                        final currency = (m['currency'] ?? 'DOP').toString();
                        final paidAt = _tsToDate(m['paidAt']);
                        final submittedBy = (m['submittedByEmail'] ?? '').toString();

                        Color badge;
                        switch (status) {
                          case 'verified':
                            badge = Colors.green;
                            break;
                          case 'rejected':
                            badge = Colors.red;
                            break;
                          default:
                            badge = Colors.orange;
                        }

                        final money = NumberFormat.simpleCurrency(name: currency);

                        return ListTile(
                          title: Text(
                            '$method • ${money.format(amount)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${paidAt == null ? '' : DateFormat.yMd().format(paidAt)}'
                            '${ref.trim().isEmpty ? '' : ' • Ref: $ref'}'
                            '${submittedBy.trim().isEmpty ? '' : '\nPor: $submittedBy'}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: badge.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: badge.withOpacity(0.35)),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(fontWeight: FontWeight.w900, color: badge),
                                ),
                              ),
                              if (widget.canReviewPayments && status == 'submitted')
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Verificar',
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: _saving
                                          ? null
                                          : () => _setStatus(
                                                paymentId: d.id,
                                                payment: m,
                                                newStatus: 'verified',
                                              ),
                                    ),
                                    IconButton(
                                      tooltip: 'Rechazar',
                                      icon: const Icon(Icons.cancel, color: Colors.red),
                                      onPressed: _saving
                                          ? null
                                          : () => _setStatus(
                                                paymentId: d.id,
                                                payment: m,
                                                newStatus: 'rejected',
                                              ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
