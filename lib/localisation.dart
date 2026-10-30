import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'main.dart' show couleurFond, couleurCarte, couleurOrange, couleurTexte;

/// Dakar : utilisé quand la position de l'utilisateur est inconnue.
const positionParDefaut = LatLng(14.6937, -17.4441);

// ---------------------------------------------------------------------------
// Service de localisation
// ---------------------------------------------------------------------------

class ErreurLocalisation implements Exception {
  final String message;
  const ErreurLocalisation(this.message);
}

class ServiceLocalisation {
  /// Retourne la position actuelle ou lève une [ErreurLocalisation]
  /// avec un message lisible par l'utilisateur.
  static Future<LatLng> positionActuelle() async {
    final actif = await Geolocator.isLocationServiceEnabled();
    if (!actif) {
      throw const ErreurLocalisation(
        'Activez la localisation (GPS) de votre appareil.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const ErreurLocalisation('Permission de localisation refusée.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ErreurLocalisation(
        'Permission refusée définitivement. Autorisez la localisation '
        'dans les paramètres de l’appareil ou du navigateur.',
      );
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      throw const ErreurLocalisation(
        'Impossible d’obtenir votre position. Réessayez.',
      );
    }
  }

  /// Distance à vol d'oiseau, en kilomètres.
  static double distanceKm(LatLng a, LatLng b) =>
      const Distance().distance(a, b) / 1000;
}

// ---------------------------------------------------------------------------
// Éléments de carte partagés
// ---------------------------------------------------------------------------

Widget _tuiles() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.thiak_thiak_mobile',
);

Widget _attribution() => RichAttributionWidget(
  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
);

Marker _marqueur(LatLng point, IconData icone, Color couleur) => Marker(
  point: point,
  width: 44,
  height: 44,
  alignment: Alignment.topCenter,
  child: Icon(icone, color: couleur, size: 44),
);

// ---------------------------------------------------------------------------
// Carte de l'accueil (aperçu de la position de l'utilisateur)
// ---------------------------------------------------------------------------

class CarteAccueil extends StatefulWidget {
  const CarteAccueil({super.key});

  @override
  State<CarteAccueil> createState() => _CarteAccueilState();
}

class _CarteAccueilState extends State<CarteAccueil> {
  final _controller = MapController();
  LatLng? _position;
  String? _erreur;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _localiser());
  }

  Future<void> _localiser() async {
    final carteDejaAffichee = _position != null;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final pos = await ServiceLocalisation.positionActuelle();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _chargement = false;
      });
      if (carteDejaAffichee) _controller.move(pos, 15);
    } on ErreurLocalisation catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: couleurCarte,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: _position != null ? _carte(_position!) : _etatAttente(),
    );
  }

  Widget _carte(LatLng position) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: position,
            initialZoom: 15,
            // Aperçu non interactif pour ne pas bloquer le défilement.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            _tuiles(),
            MarkerLayer(
              markers: [_marqueur(position, Icons.location_on, couleurOrange)],
            ),
            _attribution(),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filled(
            tooltip: 'Actualiser ma position',
            style: IconButton.styleFrom(
              backgroundColor: couleurFond,
              foregroundColor: couleurOrange,
            ),
            onPressed: _chargement ? null : _localiser,
            icon: _chargement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _etatAttente() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_chargement) ...[
              const CircularProgressIndicator(color: couleurOrange),
              const SizedBox(height: 14),
              const Text(
                'Localisation en cours...',
                style: TextStyle(color: Colors.white70),
              ),
            ] else ...[
              const Icon(Icons.location_off, color: couleurOrange, size: 40),
              const SizedBox(height: 8),
              Text(
                _erreur ?? 'Position indisponible.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: couleurTexte, fontSize: 13),
              ),
              TextButton(onPressed: _localiser, child: const Text('Réessayer')),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sélection d'un point sur la carte (destination)
// ---------------------------------------------------------------------------

class SelectionCartePage extends StatefulWidget {
  final LatLng? depart;
  final LatLng? pointInitial;
  final bool choisirDepart;

  const SelectionCartePage({
    super.key,
    this.depart,
    this.pointInitial,
    this.choisirDepart = false,
  });

  @override
  State<SelectionCartePage> createState() => _SelectionCartePageState();
}

class _SelectionCartePageState extends State<SelectionCartePage> {
  LatLng? _point;

  @override
  void initState() {
    super.initState();
    _point = widget.pointInitial;
  }

  @override
  Widget build(BuildContext context) {
    final centre = widget.pointInitial ?? widget.depart ?? positionParDefaut;
    final libelle = widget.choisirDepart
        ? 'le point de départ'
        : 'la destination';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: Text(
          widget.choisirDepart
              ? 'Choisir le point de départ'
              : 'Choisir la destination',
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: centre,
              initialZoom: 14,
              onTap: (_, point) => setState(() => _point = point),
            ),
            children: [
              _tuiles(),
              MarkerLayer(
                markers: [
                  if (widget.depart != null)
                    _marqueur(
                      widget.depart!,
                      Icons.my_location,
                      Colors.lightBlueAccent,
                    ),
                  if (_point != null)
                    _marqueur(_point!, Icons.location_on, couleurOrange),
                ],
              ),
              _attribution(),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: couleurCarte,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _point == null
                          ? 'Touchez la carte pour placer $libelle'
                          : widget.choisirDepart
                          ? 'Point de départ sélectionné'
                          : 'Destination sélectionnée',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: couleurOrange,
                          foregroundColor: couleurFond,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _point == null
                            ? null
                            : () => Navigator.of(context).pop(_point),
                        child: Text(
                          widget.choisirDepart
                              ? 'Confirmer ce point de départ'
                              : 'Confirmer cette destination',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
