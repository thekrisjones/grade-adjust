import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class RouteMap extends StatelessWidget {
  final List<LatLng> routePoints;
  final MapController mapController;
  final double? hoveredDistance;
  final List<Marker> markers;

  const RouteMap({
    super.key,
    required this.routePoints,
    required this.mapController,
    this.hoveredDistance,
    this.markers = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (routePoints.isEmpty) {
      return const Center(child: Text('No route data available'));
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        center: routePoints[0],
        zoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
          tileProvider: CancellableNetworkTileProvider(),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              strokeWidth: 4.0,
              color: Colors.blue,
            ),
          ],
        ),
        MarkerLayer(
          markers: markers,
        ),
      ],
    );
  }
} 