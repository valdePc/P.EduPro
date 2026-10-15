import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/admin_escolar/services/competencias_service.dart';

class CompetenciasPanel extends StatefulWidget {
  final String sid;
  final String subjectDocId;
  final CompetenciasService? service;

  const CompetenciasPanel({
    super.key,
    required this.sid,
    required this.subjectDocId,
    CompetenciasService? service,
  }) : service = service;

  @override
  State<CompetenciasPanel> createState() => _CompetenciasPanelState();
}

class _CompetenciasPanelState extends State<CompetenciasPanel> {
  late final CompetenciasService _defaultService = CompetenciasService();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    _updateStream();
  }

  @override
  void didUpdateWidget(covariant CompetenciasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sid != widget.sid ||
        oldWidget.subjectDocId != widget.subjectDocId ||
        oldWidget.service != widget.service) {
      _updateStream();
    }
  }

  void _updateStream() {
    _stream =
        widget.sid.trim().isEmpty || widget.subjectDocId.trim().isEmpty
            ? null
            : (widget.service ?? _defaultService).streamCompetencias(
              widget.sid,
              widget.subjectDocId,
            );
  }

  @override
  Widget build(BuildContext context) {
    if (_stream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Text('Error cargando competencias');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          );
        }

        final docs = snap.data!.docs;
        final items =
            docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .where((x) => x['active'] == true)
                .toList();

        if (items.isEmpty) {
          return const Text(
            'Esta asignatura aún no tiene competencias configuradas.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Competencias',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map((c) {
              final title = (c['title'] ?? '').toString().trim();
              final desc = (c['description'] ?? '').toString().trim();
              return Card(
                child: ListTile(
                  title: Text(title.isEmpty ? '(Sin título)' : title),
                  subtitle: desc.isEmpty ? null : Text(desc),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }
}
