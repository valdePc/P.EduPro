// lib/admin_escolar/screens/A_pagos.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class APagos extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride;

  const APagos({
    super.key,
    required this.escuela,
    this.schoolIdOverride,
  });

  @override
  State<APagos> createState() => _APagosState();
}

class _APagosState extends State<APagos> {
  final _db = FirebaseFirestore.instance;

  String? _schoolIdRaw;
  String? _schoolId;

  bool _resolvingSchool = true;
  String? _resolveError;

  static const Map<String, Map<String, dynamic>> _planDefaults = {
    'starter': {'name': 'Starter', 'price': 79, 'max': 200},
    'pro': {'name': 'Pro', 'price': 129, 'max': 500},
    'premium': {'name': 'Premium', 'price': 199, 'max': 1200},
  };

  @override
  void initState() {
    super.initState();
    _resolveSchoolId();
  }

  // Solo limpia lo mínimo (Firestore no permite "/" en docId)
  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  bool _isPastDue(DateTime? due) {
    if (due == null) return false;
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(due.year, due.month, due.day);
    return b.isBefore(a);
  }

  int? _daysLeft(DateTime? due) {
    if (due == null) return null;
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(due.year, due.month, due.day);
    return b.difference(a).inDays;
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _toast('$label copiado.');
  }

  Future<String?> _tryResolveByDocId(String candidate) async {
    final doc = await _db.collection('schools').doc(candidate).get();
    if (doc.exists) return candidate;
    return null;
  }

  Future<String?> _tryResolveByQueries({
    required String uid,
    required String? candidate,
    required String schoolName,
  }) async {
    final candidatesToTry = <String>{
      uid.trim(),
      if (candidate != null && candidate.trim().isNotEmpty) candidate.trim(),
    }.toList();

    for (final v in candidatesToTry) {
      final qs1 = await _db
          .collection('schools')
          .where('adminUid', isEqualTo: v)
          .limit(1)
          .get();
      if (qs1.docs.isNotEmpty) return qs1.docs.first.id;

      final qs2 = await _db
          .collection('schools')
          .where('schoolAdminUid', isEqualTo: v)
          .limit(1)
          .get();
      if (qs2.docs.isNotEmpty) return qs2.docs.first.id;

      final qs3 = await _db
          .collection('schools')
          .where('ownerUid', isEqualTo: v)
          .limit(1)
          .get();
      if (qs3.docs.isNotEmpty) return qs3.docs.first.id;

      final qs4 = await _db
          .collection('schools')
          .where('createdByUid', isEqualTo: v)
          .limit(1)
          .get();
      if (qs4.docs.isNotEmpty) return qs4.docs.first.id;

      final qs5 = await _db
          .collection('schools')
          .where('admins', arrayContains: v)
          .limit(1)
          .get();
      if (qs5.docs.isNotEmpty) return qs5.docs.first.id;
    }

    final byNombre = await _db
        .collection('schools')
        .where('nombre', isEqualTo: schoolName.trim())
        .limit(1)
        .get();
    if (byNombre.docs.isNotEmpty) return byNombre.docs.first.id;

    final byName = await _db
        .collection('schools')
        .where('name', isEqualTo: schoolName.trim())
        .limit(1)
        .get();
    if (byName.docs.isNotEmpty) return byName.docs.first.id;

    return null;
  }

