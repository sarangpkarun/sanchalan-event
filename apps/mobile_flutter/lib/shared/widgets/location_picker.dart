import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_text_field.dart';
import 'primary_button.dart';

/// A place chosen on the map.
class PickedLocation {
  const PickedLocation({required this.latLng, required this.address, required this.city});

  final LatLng latLng;
  final String address;

  /// Short city or area name, used as the event's region.
  final String city;

  Map<String, dynamic> toJson() => {'lat': latLng.latitude, 'lng': latLng.longitude, 'address': address};
}

/// Turns a coordinate into an address. Swappable so tests need no network.
typedef ReverseGeocoder = Future<PickedLocation> Function(LatLng point);

final _dio = Dio(BaseOptions(
  baseUrl: 'https://nominatim.openstreetmap.org',
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
  headers: {'User-Agent': 'SetzO-App/1.0'},
));

Future<PickedLocation> nominatimReverse(LatLng p) async {
  final res = await _dio.get<Map<String, dynamic>>(
    '/reverse',
    queryParameters: {'format': 'jsonv2', 'lat': p.latitude, 'lon': p.longitude, 'zoom': 16},
  );
  final data = res.data ?? const {};
  final addr = (data['address'] as Map?)?.cast<String, dynamic>() ?? const {};
  final city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['suburb'] ?? addr['state_district'] ?? addr['state'] ?? '')
      .toString();
  return PickedLocation(latLng: p, address: (data['display_name'] ?? city).toString(), city: city);
}

/// A text field for the place plus a button that opens a map to pick it.
class LocationField extends StatefulWidget {
  const LocationField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onPicked,
    this.errorText,
    this.geocoder = nominatimReverse,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<PickedLocation> onPicked;
  final String? errorText;
  final ReverseGeocoder geocoder;

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  PickedLocation? _picked;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(initial: _picked?.latLng, geocoder: widget.geocoder),
      ),
    );
    if (result == null) return;
    setState(() => _picked = result);
    widget.controller.text = result.city.isNotEmpty ? result.city : result.address;
    widget.onChanged(widget.controller.text);
    widget.onPicked(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: widget.label,
          controller: widget.controller,
          errorText: widget.errorText,
          textInputAction: TextInputAction.next,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: AppSpace.s),
        OutlinedButton.icon(
          onPressed: _open,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Pick on map'),
        ),
        if (_picked != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place, size: 18, color: AppColors.maroon),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(_picked!.address, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Full-screen OpenStreetMap: tap to drop the pin, or use the current location.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial, this.geocoder = nominatimReverse});

  final LatLng? initial;
  final ReverseGeocoder geocoder;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _india = LatLng(20.5937, 78.9629);

  final _map = MapController();
  LatLng? _pin;
  PickedLocation? _resolved;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _setPin(LatLng p) async {
    setState(() {
      _pin = p;
      _resolved = null;
      _error = null;
    });
    try {
      final r = await widget.geocoder(p);
      if (mounted && _pin == p) setState(() => _resolved = r);
    } catch (_) {
      // No network for the address lookup: still allow using the pin with its coordinates.
      if (mounted && _pin == p) {
        setState(() => _resolved = PickedLocation(
              latLng: p,
              address: '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
              city: '',
            ));
      }
    }
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Turn on location services and try again.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission is off. Pick the place on the map instead.';
      }
      final pos = await Geolocator.getCurrentPosition();
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 16);
      await _setPin(p);
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : 'Could not get your location.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick location')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: widget.initial ?? _india,
                    initialZoom: widget.initial != null ? 15 : 4.5,
                    onTap: (_, p) => _setPin(p),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.setzo.app',
                    ),
                    if (_pin != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pin!,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.location_on, size: 44, color: AppColors.maroon),
                        ),
                      ]),
                    const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                  ],
                ),
                Positioned(
                  right: AppSpace.m,
                  top: AppSpace.m,
                  child: FloatingActionButton.small(
                    tooltip: 'Use my current location',
                    onPressed: _busy ? null : _useMyLocation,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _error ??
                        (_pin == null
                            ? 'Tap the map to drop a pin.'
                            : _resolved?.address ?? 'Finding the address…'),
                    style: text.bodyMedium?.copyWith(color: _error != null ? AppColors.errorText : null),
                  ),
                  const SizedBox(height: AppSpace.m),
                  PrimaryButton(
                    label: 'Use this location',
                    onPressed: _resolved == null ? null : () => Navigator.of(context).pop(_resolved),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
