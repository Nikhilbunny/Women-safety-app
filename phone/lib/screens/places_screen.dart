import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db.dart';
import '../geo.dart';
import '../places.dart';
import '../places_service.dart';
import '../tracking_service.dart';

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _Row {
  final Place place;
  final double meters;
  final double bearing;
  const _Row(this.place, this.meters, this.bearing);
}

class _PlacesScreenState extends State<PlacesScreen> {
  List<Place> _places = [];
  List<List<double>> _trail = [];
  double? _lat;
  double? _lng;
  PlaceKind? _filter;
  bool _loading = false;
  bool _mapView = false;
  String _note = '';
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _places = await AppDb.instance.places();
    _trail = await TrackingService.trail();
    final t = await AppDb.instance.getSetting('places_time');
    if (t != null) _updated = DateTime.fromMillisecondsSinceEpoch(int.parse(t));
    await _locate();
    if (!mounted) return;
    setState(() {});
    // Refresh quietly when the saved list is missing, a day old, or from another area.
    final stale = _updated == null || DateTime.now().difference(_updated!).inHours > 24;
    final moved = await _movedFarFromSaved();
    if (_lat != null && (_places.isEmpty || stale || moved)) {
      _refresh();
    } else if (_lat == null) {
      setState(() => _note = 'Your location is not available yet. Turn on GPS and tap Refresh.');
    }
  }

  Future<bool> _movedFarFromSaved() async {
    final la = double.tryParse(await AppDb.instance.getSetting('places_lat') ?? '');
    final ln = double.tryParse(await AppDb.instance.getSetting('places_lng') ?? '');
    if (la == null || ln == null || _lat == null || _lng == null) return false;
    return distanceMeters(_lat!, _lng!, la, ln) > 3000;
  }

  Future<void> _locate() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      _lat = p.latitude;
      _lng = p.longitude;
      return;
    } catch (_) {}
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) {
        _lat = p.latitude;
        _lng = p.longitude;
        return;
      }
    } catch (_) {}
    // Fall back to the centre of the last saved search.
    _lat = double.tryParse(await AppDb.instance.getSetting('places_lat') ?? '');
    _lng = double.tryParse(await AppDb.instance.getSetting('places_lng') ?? '');
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _note = '';
    });
    if (_lat == null) await _locate();
    if (_lat == null || _lng == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _note = 'Your location is not available. Turn on GPS and try again.';
        });
      }
      return;
    }
    try {
      final fresh = await PlacesService.fetch(_lat!, _lng!);
      _updated = DateTime.now();
      if (!mounted) return;
      setState(() {
        _places = fresh;
        _loading = false;
        _note = fresh.isEmpty ? 'Nothing found within 5 km in the map data.' : '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _note = _places.isEmpty
            ? 'No internet and nothing saved yet. Connect once to save places for offline use.'
            : 'No internet. Showing the places saved earlier.';
      });
    }
  }

  List<_Row> get _rows {
    final lat = _lat, lng = _lng;
    final rows = <_Row>[];
    for (final p in _places) {
      if (_filter != null && p.kind != _filter) continue;
      if (lat == null || lng == null) {
        rows.add(_Row(p, double.infinity, 0));
      } else {
        rows.add(_Row(p, distanceMeters(lat, lng, p.lat, p.lng), bearingDegrees(lat, lng, p.lat, p.lng)));
      }
    }
    rows.sort((a, b) => a.meters.compareTo(b.meters));
    return rows;
  }

  Future<void> _directions(Place p) async {
    final label = Uri.encodeComponent(p.name);
    final geo = Uri.parse('geo:${p.lat},${p.lng}?q=${p.lat},${p.lng}($label)');
    try {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _call(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    await launchUrl(Uri.parse('tel:$cleaned'));
  }

  Color _color(PlaceKind k) {
    switch (k) {
      case PlaceKind.hospital:
        return Colors.red.shade700;
      case PlaceKind.police:
        return Colors.indigo;
      case PlaceKind.exit:
        return Colors.green.shade700;
    }
  }

  IconData _icon(PlaceKind k) {
    switch (k) {
      case PlaceKind.hospital:
        return Icons.local_hospital;
      case PlaceKind.police:
        return Icons.local_police;
      case PlaceKind.exit:
        return Icons.exit_to_app;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby help'),
        actions: [
          IconButton(
            tooltip: _mapView ? 'Show list' : 'Show map',
            icon: Icon(_mapView ? Icons.list : Icons.map),
            onPressed: () => setState(() => _mapView = !_mapView),
          ),
          IconButton(
            tooltip: 'Refresh (needs internet)',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                for (final k in PlaceKind.values)
                  ChoiceChip(
                    label: Text(k == PlaceKind.hospital ? 'Hospitals' : k == PlaceKind.police ? 'Police' : 'Exits'),
                    selected: _filter == k,
                    onSelected: (_) => setState(() => _filter = k),
                  ),
              ],
            ),
          ),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_note, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_updated != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Saved ${_updated.toString().substring(0, 16)}. The list works offline.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _mapView ? _buildMap(rows) : _buildList(rows)),
        ],
      ),
    );
  }

  Widget _buildList(List<_Row> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nothing to show yet. Tap refresh when you have internet.'),
        ),
      );
    }
    return ListView.separated(
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == rows.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Data comes from OpenStreetMap contributors. Emergency exits are only listed where '
              'someone has mapped them, so many buildings will show none. Always follow the signs in the building.',
              style: TextStyle(fontSize: 12),
            ),
          );
        }
        final r = rows[i];
        final p = r.place;
        return ListTile(
          leading: Icon(_icon(p.kind), color: _color(p.kind)),
          title: Text(p.name),
          subtitle: Text(
            '${kindLabel(p.kind)}'
            '${r.meters.isFinite ? '  -  ${formatDistance(r.meters)} ${compass(r.bearing)}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.phone != null)
                IconButton(tooltip: 'Call', icon: const Icon(Icons.call), onPressed: () => _call(p.phone!)),
              IconButton(tooltip: 'Directions', icon: const Icon(Icons.directions), onPressed: () => _directions(p)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMap(List<_Row> rows) {
    final centre = LatLng(_lat ?? 20.5937, _lng ?? 78.9629);
    final markers = <Marker>[
      for (final r in rows)
        Marker(
          point: LatLng(r.place.lat, r.place.lng),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _directions(r.place),
            child: Icon(_icon(r.place.kind), color: _color(r.place.kind), size: 30),
          ),
        ),
      if (_lat != null && _lng != null)
        Marker(
          point: LatLng(_lat!, _lng!),
          width: 30,
          height: 30,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 26),
        ),
    ];
    final trailPoints = _trail.map((p) => LatLng(p[0], p[1])).toList();
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(initialCenter: centre, initialZoom: _lat == null ? 4.5 : 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.safetyapp',
            ),
            if (trailPoints.length > 1)
              PolylineLayer(
                polylines: [Polyline(points: trailPoints, strokeWidth: 4, color: Colors.deepPurple)],
              ),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Map pictures need internet. Markers and the list still work offline. '
                'The purple line is your recorded trail.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
