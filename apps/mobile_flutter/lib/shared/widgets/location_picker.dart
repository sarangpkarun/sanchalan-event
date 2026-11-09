import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_text_field.dart';

/// A place chosen from the suggestions.
class PickedLocation {
  const PickedLocation({required this.latLng, required this.address, required this.city});

  final LatLng latLng;
  final String address;

  /// Short city or area name, used as the event's region.
  final String city;

  Map<String, dynamic> toJson() => {'lat': latLng.latitude, 'lng': latLng.longitude, 'address': address};
}

/// Looks up place suggestions for a query. Swappable so tests need no network.
typedef PlaceSearch = Future<List<PickedLocation>> Function(String query);

final _dio = Dio(BaseOptions(
  baseUrl: 'https://nominatim.openstreetmap.org',
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
  headers: {'User-Agent': 'SetzO-App/1.0'},
));

Future<List<PickedLocation>> nominatimSearch(String query) async {
  final res = await _dio.get<List<dynamic>>(
    '/search',
    queryParameters: {'format': 'jsonv2', 'q': query, 'addressdetails': 1, 'limit': 5, 'countrycodes': 'in'},
  );
  return [
    for (final item in (res.data ?? const []).whereType<Map>())
      () {
        final addr = (item['address'] as Map?)?.cast<String, dynamic>() ?? const {};
        final city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['suburb'] ?? addr['state_district'] ?? addr['state'] ?? '')
            .toString();
        return PickedLocation(
          latLng: LatLng(double.parse('${item['lat']}'), double.parse('${item['lon']}')),
          address: (item['display_name'] ?? city).toString(),
          city: city,
        );
      }(),
  ];
}

/// A text field that suggests matching places as you type.
class LocationField extends StatefulWidget {
  const LocationField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onPicked,
    this.errorText,
    this.search = nominatimSearch,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<PickedLocation> onPicked;
  final String? errorText;
  final PlaceSearch search;

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  Timer? _debounce;
  List<PickedLocation> _suggestions = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onTyped(String value) {
    widget.onChanged(value);
    _debounce?.cancel();
    final q = value.trim();
    _lastQuery = q;
    if (q.length < 3) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      List<PickedLocation> found;
      try {
        found = await widget.search(q);
      } catch (_) {
        found = const []; // Offline: the typed text is still usable as the region.
      }
      if (mounted && _lastQuery == q) {
        setState(() {
          _suggestions = found;
          _loading = false;
        });
      }
    });
  }

  void _select(PickedLocation l) {
    _lastQuery = '';
    widget.controller.text = l.city.isNotEmpty ? l.city : l.address;
    widget.onChanged(widget.controller.text);
    widget.onPicked(l);
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: widget.label,
          controller: widget.controller,
          errorText: widget.errorText,
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.s),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        for (final s in _suggestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined, color: AppColors.maroon),
            title: Text(s.city.isNotEmpty ? s.city : s.address, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(s.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            onTap: () => _select(s),
          ),
      ],
    );
  }
}
