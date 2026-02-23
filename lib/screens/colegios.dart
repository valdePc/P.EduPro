import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ColegiosScreen extends StatelessWidget {
  const ColegiosScreen({Key? key}) : super(key: key);

  static const String _adminPrefix = 'eduproapp_admin_';

  Stream<QuerySnapshot<Map<String, dynamic>>> _schoolsStream() {
    return FirebaseFirestore.instance.collection('schools').snapshots();
  }

  String _normalizeCode(String value) {
    final v = value.trim();
    if (v.startsWith(_adminPrefix)) {
      return v.substring(_adminPrefix.length);
    }
    return v;
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final yyyy = d.year.toString();
      return '$dd/$mm/$yyyy';
    }
    return '—';
  }

  Future<void> _crearAdminDoc({
    required BuildContext context,
    required String schoolCode, // doc.id del colegio seleccionado (ej: QICMY6Q5)
    required String email,
  }) async {
    final emailLower = email.trim().toLowerCase();

    if (emailLower.isEmpty || !emailLower.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo inválido')),
      );
      return;
    }

    // ✅ Siempre trabajamos con el código limpio (sin prefijo)
    final code = _normalizeCode(schoolCode);

    // ✅ Doc interno requerido por tu estructura:
    final adminDocId = '$_adminPrefix$code';

    final schools = FirebaseFirestore.instance.collection('schools');
    final baseRef = schools.doc(code); // doc base (QICMY6Q5)
    final adminRef = schools.doc(adminDocId); // doc enlace (eduproapp_admin_QICMY6Q5)

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final baseSnap = await tx.get(baseRef);
        final baseData = baseSnap.data();

        final name = baseData?['name'];
        final nombre = baseData?['nombre'];

        final adminSnap = await tx.get(adminRef);
        tx.set(
          adminRef,
          {
            'adminEmail': emailLower,
            'active': true,
            'schoolCode': code,
            'updatedAt': FieldValue.serverTimestamp(),
            if (!adminSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
            if (name != null) 'name': name,
            if (nombre != null) 'nombre': nombre,
          },
          SetOptions(merge: true),
        );

        tx.set(
          baseRef,
          {
            'adminEmail': emailLower,
            'active': true,
            'schoolCode': code,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Admin asignado al colegio $code')),
      );
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error Firestore: ${e.code}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _mostrarDialogCorreo(
    BuildContext context,
    String schoolCode,
  ) {
    String correo = '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Asignar admin a $schoolCode'),
        content: TextField(
          decoration: const InputDecoration(
            labelText: 'Correo administrador',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => correo = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _crearAdminDoc(
                context: context,
                schoolCode: schoolCode,
                email: correo,
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colegios'),
        // ✅ Botón para salir / regresar atrás
leading: IconButton(
  icon: const Icon(Icons.arrow_back),
  tooltip: 'Atrás',
  onPressed: () => Navigator.pushReplacementNamed(context, '/panel'),
),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _schoolsStream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // ✅ Ocultamos docs internos eduproapp_admin_* para NO duplicar widgets
          final docs = snap.data!.docs
              .where((d) => !d.id.startsWith(_adminPrefix))
              .toList();

          if (docs.isEmpty) {
            return const Center(child: Text('No hay colegios'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              // Código limpio del colegio
              final schoolCode = (data['schoolCode'] ?? doc.id).toString();

              final name =
                  (data['name'] ?? data['nombre'] ?? '').toString();

              // ✅ Nuevo: correo admin visible en el widget
              final adminEmail = (data['adminEmail'] ?? '').toString();

              // ✅ Nuevo: fecha creación visible en el widget
              final createdAtText = _formatDate(data['createdAt']);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // ✅ Mostramos código + correo + fecha creación
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Código: $schoolCode'),
                      Text(
                        'Admin: ${adminEmail.isEmpty ? '—' : adminEmail}',
                      ),
                      Text('Creado: $createdAtText'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.email),
                    onPressed: () => _mostrarDialogCorreo(context, schoolCode),
                    tooltip: 'Asignar correo admin',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}