import 'dart:math';

import 'package:flutter/material.dart';

import '../data/dominican_locations.dart';
import '../services/team_school_catalog_controller.dart';

class SchoolCatalogControls extends StatefulWidget {
  const SchoolCatalogControls({super.key, required this.controller});
  final TeamSchoolCatalogController controller;
  @override
  State<SchoolCatalogControls> createState() => _SchoolCatalogControlsState();
}

class _SchoolCatalogControlsState extends State<SchoolCatalogControls> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.search,
  );
  @override
  void didUpdateWidget(SchoolCatalogControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.controller.search) {
      _search.text = widget.controller.search;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final catalog = widget.controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: min(320, bounds.maxWidth),
                child: TextField(
                  controller: _search,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Buscar colegio o código',
                    helperText: 'Inicio del nombre, palabra o código',
                    counterText: '',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: catalog.setSearch,
                ),
              ),
              if (catalog.role.isNotEmpty && catalog.role != 'billing_admin')
                SizedBox(
                  width: min(240, bounds.maxWidth),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(catalog.province),
                    initialValue: catalog.province,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Provincia',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Todas las provincias'),
                      ),
                      for (final province
                          in dominicanMunicipalitiesByProvince.keys)
                        DropdownMenuItem(
                          value: province,
                          child: Text(
                            province,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => catalog.setProvince(value ?? ''),
                  ),
                ),
              IconButton(
                tooltip: 'Actualizar catálogo e indicadores',
                onPressed: catalog.loading ? null : catalog.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Página ${catalog.pageIndex + 1} · ${catalog.records.length} de ${catalog.matchingTotal ?? '…'} resultados',
              ),
              TextButton.icon(
                onPressed:
                    catalog.loading || !catalog.hasPrevious
                        ? null
                        : catalog.previous,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Anterior'),
              ),
              TextButton.icon(
                onPressed:
                    catalog.loading || !catalog.hasNext ? null : catalog.next,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Siguiente'),
              ),
            ],
          ),
          if (catalog.loading)
            const LinearProgressIndicator(semanticsLabel: 'Cargando catálogo'),
        ],
      );
    },
  );
}

class SchoolCatalogStatus extends StatelessWidget {
  const SchoolCatalogStatus({
    super.key,
    required this.controller,
    required this.child,
  });
  final TeamSchoolCatalogController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (controller.error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudo cargar el catálogo. Revisa tu conexión o sesión e intenta nuevamente.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.loading ? null : controller.retry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (controller.loading && controller.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Cargando colegios'),
      );
    }
    return child;
  }
}

class SchoolCatalogView extends StatelessWidget {
  const SchoolCatalogView({
    super.key,
    required this.controller,
    required this.builder,
  });
  final TeamSchoolCatalogController controller;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => Column(
          children: [
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .4,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SchoolCatalogControls(controller: controller),
                ),
              ),
            ),
            Expanded(
              child: SchoolCatalogStatus(
                controller: controller,
                child: builder(context),
              ),
            ),
          ],
        ),
  );
}
