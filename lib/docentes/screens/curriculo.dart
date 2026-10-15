import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';

import 'package:edupro/data/curriculo_base_docs.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class CurriculoScreen extends StatelessWidget {
  final Escuela escuela;
  const CurriculoScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);
  static const Color accentColor = Color(0xFFFFA000);
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> _openPdf(BuildContext context, String url) async {
    final raw = url.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este documento aun no tiene URL configurado.')),
      );
      return;
    }

    String resolvedUrl = raw;
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      try {
        resolvedUrl = await _storage.ref().child(raw).getDownloadURL();
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo resolver el documento en Storage.')),
        );
        return;
      }
    }

    final uri = safeExternalDocumentUri(resolvedUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL de documento invalido.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el documento.')),
      );
    }
  }

  Widget _buildList(
    BuildContext context,
    List<Map<String, dynamic>> docs, {
    bool fallback = false,
  }) {
    if (docs.isEmpty) {
      return const Center(
        child: Text(
          'No hay documentos de curriculo para esta escuela.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        if (fallback)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: const Text(
              'Curricular de la Republica Dominicana.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final m = docs[i];
              final title = (m['title'] ?? 'Documento').toString();
              final category = (m['category'] ?? 'General').toString();
              final url = (m['url'] ?? '').toString();

              return Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: accentColor),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(category),
                  trailing: IconButton(
                    tooltip: 'Abrir PDF',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openPdf(context, url),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = normalizeSchoolIdFromEscuela(escuela);
    final docsStream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('curriculo_docs')
        .orderBy('order')
        .snapshots();

    return Scaffold(
      appBar: buildDocenteBackAppBar(context),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: docsStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error cargando curriculo: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs.where((d) {
            final active = d.data()['active'];
            return active is bool ? active : true;
          }).map((d) => d.data()).toList();

          if (docs.isNotEmpty) {
            return _buildList(context, docs);
          }

          final fallbackDocs = kCurriculoBaseDocs
              .map((e) => <String, dynamic>{
                    'title': e['title'] ?? '',
                    'category': e['category'] ?? '',
                    'url': e['url'] ?? '',
                  })
              .toList();

          return _buildList(context, fallbackDocs, fallback: true);
        },
      ),
    );
  }
}
