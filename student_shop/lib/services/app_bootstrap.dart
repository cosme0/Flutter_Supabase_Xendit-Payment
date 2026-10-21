import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Prepares the Supabase client before the catalogue is loaded.
///
/// The client is initialised with a timeout so that a slow or unreachable
/// backend can never block the first frame - the store always renders and
/// shows a readable error instead of hanging on the splash screen.
class AppBootstrap {
  AppBootstrap._();

  static Future<String?>? _initialisation;

  /// Initialises Supabase and returns `null` on success or an error message.
  static Future<String?> initialize() {
    return _initialisation ??= _initialise();
  }

  static Future<String?> _initialise() async {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
        authOptions: const FlutterAuthClientOptions(
          // The shop is a guest checkout - it never signs a customer in, so
          // neither the deep link observer (app_links) nor a persisted
          // session (shared_preferences) is needed. Both are switched off so
          // that the start up does not depend on any native plugin.
          detectSessionInUri: false,
          persistSession: false,
          autoRefreshToken: false,
        ),
      ).timeout(const Duration(seconds: 15));

      return null;
    } catch (error) {
      return '$error';
    }
  }
}
