/// Compile time configuration of the Student Shop application.
///
/// The values can be overridden at build time:
///
/// ```bash
/// flutter build apk --release --dart-define-from-file=.env
/// ```
///
/// Only **public** values belong here. The Supabase service role key and the
/// Xendit secret key live in Supabase edge function secrets and are never
/// compiled into the application.
class AppConfig {
  AppConfig._();

  /// Supabase project url of the backend that hosts the catalogue, the
  /// orders and the edge functions.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kfvxqsxycpmawgbwugyr.supabase.co',
  );

  /// The public Supabase key (the *publishable* key).
  ///
  /// It only grants the `anon` role: the client may read the catalogue and
  /// may call the edge functions, but it can neither write orders nor mark an
  /// order as paid - that is the job of the Xendit webhook.
  static const String supabaseKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_IJvYbkAOlEZu1rDqquaKtg_FTmV5Pq7',
  );

  /// Name of the edge function that creates the Xendit invoice.
  static const String createInvoiceFunction = 'create-invoice';

  /// Human readable name of the application.
  static const String appName = 'Student Shop';

  /// Currency of the demonstration (Philippine Peso).
  static const String currencySymbol = '₱';

  /// True when the app has everything it needs to talk to Supabase.
  static bool get isSupabaseConfigured =>
      supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty;
}
