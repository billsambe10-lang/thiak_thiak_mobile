import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database.dart';
import 'localisation.dart';
import 'main.dart'
    show
        afficherMessage,
        couleurCarte,
        couleurFond,
        couleurOrange,
        couleurTexte;
import 'models/course.dart';

class EspaceMotardPage extends StatefulWidget {
  const EspaceMotardPage({super.key});

  @override
  State<EspaceMotardPage> createState() => _EspaceMotardPageState();
}

class _EspaceMotardPageState extends State<EspaceMotardPage> {
  final _database = const DatabaseRepository();
  final List<Map<String, dynamic>> _offers = [];
  final Set<String> _actionsEnCours = {};

  bool _verificationEnCours = true;
  bool _autorise = false;
  bool _disponible = false;
  bool _chargementOffres = false;
  bool _miseAJourDisponibilite = false;
  latlong.LatLng? _position;
  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    if (_disponible) _enregistrerIndisponibilite();
    final channel = _channel;
    if (channel != null) {
      unawaited(DatabaseService.client.removeChannel(channel));
    }
    super.dispose();
  }

  Future<void> _initialiser() async {
    if (!DatabaseService.isConfigured) {
      if (mounted) setState(() => _verificationEnCours = false);
      return;
    }
    try {
      final autorise = await _database.isApprovedMotorist();
      if (!mounted) return;
      setState(() {
        _autorise = autorise;
        _verificationEnCours = false;
      });
      if (!autorise) return;

      final presence = await _database.loadMotoristPresence();
      if (!mounted) return;
      final latitude = (presence?['latitude'] as num?)?.toDouble();
      final longitude = (presence?['longitude'] as num?)?.toDouble();
      setState(() {
        _disponible = presence?['is_available'] as bool? ?? false;
        if (latitude != null && longitude != null) {
          _position = latlong.LatLng(latitude, longitude);
        }
      });
      _abonnerAuxOffres();
      await _chargerOffres();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _verificationEnCours = false);
      afficherMessage(context, messageErreurBaseDeDonnees(error));
    }
  }

  Future<void> _chargerOffres() async {
    if (!mounted) return;
    setState(() => _chargementOffres = true);
    try {
      final offers = await _database.loadMotoristOffers();
      if (mounted) {
        setState(() {
          _offers
            ..clear()
            ..addAll(offers);
        });
      }
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    } finally {
      if (mounted) setState(() => _chargementOffres = false);
    }
  }

  void _abonnerAuxOffres() {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = DatabaseService.client
        .channel('motorist-offers-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'motorist_course_offers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motorist_id',
            value: userId,
          ),
          callback: (_) => _chargerOffres(),
        )
        .subscribe();
  }

  Future<void> _modifierDisponibilite(bool disponible) async {
    if (_miseAJourDisponibilite) return;
    setState(() => _miseAJourDisponibilite = true);
    try {
      var position = _position;
      if (disponible) {
        final actuelle = await ServiceLocalisation.positionActuelle();
        if (!mounted) return;
        position = actuelle;
      }
      await _database.updateMotoristPresence(
        available: disponible,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      if (!mounted) {
        if (disponible) _enregistrerIndisponibilite();
        return;
      }
      setState(() {
        _disponible = disponible;
        _position = position;
      });
      if (disponible) {
        _suivrePosition();
      } else {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }
    } on ErreurLocalisation catch (error) {
      if (mounted) afficherMessage(context, error.message);
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    } finally {
      if (mounted) setState(() => _miseAJourDisponibilite = false);
    }
  }

  void _enregistrerIndisponibilite() {
    unawaited(
      _database
          .updateMotoristPresence(
            available: false,
            latitude: _position?.latitude,
            longitude: _position?.longitude,
          )
          .catchError((Object error) {
            debugPrint('Unable to mark motorist unavailable: $error');
          }),
    );
  }

  void _suivrePosition() {
    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 100,
          ),
        ).listen(
          (position) {
            final point = latlong.LatLng(position.latitude, position.longitude);
            if (mounted) setState(() => _position = point);
            _enregistrerPosition(point);
          },
          onError: (Object error) {
            debugPrint('Motorist location stream failed: $error');
            if (mounted) {
              afficherMessage(
                context,
                'Le suivi GPS est interrompu. Vérifiez la localisation.',
              );
            }
          },
        );
  }

  Future<void> _enregistrerPosition(latlong.LatLng position) async {
    try {
      await _database.updateMotoristPresence(
        available: true,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Exception catch (error) {
      debugPrint('Unable to update motorist position: $error');
      if (mounted) {
        afficherMessage(
          context,
          'Position non synchronisée. Vérifiez votre connexion.',
        );
      }
    }
  }

  Future<void> _repondre(Map<String, dynamic> offer, bool accepter) async {
    final id = offer['id'] as String?;
    if (id == null || _actionsEnCours.contains(id)) return;
    setState(() => _actionsEnCours.add(id));
    try {
      await _database.respondToMotoristOffer(offerId: id, accept: accepter);
      await _chargerOffres();
      if (mounted) {
        afficherMessage(
          context,
          accepter ? 'Commande acceptée.' : 'Commande refusée.',
        );
      }
    } on Exception catch (error) {
      if (mounted) afficherMessage(context, messageErreurBaseDeDonnees(error));
    } finally {
      if (mounted) setState(() => _actionsEnCours.remove(id));
    }
  }

  List<Map<String, dynamic>> get _coursesOffertes =>
      _offers.where((offer) => offer['courses'] is Map).toList(growable: false);

  latlong.LatLng get _centreCarte {
    if (_position != null) return _position!;
    for (final offer in _coursesOffertes) {
      final course = Map<String, dynamic>.from(offer['courses'] as Map);
      final latitude = (course['departure_lat'] as num?)?.toDouble();
      final longitude = (course['departure_lng'] as num?)?.toDouble();
      if (latitude != null && longitude != null) {
        return latlong.LatLng(latitude, longitude);
      }
    }
    return positionParDefaut;
  }

  Set<google_maps.Marker> get _marqueurs {
    final markers = <google_maps.Marker>{};
    if (_position case final position?) {
      markers.add(
        google_maps.Marker(
          markerId: const google_maps.MarkerId('motorist'),
          position: google_maps.LatLng(position.latitude, position.longitude),
          infoWindow: const google_maps.InfoWindow(title: 'Ma position'),
        ),
      );
    }
    for (final offer in _coursesOffertes) {
      final course = Map<String, dynamic>.from(offer['courses'] as Map);
      final latitude = (course['departure_lat'] as num?)?.toDouble();
      final longitude = (course['departure_lng'] as num?)?.toDouble();
      final id = offer['id'] as String?;
      if (latitude != null && longitude != null && id != null) {
        markers.add(
          google_maps.Marker(
            markerId: google_maps.MarkerId(id),
            position: google_maps.LatLng(latitude, longitude),
            infoWindow: google_maps.InfoWindow(
              title: 'Départ : ${course['departure']}',
            ),
          ),
        );
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: couleurFond,
        title: const Text('Espace motard'),
      ),
      body: _verificationEnCours
          ? const Center(child: CircularProgressIndicator())
          : !DatabaseService.isConfigured
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Configurez Supabase pour accéder à l’espace motard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            )
          : !_autorise
          ? const _AccesMotardEnAttente()
          : _construireTableau(),
    );
  }

  Widget _construireTableau() {
    final centre = _centreCarte;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: couleurCarte,
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Text(
              _disponible ? 'Disponible pour les courses' : 'Indisponible',
              style: const TextStyle(
                color: couleurTexte,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _disponible
                  ? 'Votre position est partagée pendant que l’écran est ouvert.'
                  : 'Activez votre disponibilité pour recevoir des propositions.',
              style: const TextStyle(color: Colors.white60),
            ),
            activeThumbColor: couleurOrange,
            value: _disponible,
            onChanged: _miseAJourDisponibilite ? null : _modifierDisponibilite,
            secondary: _miseAJourDisponibilite
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _disponible ? Icons.circle : Icons.circle_outlined,
                    color: _disponible ? Colors.greenAccent : Colors.white54,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 230,
            child: google_maps.GoogleMap(
              initialCameraPosition: google_maps.CameraPosition(
                target: google_maps.LatLng(centre.latitude, centre.longitude),
                zoom: 13,
              ),
              markers: _marqueurs,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              zoomControlsEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Commandes proposées',
                style: TextStyle(
                  color: couleurTexte,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _chargementOffres ? null : _chargerOffres,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_chargementOffres && _coursesOffertes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_coursesOffertes.isEmpty)
          const Card(
            color: couleurCarte,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucune commande proposée pour le moment.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
            ),
          )
        else
          ..._coursesOffertes.map(_carteCommande),
      ],
    );
  }

  Widget _carteCommande(Map<String, dynamic> offer) {
    final course = Course.fromDatabase(
      Map<String, dynamic>.from(offer['courses'] as Map),
    );
    final id = offer['id'] as String?;
    final busy = id == null || _actionsEnCours.contains(id);
    return Card(
      color: couleurCarte,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${course.type == TypeCourse.livraison ? 'Livraison' : 'Course moto'} • ${course.prixEstime} FCFA',
              style: const TextStyle(
                color: couleurOrange,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${course.depart} → ${course.destination}',
              style: const TextStyle(color: couleurTexte, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _repondre(offer, false),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: couleurOrange,
                      foregroundColor: couleurFond,
                    ),
                    onPressed: busy ? null : () => _repondre(offer, true),
                    child: const Text('Accepter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccesMotardEnAttente extends StatelessWidget {
  const _AccesMotardEnAttente();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 52, color: couleurOrange),
            SizedBox(height: 16),
            Text(
              'Accès en attente de validation',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: couleurTexte,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'L’équipe doit approuver votre demande et activer votre rôle motard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
