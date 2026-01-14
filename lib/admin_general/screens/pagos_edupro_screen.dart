// lib/admin_general/screens/pagos_edupro_screen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PagosEduProScreen extends StatefulWidget {
  const PagosEduProScreen({super.key});

  @override
  State<PagosEduProScreen> createState() => _PagosEduProScreenState();
}

class _PagosEduProScreenState extends State<PagosEduProScreen> {
  final _db = FirebaseFirestore.instance;

  static DateTime _addMonthsClamped(DateTime dt, int months) {
    final target = DateTime(dt.year, dt.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = min(dt.day, lastDay);
    return DateTime(target.year, target.month, day, dt.hour, dt.minute, dt.second);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _isSuperAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final d = await _db.collection('superadmins').doc(uid).get();
    return (d.data()?['active'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);

    final pendingQ = _db
        .collectionGroup('payments')
        .where('status', isEqualTo: 'submitted')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos EduPro — Verificación'),
        backgroundColor: azul,
      ),
      body: FutureBuilder<bool>(
        future: _isSuperAdmin(),
        builder: (context, snapAdmin) {
          if (!snapAdmin.hasData) return const Center(child: CircularProgressIndicator());
          if (snapAdmin.data != true) {
            return const Center(child: Text('Acceso denegado (no eres superadmin).'));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: pendingQ.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No hay pagos pendientes.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final m = doc.data();

                  final schoolRef = doc.reference.parent.parent; // schools/{schoolId}
                  final schoolId = schoolRef?.id ?? '—';

                  final method = (m['method'] ?? '—').toString();
                  final amount = m['amount'];
                  final currency = (m['currency'] ?? 'USD').toString();
                  final reference = (m['reference'] ?? '').toString();
                  final byEmail = (m['submittedByEmail'] ?? '').toString();

                  return Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Colegio: $schoolId',
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text('Método: $method'),
                          Text('Monto: ${amount is num ? amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2) : amount} $currency'),
                          Text('Referencia: $reference'),
                          if (byEmail.trim().isNotEmpty) Text('Reportado por: $byEmail'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    // Rechazar
                                    await doc.reference.update({
                                      'status': 'rejected',
                                      'verifiedAt': FieldValue.serverTimestamp(),
                                      'verifiedByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
                                      'verifiedByEmail': FirebaseAuth.instance.currentUser?.email ?? '',
                                    });
                                    _toast('Pago rechazado.');
                                  },
                                  child: const Text('Rechazar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    // Verificar + mover fechas en schools/{schoolId}
                                    final schoolDoc = await schoolRef!.get();
                                    final data = schoolDoc.data() as Map<String, dynamic>? ?? {};

                                    final dueAt = (data['billingNextDueAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                    final next = _addMonthsClamped(dueAt, 1);

                                    final batch = _db.batch();
                                    batch.update(doc.reference, {
                                      'status': 'verified',
                                      'verifiedAt': FieldValue.serverTimestamp(),
                                      'verifiedByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
                                      'verifiedByEmail': FirebaseAuth.instance.currentUser?.email ?? '',
                                    });

                                    batch.update(schoolRef, {
                                      'billingLastPaidAt': FieldValue.serverTimestamp(),
                                      'billingNextDueAt': Timestamp.fromDate(next),
                                    });

                                    await batch.commit();
                                    _toast('Pago verificado y próxima fecha actualizada.');
                                  },
                                  child: const Text('Verificar'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
