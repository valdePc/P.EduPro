import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const LatLng _defaultSchoolMapCenter = LatLng(18.7357, -70.1627);

class SchoolLocationSelection {
  final double latitude;
  final double longitude;

  const SchoolLocationSelection({
    required this.latitude,
    required this.longitude,
  });
}

Future<SchoolLocationSelection?> showSchoolLocationPickerDialog(
  BuildContext context, {
  double? initialLatitude,
  double? initialLongitude,
}) {
  return showDialog<SchoolLocationSelection>(
    context: context,
    builder:
        (_) => _SchoolLocationPickerDialog(
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
        ),
  );
}

class SchoolLocationPreviewMap extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double height;

  const SchoolLocationPreviewMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        child: AbsorbPointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: 14.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.valmich.edupro',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 42,
                    height: 42,
                    child: const _SchoolMarker(),
                  ),
                ],
              ),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchoolLocationPickerDialog extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const _SchoolLocationPickerDialog({
    required this.initialLatitude,
    required this.initialLongitude,
  });

  @override
  State<_SchoolLocationPickerDialog> createState() =>
      _SchoolLocationPickerDialogState();
}

class _SchoolLocationPickerDialogState
    extends State<_SchoolLocationPickerDialog> {
  late LatLng? _selectedPoint;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
    } else {
      _selectedPoint = null;
    }
  }

  String _fmt(double value) => value.toStringAsFixed(6);

  bool _isInCountry(LatLng point) =>
      point.latitude >= 17.3 &&
      point.latitude <= 20.2 &&
      point.longitude >= -72.1 &&
      point.longitude <= -68.0;

  @override
  Widget build(BuildContext context) {
    final initialCenter = _selectedPoint ?? _defaultSchoolMapCenter;
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.42).clamp(
      190.0,
      380.0,
    );
    return AlertDialog(
      title: const Text('Ubicacion exacta del colegio'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Toca el mapa para fijar el punto exacto del colegio. '
                'Luego esa ubicacion quedara lista para el mapa general de crecimiento de EduPro.',
                style: TextStyle(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: mapHeight,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: _selectedPoint == null ? 8.2 : 15,
                      minZoom: 5,
                      maxZoom: 18,
                      onTap: (_, point) {
                        setState(() => _selectedPoint = point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.valmich.edupro',
                      ),
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              width: 48,
                              height: 48,
                              child: const _SchoolMarker(),
                            ),
                          ],
                        ),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD8E1FF)),
                ),
                child:
                    _selectedPoint == null
                        ? const Text(
                          'Aun no has seleccionado un punto. Toca el mapa para marcar la ubicacion.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        )
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isInCountry(_selectedPoint!))
                              Text(
                                'Selecciona un punto dentro de República Dominicana.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            const Text(
                              'Coordenadas seleccionadas',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Latitud: ${_fmt(_selectedPoint!.latitude)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Longitud: ${_fmt(_selectedPoint!.longitude)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => setState(() => _selectedPoint = null),
          child: const Text('Limpiar'),
        ),
        ElevatedButton.icon(
          onPressed:
              _selectedPoint == null || !_isInCountry(_selectedPoint!)
                  ? null
                  : () {
                    Navigator.pop(
                      context,
                      SchoolLocationSelection(
                        latitude: _selectedPoint!.latitude,
                        longitude: _selectedPoint!.longitude,
                      ),
                    );
                  },
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Usar ubicacion'),
        ),
      ],
    );
  }
}

class _SchoolMarker extends StatelessWidget {
  const _SchoolMarker();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A237E),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: const Icon(
          Icons.location_on_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
