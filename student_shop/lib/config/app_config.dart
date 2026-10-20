import 'env_file.dart';

/// Compile time configuration of the student shop application.
///
/// The values are injected with `--dart-define` (recommended) or with
/// `--dart-define-from-file=.env`:
///
/// ```bash
/// flutter run --dart-define-from-file=.env
/// ```
///
/// As a convenience the app also reads a `.env` file from the working
/// directory at start up (useful when `flutter run` is used without the
/// flag on the desktop). The APK always uses the values that were compiled
/// into it.
///
/// Only **public** values belong here. The Supabase service role key, the
/// Xendit secret key and the Xendit webhook token live in Supabase edge
/// function secrets and must never be compiled into the application.
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------------
  // values that were compiled into the app
  // ---------------------------------------------------------------------------
  static const String _compiledUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _compiledPublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _compiledAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  // ---------------------------------------------------------------------------
  // values that are used at runtime
  // ---------------------------------------------------------------------------
  static String _supabaseUrl = _compiledUrl;
  static String _supabaseKey = _compiledPublishableKey.isNotEmpty
      ? _compiledPublishableKey
      : _compiledAnonKey;

  /// True when the `.env` file still contains a placeholder instead of a
  /// real key.
  static bool get containsPlaceholder {
    const List<String> placeholders = <String>[
      'PASTE_THE_PUBLISHABLE_KEY_HERE',
      'YOUR_SUPABASE_PUBLISHABLE_KEY',
      'YOUR-PUBLISHABLE-KEY',
      '<publishable key>',
    ];
    final String key = _supabaseKey.toUpperCase();
    return placeholders.any((String placeholder) => key.contains(placeholder));
  }

  /// Supabase project url, e.g. `https://abcdefghijkl.supabase.co`.
  static String get supabaseUrl => _supabaseUrl;

  /// Supabase publishable key (the new name of the anon key).
  static String get supabaseKey => _supabaseKey;

  /// True when the app has everything it needs to talk to Supabase.
  static bool get isSupabaseConfigured =>
      _supabaseUrl.startsWith('https://') &&
      _supabaseKey.isNotEmpty &&
      !containsPlaceholder;

  /// Reads a `.env` file from the working directory.
  ///
  /// The compiled values always win, the file is only a fallback for
  /// `flutter run` without `--dart-define-from-file`.
  static void loadLocalEnvFile([String path = '.env']) {
    final Map<String, String>? values = readEnvFile(path);
    if (values == null) return;

    final String? url = values['SUPABASE_URL'];
    if (url != null && url.isNotEmpty && _compiledUrl.isEmpty) {
      _supabaseUrl = url;
    }

    final String? key =
        values['SUPABASE_PUBLISHABLE_KEY'] ?? values['SUPABASE_ANON_KEY'];
    if (key != null && key.isNotEmpty && _supabaseKey.isEmpty) {
      _supabaseKey = key;
    }
  }

  /// Human readable name of the application.
  static const String appName = 'Student Shop';

  /// Currency of the demonstration (Philippine Peso).
  static const String currencyCode = 'PHP';

  /// Currency symbol used in the user interface.
  static const String currencySymbol = '₱';

  /// Name of the edge function that creates a Xendit invoice.
  static const String createInvoiceFunction = 'create-invoice';
}
