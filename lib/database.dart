import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/course.dart';

class DatabaseService {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => _url.isNotEmpty && _publishableKey.isNotEmpty;

  static SupabaseClient get client {
    if (!isConfigured) {
      throw StateError('Supabase is not configured.');
    }
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (_url.isEmpty && _publishableKey.isEmpty) return;
    if (_url.isEmpty || _publishableKey.isEmpty) {
      throw StateError(
        'Configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY together.',
      );
    }
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
  }
}

class DatabaseRepository {
  const DatabaseRepository();

  Future<List<Course>> loadCourses() async {
    final rows = await DatabaseService.client
        .from('courses')
        .select()
        .order('created_at', ascending: false);
    return rows.map(Course.fromDatabase).toList(growable: false);
  }

  Future<void> createCourse(Course course) async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Connectez-vous pour enregistrer une course.');
    }
    await DatabaseService.client.from('courses').insert({
      ...course.toDatabase(),
      'user_id': userId,
    });
  }

  Future<void> createMotoristApplication({
    required String name,
    required String phone,
    required String plate,
  }) async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException(
        'Connectez-vous pour envoyer votre demande motard.',
      );
    }
    await DatabaseService.client.from('motorist_applications').insert({
      'user_id': userId,
      'full_name': name.trim(),
      'phone': phone.trim(),
      'license_plate': plate.trim(),
    });
  }

  Future<bool> isApprovedMotorist() async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) return false;

    final profile = await DatabaseService.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    if (profile?['role'] != 'motard') return false;

    final application = await DatabaseService.client
        .from('motorist_applications')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'approved')
        .limit(1)
        .maybeSingle();
    return application != null;
  }

  Future<Map<String, dynamic>?> loadMotoristPresence() async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Connectez-vous pour ouvrir l’espace motard.');
    }

    return DatabaseService.client
        .from('motorist_presence')
        .select()
        .eq('motorist_id', userId)
        .maybeSingle();
  }

  Future<void> updateMotoristPresence({
    required bool available,
    required double? latitude,
    required double? longitude,
  }) async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Connectez-vous pour modifier votre statut.');
    }

    await DatabaseService.client.from('motorist_presence').upsert({
      'motorist_id': userId,
      'is_available': available,
      'latitude': latitude,
      'longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadMotoristOffers() async {
    final userId = DatabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Connectez-vous pour consulter les commandes.');
    }

    final rows = await DatabaseService.client
        .from('motorist_course_offers')
        .select('id, status, created_at, courses(*)')
        .eq('motorist_id', userId)
        .eq('status', 'offered')
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> respondToMotoristOffer({
    required String offerId,
    required bool accept,
  }) async {
    await DatabaseService.client.rpc(
      'respond_to_motorist_offer',
      params: {'p_offer_id': offerId, 'p_accept': accept},
    );
  }
}

String messageErreurBaseDeDonnees(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) {
    debugPrint('Supabase database error: ${error.message}');
    return 'La base de données a refusé la demande. Vérifiez la configuration.';
  }
  debugPrint('Database request failed: $error');
  return 'Impossible de contacter la base de données. Réessayez.';
}
