import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:thiak_thiak_mobile/models/course.dart';

void main() {
  test('Une course conserve ses détails lors du passage en base', () {
    final date = DateTime.utc(2026, 10, 26, 12);
    final original = Course(
      type: TypeCourse.livraison,
      depart: 'Dakar',
      destination: 'Plateau',
      prixEstime: 1750,
      date: date,
      statut: 'En recherche d’un motard',
      departPos: const LatLng(14.7167, -17.4677),
      destinationPos: const LatLng(14.6708, -17.4381),
      distanceKm: 5.2,
    );

    final restored = Course.fromDatabase(original.toDatabase());

    expect(restored.type, original.type);
    expect(restored.depart, original.depart);
    expect(restored.destination, original.destination);
    expect(restored.prixEstime, original.prixEstime);
    expect(restored.date.toUtc(), original.date);
    expect(restored.statut, original.statut);
    expect(restored.departPos, original.departPos);
    expect(restored.destinationPos, original.destinationPos);
    expect(restored.distanceKm, original.distanceKm);
  });
}
