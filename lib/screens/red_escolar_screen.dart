import 'package:edupro/widgets/team_access_gate.dart';
import 'package:edupro/widgets/school_catalog_view.dart';
import 'package:edupro/services/team_school_catalog_controller.dart';
import '../services/team_school_access_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:edupro/widgets/team_section_navigation.dart';

class RedEscolarScreen extends StatefulWidget {
  const RedEscolarScreen({super.key});

  @override
  State<RedEscolarScreen> createState() => _RedEscolarScreenState();
}

class _RedEscolarScreenState extends State<RedEscolarScreen> {
  static const LatLng _defaultCenter = LatLng(18.7357, -70.1627);
  static const Color _navy = Color(0xFF102A43);
  static const Color _blue = Color(0xFF1A237E);
  static const Color _gold = Color(0xFFF4B400);

  late TeamSchoolCatalogController _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog = TeamSchoolAccessService.sharedCatalog(
      role: TeamAccessRoleScope.of(context),
    );
    _catalog.ensureFresh();
  }

  String _clean(dynamic value) {
    return (value ?? '').toString().trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_clean(value));
  }

  LatLng? _extractPoint(Map<String, dynamic> data) {
    final locationRaw = data['location'];
    if (locationRaw is Map) {
      final location = Map<String, dynamic>.from(locationRaw);
      final lat =
          _toDouble(location['latitude']) ??
          _toDouble(location['lat']) ??
          _toDouble(location['y']);
      final lng =
          _toDouble(location['longitude']) ??
          _toDouble(location['lng']) ??
          _toDouble(location['lon']) ??
          _toDouble(location['x']);
      if (lat != null &&
          lng != null &&
          lat >= 17.3 &&
          lat <= 20.2 &&
          lng >= -72.1 &&
          lng <= -68.0) {
        return LatLng(lat, lng);
      }
    }

    final lat = _toDouble(data['latitude']) ?? _toDouble(data['lat']);
    final lng =
        _toDouble(data['longitude']) ??
        _toDouble(data['lng']) ??
        _toDouble(data['lon']);
    if (lat != null &&
        lng != null &&
        lat >= 17.3 &&
        lat <= 20.2 &&
        lng >= -72.1 &&
        lng <= -68.0) {
      return LatLng(lat, lng);
    }

    final geoRaw = data['geo'];
    if (geoRaw is Map) {
      final geo = Map<String, dynamic>.from(geoRaw);
      final geoLat = _toDouble(geo['latitude']) ?? _toDouble(geo['lat']);
      final geoLng =
          _toDouble(geo['longitude']) ??
          _toDouble(geo['lng']) ??
          _toDouble(geo['lon']);
      if (geoLat != null &&
          geoLng != null &&
          geoLat >= 17.3 &&
          geoLat <= 20.2 &&
          geoLng >= -72.1 &&
          geoLng <= -68.0) {
        return LatLng(geoLat, geoLng);
      }
    }

    return null;
  }

  _SchoolMapItem _schoolFromDoc(TeamSchoolRecord doc) {
    final data = doc.data();
    final locationRaw = data['location'];
    final location =
        locationRaw is Map
            ? Map<String, dynamic>.from(locationRaw)
            : <String, dynamic>{};
    final directPoint = _extractPoint(data);

    final name =
        _clean(data['officialName']).isNotEmpty
            ? _clean(data['officialName'])
            : (_clean(data['name']).isNotEmpty
                ? _clean(data['name'])
                : _clean(data['nombre']).isNotEmpty
                ? _clean(data['nombre'])
                : doc.id);

    final code =
        _clean(data['institutionCode']).isNotEmpty
            ? _clean(data['institutionCode'])
            : (_clean(data['code']).isNotEmpty ? _clean(data['code']) : doc.id);

    final addressLine = _clean(location['addressLine']);
    final sector = _clean(location['sector']);
    final municipality = _clean(location['municipality']);
    final province = _clean(location['province']);
    final country = _clean(data['country']);
    final status =
        _clean(data['accountStatus']).isNotEmpty
            ? _clean(data['accountStatus'])
            : ((data['active'] ?? true) == true ? 'activa' : 'suspendida');

    return _SchoolMapItem(
      id: doc.id,
      name: name,
      code: code,
      addressLine: addressLine,
      sector: sector,
      municipality: municipality,
      province: province,
      country: country,
      directPoint: directPoint,
      active: (data['active'] ?? true) == true,
      status: status,
    );
  }

  LatLng _centerFor(List<LatLng> points) {
    if (points.isEmpty) return _defaultCenter;
    final lat = points.fold<double>(0, (sum, point) => sum + point.latitude);
    final lon = points.fold<double>(0, (sum, point) => sum + point.longitude);
    return LatLng(lat / points.length, lon / points.length);
  }

  double _zoomFor(int pointCount) {
    if (pointCount <= 1) return 10.7;
    if (pointCount <= 3) return 8.6;
    if (pointCount <= 8) return 7.2;
    return 6.3;
  }

  String _locationLabel(_SchoolMapItem school) {
    final parts =
        <String>[
          school.addressLine,
          school.sector,
          school.municipality,
          school.province,
          school.country,
        ].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? 'Sin direccion registrada' : parts.join(', ');
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip({required bool active, required String label}) {
    final color = active ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _locationMarker({required bool active}) {
    final color = active ? _blue : Colors.grey.shade600;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 5),
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

  Widget _buildSchoolCard(_ResolvedSchoolItem item) {
    final point = item.point;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5ECFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.school.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Codigo: ${item.school.code}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _statusChip(
                active: item.school.active,
                label:
                    item.school.status.isNotEmpty
                        ? item.school.status
                        : (item.school.active ? 'Activa' : 'Suspendida'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _locationLabel(item.school),
            style: TextStyle(color: Colors.grey.shade800, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                point != null ? Icons.place_rounded : Icons.place_outlined,
                color: point != null ? _blue : Colors.grey.shade500,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  point == null
                      ? 'Ubicación pendiente: márcala desde Colegios'
                      : 'Lat ${point.latitude.toStringAsFixed(5)}, Lon ${point.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard(List<_ResolvedSchoolItem> schools) {
    final points =
        schools
            .where((item) => item.point != null)
            .map((item) => item.point!)
            .toList();
    final center = _centerFor(points);
    final zoom = _zoomFor(points.length);
    final markers =
        schools
            .where((item) => item.point != null)
            .map(
              (item) => Marker(
                point: item.point!,
                width: 44,
                height: 44,
                child: Tooltip(
                  message: item.school.name,
                  child: _locationMarker(active: item.school.active),
                ),
              ),
            )
            .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5ECFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.public_rounded, color: _navy),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mapa de escuelas registradas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Las escuelas con coordenadas aparecen marcadas en el mapa.',
                      style: TextStyle(height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 520,
              child: Stack(
                children: [
                  FlutterMap(
                    key: ValueKey(
                      points
                          .map((p) => '${p.latitude},${p.longitude}')
                          .join(';'),
                    ),
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: zoom,
                      initialCameraFit:
                          points.length > 1
                              ? CameraFit.coordinates(
                                coordinates: points,
                                padding: const EdgeInsets.all(70),
                                maxZoom: 13,
                              )
                              : null,
                      minZoom: 3.5,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.valmich.edupro',
                      ),
                      if (markers.isNotEmpty) MarkerLayer(markers: markers),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                  if (markers.isEmpty)
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xCCFFFFFF),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_outlined, size: 52, color: _navy),
                              SizedBox(height: 12),
                              Text(
                                'Aun no hay coordenadas para dibujar marcadores.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Marca la ubicación exacta de cada colegio desde Colegios para verla aquí.',
                                textAlign: TextAlign.center,
                                style: TextStyle(height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int total, int withPoint, int withoutPoint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F1B4D), Color(0xFF1A237E), Color(0xFF2C4DA3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Red Escolar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ubicacion de escuelas registradas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Vista geográfica de los colegios de EduPro con ubicación exacta registrada.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricCard(
                label: 'Escuelas',
                value: '$total',
                icon: Icons.school_rounded,
                color: Colors.white,
              ),
              _metricCard(
                label: 'Con ubicacion',
                value: '$withPoint',
                icon: Icons.place_rounded,
                color: _gold,
              ),
              _metricCard(
                label: 'Sin ubicacion',
                value: '$withoutPoint',
                icon: Icons.place_outlined,
                color: Colors.orangeAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5ECFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.public_rounded, color: _blue, size: 38),
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay colegios en estos resultados',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba otra búsqueda o provincia. Los colegios con ubicación registrada aparecerán en el mapa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolvedBody(List<_ResolvedSchoolItem> schools) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final content = <Widget>[
          _buildHeader(
            _catalog.metrics?.total ?? 0,
            _catalog.metrics?.located ?? 0,
            _catalog.metrics?.unlocated ?? 0,
          ),
          Text(
            'El mapa muestra los colegios de esta página. Busca o filtra por provincia para localizar otros.',
          ),
          const SizedBox(height: 18),
          schools.isEmpty ? _buildEmptyState() : _buildMapCard(schools),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5ECFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detalle de escuelas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Las tarjetas ayudan a revisar rapidamente que escuelas ya tienen ubicacion visible.',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 16),
                ...schools.map(_buildSchoolCard),
              ],
            ),
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1260 : 980),
              child: Column(children: content),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        leading: TeamSectionNavigation.backButton(context, color: Colors.white),
        title: const Text('Red Escolar'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SchoolCatalogView(
        controller: _catalog,
        builder: (context) {
          final schools =
              _catalog.records.map(_schoolFromDoc).toList()..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

          return _buildResolvedBody([
            for (final school in schools)
              _ResolvedSchoolItem(school: school, point: school.directPoint),
          ]);
        },
      ),
    );
  }
}

class _SchoolMapItem {
  final String id;
  final String name;
  final String code;
  final String addressLine;
  final String sector;
  final String municipality;
  final String province;
  final String country;
  final LatLng? directPoint;
  final bool active;
  final String status;

  const _SchoolMapItem({
    required this.id,
    required this.name,
    required this.code,
    required this.addressLine,
    required this.sector,
    required this.municipality,
    required this.province,
    required this.country,
    required this.directPoint,
    required this.active,
    required this.status,
  });
}

class _ResolvedSchoolItem {
  final _SchoolMapItem school;
  final LatLng? point;

  const _ResolvedSchoolItem({required this.school, required this.point});
}