  Future<void> _resolveSchoolId() async {
    setState(() {
      _resolvingSchool = true;
      _resolveError = null;
    });

    try {
      final override = widget.schoolIdOverride?.trim();
      if (override != null && override.isNotEmpty) {
        _schoolIdRaw = override;
        _schoolId = _cleanSchoolId(override);
        debugPrint('APagos schoolId override=$_schoolIdRaw -> clean=$_schoolId');
        setState(() => _resolvingSchool = false);
        return;
      }

      final candidateRaw = normalizeSchoolIdFromEscuela(widget.escuela).trim();
      _schoolIdRaw = candidateRaw;
      final candidateClean = _cleanSchoolId(candidateRaw);

      final byDoc = await _tryResolveByDocId(candidateClean);
      if (byDoc != null) {
        _schoolId = byDoc;
        debugPrint('APagos resolved by docId candidate=$_schoolIdRaw -> $_schoolId');
        setState(() => _resolvingSchool = false);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      if (uid.isEmpty) {
        throw 'No hay usuario autenticado para resolver el colegio.';
      }

      final schoolName = (widget.escuela.nombre ?? '').toString();
      final resolved = await _tryResolveByQueries(
        uid: uid,
        candidate: candidateClean,
        schoolName: schoolName,
      );

      if (resolved == null || resolved.trim().isEmpty) {
        throw 'No pude encontrar el colegio en /schools. '
            'Candidato: "$candidateClean" | UID: "$uid" | Nombre: "$schoolName". '
            'Solución recomendada: guardar adminUid (o admins[]) en el doc del colegio cuando se crea.';
      }

      _schoolId = resolved.trim();
      debugPrint(
        'APagos resolved schoolId: candidate=$_schoolIdRaw ($candidateClean) | uid=$uid -> schoolId=$_schoolId',
      );

      setState(() => _resolvingSchool = false);
    } catch (e) {
      setState(() {
        _resolvingSchool = false;
        _resolveError = e.toString();
      });
    }
  }

  Future<void> _openReportPaymentDialog({
    required Map<String, dynamic> schoolData,
    required String currency,
    required String planTier,
  }) async {
    final defaults = _planDefaults[planTier] ?? _planDefaults['starter']!;
    final suggestedAmount = (schoolData['planPrice'] is num)
        ? (schoolData['planPrice'] as num).toString()
        : (defaults['price'] as int).toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportPaymentDialog(
        schoolId: _schoolId!,
        schoolName: (widget.escuela.nombre ?? 'Colegio').toString(),
        currency: currency,
        suggestedAmount: suggestedAmount,
      ),
    );

    if (ok == true) _toast('Pago reportado. Pendiente de verificación.');
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final azulDark = const Color.fromARGB(255, 13, 71, 161);
    final bg = const Color(0xFFF4F7FB);

    if (_resolvingSchool) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text('Pagos — ${widget.escuela.nombre ?? ''}'),
          backgroundColor: azul,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolveError != null || _schoolId == null || _schoolId!.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text('Pagos — ${widget.escuela.nombre ?? ''}'),
          backgroundColor: azul,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: _EmptyState(
          title: 'No se pudo identificar el colegio',
          subtitle: _resolveError ?? 'SchoolId vacío.',
        ),
      );
    }

    final schoolDocRef = _db.collection('schools').doc(_schoolId);

    // app_config/billing
    final billingGlobalRef = _db.collection('app_config').doc('billing');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Pagos — ${widget.escuela.nombre ?? ''}'),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: schoolDocRef.snapshots(),
        builder: (context, schoolSnap) {
          if (schoolSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!schoolSnap.hasData || schoolSnap.data == null || !schoolSnap.data!.exists) {
            return _EmptyState(
              title: 'No se encontró este colegio en Firestore',
              subtitle: 'SchoolId usado: $_schoolId',
            );
          }

          final schoolData = schoolSnap.data!.data() ?? {};
          final planTier = (schoolData['planTier'] ?? 'starter').toString().trim();
          final defaults = _planDefaults[planTier] ?? _planDefaults['starter']!;

          final planName = (schoolData['planName'] ?? defaults['name']).toString().trim();
          final currencySchool = (schoolData['billingCurrency'] ?? '').toString().trim();

          final planPrice = (schoolData['planPrice'] is num)
              ? (schoolData['planPrice'] as num)
              : (defaults['price'] as int);

          final dueAt = _tsToDate(schoolData['billingNextDueAt']);
          final lastPaidAt = _tsToDate(schoolData['billingLastPaidAt']);

          final pastDue = _isPastDue(dueAt);
          final daysLeft = _daysLeft(dueAt);

          final statusLabel = dueAt == null
              ? 'Sin fecha'
              : pastDue
                  ? 'Vencido'
                  : 'Al día';

          final statusColor = dueAt == null
              ? Colors.orange
              : pastDue
                  ? Colors.red
                  : Colors.green;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: billingGlobalRef.snapshots(),
            builder: (context, billingSnap) {
              final billing = billingSnap.data?.data() ?? <String, dynamic>{};

              final paypalUrl = (billing['paypalUrl'] ?? '').toString().trim();
              final currencyDefault = (billing['currencyDefault'] ?? 'DOP').toString().trim();

              final currency = currencySchool.isNotEmpty ? currencySchool : currencyDefault;

              final bankAccountsRaw = billing['bankAccounts'];
              final bankAccounts = (bankAccountsRaw is List)
                  ? bankAccountsRaw
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList()
                  : <Map<String, dynamic>>[];

              final priceText =
                  '${planPrice.toStringAsFixed(planPrice % 1 == 0 ? 0 : 2)} $currency / mes';

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                children: [
                  _Card(
                    accent: azul,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _LeadingIconBubble(
                              color: azulDark,
                              icon: Icons.receipt_long,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Plan activo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    planName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _StatusChip(
                              label: statusLabel,
                              color: statusColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: azul.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: azul.withOpacity(0.14)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.paid_outlined, color: azul, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  priceText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          icon: Icons.event,
                          title: 'Próxima fecha',
                          value: dueAt == null
                              ? 'No configurada'
                              : '${_fmtDate(dueAt)}'
                                  '${daysLeft != null ? ' • ${daysLeft >= 0 ? '$daysLeft días' : 'vencido'}' : ''}',
                          valueColor: pastDue ? Colors.red : null,
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.check_circle_outline,
                          title: 'Último pago verificado',
                          value: lastPaidAt == null ? 'No registrado' : _fmtDate(lastPaidAt),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: azul,
                              foregroundColor: Colors.white, // ✅ CONTRASTE
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            onPressed: () => _openReportPaymentDialog(
                              schoolData: schoolData,
                              currency: currency,
                              planTier: planTier,
                            ),
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Reportar pago realizado'),
                          ),
                        ),
                        if (daysLeft != null && daysLeft <= 5 && daysLeft >= 0) ...[
                          const SizedBox(height: 12),
                          _SoftWarning(
                            title: 'Aviso',
                            message: 'Faltan $daysLeft días para el pago.',
                            color: Colors.orange,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    accent: azul,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _LeadingIconBubble(color: azul, icon: Icons.account_balance_wallet_outlined),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Métodos de pago (global)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // PayPal
                        _MethodTile(
                          accent: azul,
                          icon: Icons.payments_outlined,
                          title: 'PayPal',
                          subtitle: paypalUrl.isEmpty
                              ? 'No configurado (configura app_config/billing.paypalUrl).'
                              : 'Paga por PayPal y luego reporta el pago con tu ID de transacción.',
                          trailing: paypalUrl.isEmpty
                              ? null
                              : TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: azul,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () => _copy('Link de PayPal', paypalUrl),
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copiar link'),
                                ),
                          extra: paypalUrl.isEmpty
                              ? null
                              : SelectableText(
                                  paypalUrl,
                                  style: const TextStyle(fontSize: 12.5, height: 1.2),
                                ),
                        ),

                        const Divider(height: 26),

                        // Bancos dominicanos (lista)
                        _MethodTile(
                          accent: azul,
                          icon: Icons.account_balance_outlined,
                          title: 'Transferencia bancaria (Rep. Dominicana)',
                          subtitle: bankAccounts.isEmpty
                              ? 'No configurado (configura app_config/billing.bankAccounts).'
                              : 'Transfiere a una cuenta y luego reporta el pago.',
                          trailing: bankAccounts.isEmpty
                              ? null
                              : TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: azul,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () => _copy(
                                    'Concepto sugerido',
                                    '$_schoolId • ${widget.escuela.nombre ?? ''}',
                                  ),
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copiar concepto'),
                                ),
                          extra: bankAccounts.isEmpty
                              ? null
                              : _BankAccountsList(
                                  accounts: bankAccounts,
                                  onCopy: _copy,
                                  accent: azul,
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  _PaymentsHistory(schoolId: _schoolId!, accent: azul),

                  const SizedBox(height: 12),
                  _Card(
                    accent: azul,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: azul),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nota: el pago queda como “submitted” hasta que EduPro lo verifique.',
                            style: TextStyle(color: Colors.grey.shade800, height: 1.2),
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

class _PaymentsHistory extends StatelessWidget {
  final String schoolId;
  final Color accent;
  const _PaymentsHistory({required this.schoolId, required this.accent});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final q = db
        .collection('schools')
        .doc(schoolId)
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .limit(15);

    String statusLabel(String raw) {
      switch (raw) {
        case 'verified':
          return 'Verificado';
        case 'rejected':
          return 'Rechazado';
        default:
          return 'Pendiente';
      }
    }

    return _Card(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LeadingIconBubble(color: accent, icon: Icons.history),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Historial (últimos reportes)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: LinearProgressIndicator(),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(
                  'Aún no hay pagos reportados.',
                  style: TextStyle(color: Colors.grey.shade700),
                );
              }

              return Column(
                children: docs.map((d) {
                  final m = d.data();
                  final method = (m['method'] ?? '—').toString();
                  final status = (m['status'] ?? 'submitted').toString();
                  final amount = m['amount'];
                  final currency = (m['currency'] ?? '').toString();
                  final ref = (m['reference'] ?? '').toString().trim();

                  DateTime? dt;
                  final createdAt = m['createdAt'];
                  if (createdAt is Timestamp) dt = createdAt.toDate();

                  Color badgeColor;
                  switch (status) {
                    case 'verified':
                      badgeColor = Colors.green;
                      break;
                    case 'rejected':
                      badgeColor = Colors.red;
                      break;
                    default:
                      badgeColor = Colors.orange;
                  }

                  final amountText = (amount is num)
                      ? '${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)} ${currency.isEmpty ? '' : currency}'
                      : '';

                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withOpacity(0.10)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.receipt_outlined, color: badgeColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$method${amountText.isEmpty ? '' : ' • $amountText'}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${dt == null ? '' : '${dt.day}/${dt.month}/${dt.year} • '}'
                                '${ref.isEmpty ? 'Sin referencia' : 'Ref: $ref'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade700, height: 1.2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusChip(
                          label: statusLabel(status),
                          color: badgeColor,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportPaymentDialog extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final String currency;
  final String suggestedAmount;

  const _ReportPaymentDialog({
    required this.schoolId,
    required this.schoolName,
    required this.currency,
    required this.suggestedAmount,
  });

  @override
  State<_ReportPaymentDialog> createState() => _ReportPaymentDialogState();
}

class _ReportPaymentDialogState extends State<_ReportPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _method = 'PayPal';
  DateTime _paidAt = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.suggestedAmount;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (res != null) setState(() => _paidAt = res);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText.replaceAll(',', '.'));

    if (amount == null || amount <= 0) {
      _toast('Escribe un monto válido.');
      return;
    }
    if (_refCtrl.text.trim().isEmpty) {
      _toast('Escribe una referencia / ID de transacción.');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final email = (user?.email ?? '').trim();

      final db = FirebaseFirestore.instance;

      await db.collection('schools').doc(widget.schoolId).collection('payments').add({
        'createdAt': FieldValue.serverTimestamp(),
        'paidAt': Timestamp.fromDate(_paidAt),
        'method': _method,
        'amount': amount,
        'currency': widget.currency,
        'reference': _refCtrl.text.trim(),
        'note': _noteCtrl.text.trim(),
        'status': 'submitted',
        'submittedByUid': uid,
        'submittedByEmail': email,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('No se pudo reportar el pago: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final fill = const Color(0xFFF4F7FB);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Reportar pago — ${widget.schoolName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _method,
              decoration: InputDecoration(
                labelText: 'Método',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: fill,
              ),
              items: const [
                DropdownMenuItem(value: 'PayPal', child: Text('PayPal')),
                DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia bancaria')),
                DropdownMenuItem(value: 'Otro', child: Text('Otro')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'PayPal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Monto (${widget.currency})',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: fill,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: 'Referencia / ID transacción',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: fill,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fecha de pago',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: fill,
                ),
                child: Row(
                  children: [
                    Icon(Icons.event, color: azul),
                    const SizedBox(width: 10),
                    Text('${_paidAt.day}/${_paidAt.month}/${_paidAt.year}'),
                    const Spacer(),
                    Icon(Icons.edit_calendar, color: azul),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Nota (opcional)',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: fill,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: azul,
            foregroundColor: Colors.white, // ✅ CONTRASTE
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Guardando...' : 'Enviar'),
        ),
      ],
    );
  }
}

class _BankAccountsList extends StatelessWidget {
  final List<Map<String, dynamic>> accounts;
  final Future<void> Function(String label, String value) onCopy;
  final Color accent;

  const _BankAccountsList({
    required this.accounts,
    required this.onCopy,
    required this.accent,
  });

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(fontSize: 12.8, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: accounts.asMap().entries.map((entry) {
        final i = entry.key;
        final a = entry.value;

        final bankName = (a['bankName'] ?? '').toString();
        final accountName = (a['accountName'] ?? '').toString();
        final accountNumber = (a['accountNumber'] ?? '').toString();
        final accountType = (a['accountType'] ?? '').toString();
        final idNumber = (a['idNumber'] ?? '').toString();
        final note = (a['note'] ?? '').toString();

        return Container(
          margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bankName.isEmpty ? 'Banco' : bankName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              _kv('Titular', accountName),
              _kv('Cuenta', accountNumber),
              _kv('Tipo', accountType),
              _kv('ID', idNumber),
              if (note.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    note,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, height: 1.2),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (accountNumber.trim().isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.35)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => onCopy('Cuenta', accountNumber),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar cuenta'),
                    ),
                  if (accountName.trim().isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.35)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => onCopy('Titular', accountName),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar titular'),
                    ),
                  if (bankName.trim().isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withOpacity(0.35)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => onCopy('Banco', bankName),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar banco'),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? extra;

  const _MethodTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeadingIconBubble(color: accent, icon: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade800, height: 1.25),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (extra != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: extra!),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final vColor = valueColor ?? Colors.black87;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13.5, height: 1.25),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: vColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _Card({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.10)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 10),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LeadingIconBubble extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _LeadingIconBubble({
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _SoftWarning extends StatelessWidget {
  final String title;
  final String message;
  final Color color;

  const _SoftWarning({
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13.2, height: 1.25),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(fontWeight: FontWeight.w900, color: color),
                  ),
                  TextSpan(
                    text: message,
                    style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
