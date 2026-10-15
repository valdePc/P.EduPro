import 'dart:collection';

import 'package:flutter/material.dart';

/// Memory-only cache, bounded and separated by session/role/school keys.
class SchoolSummaryCache {
  final int maximumEntries;
  final Duration lifetime;
  final DateTime Function() now;
  final _entries =
      LinkedHashMap<
        String,
        ({DateTime at, Future<Map<String, dynamic>> future})
      >();

  SchoolSummaryCache({
    this.maximumEntries = 20,
    this.lifetime = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : assert(maximumEntries > 0),
       now = now ?? DateTime.now;

  Future<Map<String, dynamic>> get(
    String key,
    Future<Map<String, dynamic>> Function() load,
  ) {
    final previous = _entries.remove(key);
    if (previous != null && now().difference(previous.at) < lifetime) {
      _entries[key] = previous;
      return previous.future;
    }
    final entry = (
      at: now(),
      future: Future<Map<String, dynamic>>.sync(
        load,
      ).timeout(const Duration(seconds: 30)),
    );
    _entries[key] = entry;
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
    return entry.future;
  }

  void invalidate(String key) => _entries.remove(key);
  void clear() => _entries.clear();
}

class SchoolSummaryLoader extends StatefulWidget {
  final String cacheKey;
  final SchoolSummaryCache cache;
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(
    BuildContext context,
    AsyncSnapshot<Map<String, dynamic>> snapshot,
  )
  builder;

  const SchoolSummaryLoader({
    super.key,
    required this.cacheKey,
    required this.cache,
    required this.load,
    required this.builder,
  });

  @override
  State<SchoolSummaryLoader> createState() => _SchoolSummaryLoaderState();
}

class _SchoolSummaryLoaderState extends State<SchoolSummaryLoader> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.cache.get(widget.cacheKey, widget.load);
  }

  @override
  void didUpdateWidget(covariant SchoolSummaryLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cache != widget.cache)
      _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    key: ValueKey(_future),
    future: _future,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final pending =
          (snapshot.data?['metricsPending'] as List? ?? const []).isNotEmpty;
      final message = Semantics(
        liveRegion: true,
        child: Text(
          snapshot.hasError
              ? 'No se pudieron cargar los indicadores. Comprueba tu sesión y conexión y pulsa Reintentar.'
              : loading
              ? 'Cargando indicadores…'
              : pending
              ? 'Algunos indicadores se están calculando. Puedes actualizar el resumen en unos momentos.'
              : 'Resumen consultado. Actualiza para ver los cambios más recientes.',
          style:
              snapshot.hasError
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
        ),
      );
      final refresh = TextButton.icon(
        key: const ValueKey('school-summary-refresh'),
        onPressed:
            loading
                ? null
                : () {
                  widget.cache.invalidate(widget.cacheKey);
                  setState(_load);
                },
        icon: const Icon(Icons.refresh),
        label: Text(snapshot.hasError ? 'Reintentar' : 'Actualizar'),
      );
      return LayoutBuilder(
        builder:
            (context, constraints) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child:
                          constraints.maxWidth < 480
                              ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  message,
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: refresh,
                                  ),
                                ],
                              )
                              : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: message),
                                  const SizedBox(width: 8),
                                  refresh,
                                ],
                              ),
                    ),
                  ),
                ),
                Expanded(child: widget.builder(context, snapshot)),
              ],
            ),
      );
    },
  );
}
