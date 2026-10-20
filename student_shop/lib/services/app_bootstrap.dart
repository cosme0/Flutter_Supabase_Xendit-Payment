import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'session_service.dart';

/// Prepares the application before the first frame is shown.
///
/// * initialises the Supabase client
/// * makes sure that the app has an identity (Supabase user or guest token)
class AppBootstrap {
  AppBootstrap._();

  /// The session of the current device.
  static final SessionService session = SessionService();

  /// Set when the application could not be started properly.
  static String? errorMessage;

  /// True when the app can talk to Supabase.
  static bool get isReady => errorMessage == null;

  /// Initialises Supabase and the customer session.
  static Future<void> initialize() async {
    // Fallback for `flutter run` without --dart-define-from-file: the app
    // reads the .env file from the working directory.
    AppConfig.loadLocalEnvFile();

    if (!AppConfig.isSupabaseConfigured) {
      if (AppConfig.containsPlaceholder) {
        errorMessage =
            'The .env file still contains a placeholder. Copy the publishable '
            'key of the project (Dashboard -> Project Settings -> API Keys) '
            'into SUPABASE_PUBLISHABLE_KEY and start the app again.';
      } else {
        errorMessage =
            'The Supabase configuration is missing. Add SUPABASE_URL and '
            'SUPABASE_PUBLISHABLE_KEY to your .env file and start the app '
            'again with --dart-define-from-file=.env';
      }
      return;
    }

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
        debug: kDebugMode,
      );
    } catch (error) {
      errorMessage = 'Supabase could not be initialised: ${_describe(error)}';
      return;
    }

    try {
      await session.ensureSession().timeout(const Duration(seconds: 20));
    } catch (error) {
      // The app keeps working in guest mode, so this is not fatal.
      debugPrint('Session could not be created: ${_describe(error)}');
    }
  }

  static String _describe(Object error) {
    final String text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}
