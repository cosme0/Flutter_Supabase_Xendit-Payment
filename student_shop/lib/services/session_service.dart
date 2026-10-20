import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps track of *who* is buying in the student shop.
///
/// The shop supports two kinds of customers:
///
///  * **Signed in customer** - the app signs in anonymously (Supabase Auth
///    anonymous user) so that the order belongs to a real `auth.uid()` and
///    the Row Level Security policies of the `orders` table apply.
///  * **Guest customer** - if anonymous sign-ins are disabled in the project
///    the app falls back to a guest checkout. The server then issues a random
///    guest token that is stored on the device (and only its hash is stored
///    in the database).
class SessionService {
  SessionService({SupabaseClient? client}) : _injectedClient = client;

  static const String _guestTokenPreference = 'student_shop_guest_token';
  static const int _guestTokenBytes = 32;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  String? _guestToken;

  /// True when the app could not create a Supabase session and therefore
  /// uses the guest checkout.
  bool _isGuestMode = false;

  /// The reason why the app is running in guest mode (if it is).
  String? _guestModeReason;

  /// The guest token of this device (only set in guest mode).
  String? get guestToken => _guestToken;

  /// True when the app runs without a Supabase user session.
  bool get isGuestMode => _isGuestMode;

  /// Explanation why the app is running in guest mode.
  String? get guestModeReason => _guestModeReason;

  /// The id of the signed in Supabase user (null in guest mode).
  String? get userId => _client.auth.currentUser?.id;

  /// True when a Supabase user session is available.
  bool get isSignedIn => _client.auth.currentUser != null;

  /// Makes sure that the app has a usable identity.
  ///
  /// This never throws: when Supabase Auth is not reachable the app simply
  /// continues in guest mode.
  Future<void> ensureSession() async {
    if (isSignedIn) {
      _isGuestMode = false;
      return;
    }

    try {
      await _client.auth.signInAnonymously();
      _isGuestMode = false;
      _guestModeReason = null;
      return;
    } catch (error) {
      _guestModeReason = _describe(error);
    }

    try {
      _guestToken = await _loadOrCreateGuestToken();
      _isGuestMode = true;
    } catch (error) {
      _guestModeReason = _describe(error);
    }
  }

  /// Stores a guest token that was issued by the server.
  Future<void> saveGuestToken(String token) async {
    if (token.length < 32) return;
    _guestToken = token;
    _isGuestMode = true;
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.setString(_guestTokenPreference, token);
    } catch (_) {
      // Storing the token is a convenience, the checkout still works
      // without it (the order can be seen in the current session).
    }
  }

  Future<String> _loadOrCreateGuestToken() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? existing = preferences.getString(_guestTokenPreference);
    if (existing != null && existing.length >= 32) {
      return existing;
    }

    final String token = generateGuestToken();
    await preferences.setString(_guestTokenPreference, token);
    return token;
  }

  /// Creates a random guest token (64 hexadecimal characters).
  static String generateGuestToken() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < _guestTokenBytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _describe(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    return error.toString();
  }
}
