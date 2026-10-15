import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edupro/utils/safe_external_uri.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ACalendarioAcademico extends StatefulWidget {
  final Escuela escuela;
  final VoidCallback? onBack;

  const ACalendarioAcademico({
    Key? key,
    required this.escuela,
    this.onBack,
  }) : super(key: key);

  @override
  State<ACalendarioAcademico> createState() => _ACalendarioAcademicoState();
}

class _ACalendarioAcademicoState extends State<ACalendarioAcademico> {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  late Future<_CalendarFilesState> _filesFuture;

  String get _schoolId => normalizeSchoolIdFromEscuela(widget.escuela);

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadCalendarFiles();
  }

  Future<_CalendarFilesState> _loadCalendarFiles() async {
    final candidatePaths = <String>[
      'schools/$_schoolId/calendario',
      '$_schoolId/calendario',
      'calendario',
    ];

    FirebaseException? lastStorageError;

    for (final path in candidatePaths) {
      try {
        final result = await _storage.ref().child(path).listAll();
        if (result.items.isEmpty) continue;

        final files = (await Future.wait(result.items.map(_readCalendarFile)))
            .where((file) =>
                file.name.toLowerCase().endsWith('.pdf') ||
                file.contentType.toLowerCase().contains('pdf'))
            .toList();
        if (files.isEmpty) continue;
        files.sort((a, b) {
          final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final byDate = bDate.compareTo(aDate);
          if (byDate != 0) return byDate;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return _CalendarFilesState(
          sourcePath: path,
          searchedPaths: candidatePaths,
          files: files,
        );
      } on FirebaseException catch (e) {
        lastStorageError = e;
      }
    }

    if (lastStorageError != null) throw lastStorageError;

    return _CalendarFilesState(
      sourcePath: null,
      searchedPaths: candidatePaths,
      files: const [],
    );
  }

  Future<_CalendarFile> _readCalendarFile(Reference ref) async {
    FullMetadata? metadata;
    String downloadUrl = '';

    try {
      metadata = await ref.getMetadata();
    } catch (_) {}

    try {
      downloadUrl = await ref.getDownloadURL();
    } catch (_) {}

    return _CalendarFile(
      name: ref.name,
      fullPath: ref.fullPath,
      sizeBytes: metadata?.size ?? 0,
      contentType: (metadata?.contentType ?? '').trim(),
      updatedAt: metadata?.updated,
      downloadUrl: downloadUrl,
    );
  }

  Future<void> _refresh() async {
    final future = _loadCalendarFiles();
    setState(() => _filesFuture = future);
    await future;
  }

  Future<void> _openFile(_CalendarFile file) async {
    if (file.downloadUrl.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la URL del archivo.')),
      );
      return;
    }

    final uri = safeExternalDocumentUri(file.downloadUrl);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La URL del archivo no es valida.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo.')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Sin dato';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final decimals = size >= 10 || unitIndex == 0 ? 0 : 2;
    return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    return DateFormat('dd/MM/yyyy hh:mm a').format(value.toLocal());
  }

  Widget _buildEmptyState(_CalendarFilesState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.blueGrey.withOpacity(0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, size: 52, color: Color(0xFF0D47A1)),
                  const SizedBox(height: 14),
                  const Text(
                    'No hay archivos cargados para el calendario academico.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Se busco en estas rutas de Storage:\n${state.searchedPaths.join('\n')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.45,
                      color: Colors.blueGrey.shade700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.red.withOpacity(0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 52, color: Colors.redAccent),
                  const SizedBox(height: 14),
                  const Text(
                    'No se pudo cargar el archivo del calendario academico.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Intentar de nuevo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileTile(_CalendarFile file, {bool highlight = false}) {
    final borderColor = highlight
        ? const Color(0xFF0D47A1).withOpacity(0.22)
        : Colors.blueGrey.withOpacity(0.16);

    final background = highlight ? const Color(0xFFEFF5FF) : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        final iconBox = Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF0D47A1).withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            color: Color(0xFF0D47A1),
            size: 28,
          ),
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.name,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              file.fullPath,
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetaChip(icon: Icons.straighten, label: _formatBytes(file.sizeBytes)),
                _MetaChip(
                  icon: Icons.update_outlined,
                  label: _formatDate(file.updatedAt),
                ),
                _MetaChip(
                  icon: Icons.description_outlined,
                  label: file.contentType.isEmpty ? 'application/pdf' : file.contentType,
                ),
              ],
            ),
          ],
        );

        final action = FilledButton.icon(
          onPressed: () => _openFile(file),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir'),
        );

        return Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(18),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(height: 14),
                    info,
                    const SizedBox(height: 14),
                    action,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: 16),
                    Expanded(child: info),
                    const SizedBox(width: 12),
                    action,
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AdminBackButton(onBack: widget.onBack),
        title: const Text('Calendario Academico'),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_CalendarFilesState>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final state = snapshot.data!;
          if (state.files.isEmpty) {
            return _buildEmptyState(state);
          }

          final latest = state.files.first;
          final olderFiles = state.files.skip(1).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Archivo actual del calendario',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.sourcePath == null
                            ? 'Mostrando archivos encontrados en Storage.'
                            : 'Carpeta detectada: ${state.sourcePath}',
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFileTile(latest, highlight: true),
                      if (olderFiles.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Otros archivos cargados',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ...olderFiles.map((file) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildFileTile(file),
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CalendarFilesState {
  final String? sourcePath;
  final List<String> searchedPaths;
  final List<_CalendarFile> files;

  const _CalendarFilesState({
    required this.sourcePath,
    required this.searchedPaths,
    required this.files,
  });
}

class _CalendarFile {
  final String name;
  final String fullPath;
  final int sizeBytes;
  final String contentType;
  final DateTime? updatedAt;
  final String downloadUrl;

  const _CalendarFile({
    required this.name,
    required this.fullPath,
    required this.sizeBytes,
    required this.contentType,
    required this.updatedAt,
    required this.downloadUrl,
  });
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey.shade700),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
