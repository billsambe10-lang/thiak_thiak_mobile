import 'package:latlong2/latlong.dart';

enum TypeCourse { moto, livraison }

class Course {
  final TypeCourse type;
  final String depart;
  final String destination;
  final int prixEstime;
  final DateTime date;
  final String statut;
  final LatLng? departPos;
  final LatLng? destinationPos;
  final double? distanceKm;

  Course({
    required this.type,
    required this.depart,
    required this.destination,
    required this.prixEstime,
    required this.date,
    this.statut = 'En recherche d’un motard',
    this.departPos,
    this.destinationPos,
    this.distanceKm,
  });

  Map<String, dynamic> toDatabase() => {
    'type': type.name,
    'departure': depart,
    'destination': destination,
    'estimated_price': prixEstime,
    'status': statut,
    'departure_lat': departPos?.latitude,
    'departure_lng': departPos?.longitude,
    'destination_lat': destinationPos?.latitude,
    'destination_lng': destinationPos?.longitude,
    'distance_km': distanceKm,
    'created_at': date.toUtc().toIso8601String(),
  };

  factory Course.fromDatabase(Map<String, dynamic> row) {
    final departureLat = (row['departure_lat'] as num?)?.toDouble();
    final departureLng = (row['departure_lng'] as num?)?.toDouble();
    final destinationLat = (row['destination_lat'] as num?)?.toDouble();
    final destinationLng = (row['destination_lng'] as num?)?.toDouble();

    return Course(
      type: TypeCourse.values.byName(row['type'] as String),
      depart: row['departure'] as String,
      destination: row['destination'] as String,
      prixEstime: row['estimated_price'] as int,
      date: DateTime.parse(row['created_at'] as String).toLocal(),
      statut: row['status'] as String,
      departPos: departureLat != null && departureLng != null
          ? LatLng(departureLat, departureLng)
          : null,
      destinationPos: destinationLat != null && destinationLng != null
          ? LatLng(destinationLat, destinationLng)
          : null,
      distanceKm: (row['distance_km'] as num?)?.toDouble(),
    );
  }
}
