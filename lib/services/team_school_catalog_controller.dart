import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/team_school_catalog.dart';

typedef CatalogFetcher =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> query);

/// Session-scoped, bounded shared cache. Pages are fetched only on demand.
class TeamSchoolCatalogController extends ChangeNotifier {
  TeamSchoolCatalogController({
    required this.fetch,
    required this.currentUid,
    required this.sessionUid,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final CatalogFetcher fetch;
  final String? Function() currentUid;
  final String sessionUid;
  final DateTime Function() _now;
  static const ttl = Duration(minutes: 2);
  final _cache = <int, _CachedCatalogPage>{};
  final _cursors = <int, String?>{0: null};
  Timer? _debounce;
  int _generation = 0, _attemptedPage = 0;
  bool _disposed = false;
  bool _ensureScheduled = false;
  DateTime? _metricsAt, _pageAt;
  List<TeamSchoolRecord> records = const [];
  SchoolCatalogMetrics? metrics;
  Object? error;
  String search = '', province = '', role = '';
  int pageIndex = 0;
  int? matchingTotal;
  String? nextCursor;
  bool loading = false;
  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => nextCursor != null;

  void ensureFresh() {
    if (_disposed || loading || _ensureScheduled) return;
    if (_pageAt == null ||
        _now().difference(_pageAt!) >= ttl ||
        error != null) {
      _ensureScheduled = true;
      scheduleMicrotask(() {
        _ensureScheduled = false;
        if (!_disposed && !loading) unawaited(_load(0, force: true));
      });
    }
  }

  void invalidateSession() {
    ++_generation;
    _debounce?.cancel();
    _cache.clear();
    records = const [];
    metrics = null;
    matchingTotal = null;
    _pageAt = _metricsAt = null;
    role = '';
    loading = false;
    error = StateError('La sesión ha cambiado.');
    if (!_disposed) notifyListeners();
  }

  void setSearch(String value) {
    if (search == value) return;
    search = value;
    _resetQuery();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(0, force: true),
    );
  }

  void setProvince(String value) {
    if (province == value) return;
    province = value;
    _resetQuery();
    unawaited(_load(0, force: true));
  }

  void _resetQuery() {
    ++_generation;
    _debounce?.cancel();
    _cache.clear();
    _cursors
      ..clear()
      ..[0] = null;
    pageIndex = _attemptedPage = 0;
    matchingTotal = null;
    nextCursor = null;
    records = const [];
    error = null;
    loading = true;
    notifyListeners();
  }

  Future<void> next() async {
    if (loading || !hasNext) return;
    _cursors[pageIndex + 1] = nextCursor;
    await _load(pageIndex + 1);
  }

  Future<void> previous() async {
    if (loading || !hasPrevious) return;
    await _load(pageIndex - 1);
  }

  Future<void> retry() => _load(_attemptedPage, force: true);

  Future<void> refresh() async {
    _resetQuery();
    _metricsAt = null;
    await _load(0, force: true);
  }

  Future<void> _load(int index, {bool force = false}) async {
    if (_disposed) return;
    if (currentUid() != sessionUid) {
      invalidateSession();
      return;
    }
    final generation = ++_generation;
    _attemptedPage = index;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final cached = force ? null : _cache.remove(index);
      final fresh = cached != null && _now().difference(cached.at) < ttl;
      final includeMetrics =
          metrics == null ||
          _metricsAt == null ||
          _now().difference(_metricsAt!) >= ttl;
      final fromCache = fresh && !includeMetrics;
      final page =
          fromCache
              ? cached.page
              : SchoolCatalogPage.fromMap(
                await fetch({
                  'limit': 25,
                  'search': search.trim(),
                  'province': province,
                  if (_cursors[index] != null) 'cursor': _cursors[index],
                  'includeMetrics': includeMetrics,
                  'includeTotal': index == 0 || matchingTotal == null,
                }).timeout(const Duration(seconds: 30)),
              );
      if (_disposed || generation != _generation) return;
      if (currentUid() != sessionUid) {
        invalidateSession();
        return;
      }
      if (role.isNotEmpty && page.role != role) {
        _cache.clear();
        metrics = null;
        matchingTotal = null;
        role = page.role;
        await refresh();
        return;
      }
      if (!fromCache && includeMetrics && page.metrics == null ||
          (index == 0 || matchingTotal == null) && page.matchingTotal == null) {
        throw const FormatException('Respuesta de catálogo incompleta.');
      }
      if (page.nextCursor != null &&
          _cursors.entries
              .where((entry) => entry.key <= index)
              .map((entry) => entry.value)
              .contains(page.nextCursor)) {
        throw const FormatException('La página no avanza.');
      }
      if (role.isNotEmpty && role != page.role) _cache.clear();
      role = page.role;
      records = page.records;
      nextCursor = page.nextCursor;
      pageIndex = index;
      matchingTotal = page.matchingTotal ?? matchingTotal;
      if (page.metrics != null) {
        metrics = page.metrics;
        _metricsAt = _now();
      }
      _pageAt = fromCache ? cached.at : _now();
      _cache[index] = _CachedCatalogPage(page, _pageAt!);
      while (_cache.length > 5) {
        _cache.remove(_cache.keys.first);
      }
      error = null;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      if (currentUid() != sessionUid) {
        invalidateSession();
        return;
      }
      records = const [];
      _cache.clear();
      metrics = null;
      matchingTotal = null;
      _metricsAt = null;
      error = failure;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _cache.clear();
    records = const [];
    metrics = null;
    super.dispose();
  }
}

class _CachedCatalogPage {
  const _CachedCatalogPage(this.page, this.at);
  final SchoolCatalogPage page;
  final DateTime at;
}
