import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight representation of a logged-in parent account.
class ParentAccount {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const ParentAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  factory ParentAccount.fromGoogle(GoogleSignInAccount account) {
    return ParentAccount(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory ParentAccount.fromJson(Map<String, dynamic> json) {
    return ParentAccount(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParentAccount &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl;

  @override
  int get hashCode =>
      id.hashCode ^
      email.hashCode ^
      (displayName?.hashCode ?? 0) ^
      (photoUrl?.hashCode ?? 0);

  @override
  String toString() =>
      'ParentAccount(id: $id, email: $email, displayName: $displayName, photoUrl: $photoUrl)';
}

typedef ParentUser = ParentAccount;

class GoogleSignInService {
  @visibleForTesting
  static GoogleSignIn? testGoogleSignIn;

  @visibleForTesting
  static GoogleSignIn? testGoogleSignInFallback;

  /// The Web Application Client ID from Google Cloud Console.
  /// Necessary to exchange serverAuthCode on the backend for a refresh token.
  static const String serverClientId =
      '260707499739-ddph8jsvipvr0atq59gpvo7i7l47rgab.apps.googleusercontent.com';

  static GoogleSignIn? _defaultGoogleSignIn;
  static GoogleSignIn? _defaultGoogleSignInBasic;

  static GoogleSignIn get _primaryClient =>
      testGoogleSignIn ??
      (_defaultGoogleSignIn ??= GoogleSignIn(
        scopes: const ['email'],
        serverClientId: serverClientId,
      ));

  static GoogleSignIn get _fallbackClient =>
      testGoogleSignInFallback ??
      (_defaultGoogleSignInBasic ??= GoogleSignIn(
        scopes: const ['email'],
      ));

  static const String _keySessionId = 'parent_session_id';
  static const String _keySessionEmail = 'parent_session_email';
  static const String _keySessionDisplayName = 'parent_session_displayName';
  static const String _keySessionPhotoUrl = 'parent_session_photoUrl';

  static String? lastError;
  static bool _isDeveloperConfigError = false;
  static ParentAccount? _currentUser;

  /// Returns true if the last sign-in attempt encountered a developer configuration error
  /// (such as missing SHA-1 fingerprint / ApiException 10).
  static bool get isDeveloperConfigError =>
      _isDeveloperConfigError ||
      (lastError != null && isDeveloperError(lastError));

  static set isDeveloperConfigError(bool value) {
    _isDeveloperConfigError = value;
  }

  /// Checks whether an exception indicates a developer configuration issue,
  /// such as missing SHA-1 fingerprint in Firebase/Google Cloud Console (ApiException 10).
  static bool isDeveloperError(dynamic error) {
    if (error == null) return false;
    if (error is PlatformException) {
      if (error.code == '10' ||
          error.code == 'DEVELOPER_ERROR' ||
          (error.message != null && _containsDeveloperErrorCode(error.message!))) {
        return true;
      }
    }
    return _containsDeveloperErrorCode(error.toString());
  }

  static bool _containsDeveloperErrorCode(String message) {
    final str = message.toLowerCase();
    if (str.contains('developer_error')) return true;
    if (str.contains('apiexception: 10') ||
        str.contains('apiexception 10') ||
        str.contains('code: 10') ||
        str.contains('code 10') ||
        str.contains('status code 10') ||
        str.contains('status: 10') ||
        str.contains('statuscode 10')) {
      return true;
    }
    if (RegExp(r'\b10\b').hasMatch(str) &&
        (str.contains('apiexception') ||
            str.contains('sign_in_failed') ||
            str.contains('gms'))) {
      return true;
    }
    return false;
  }

  /// Converts any exception or error into a structured, user-friendly German message.
  static String parseError(dynamic error) {
    if (error == null) {
      return 'Anmeldung abgebrochen oder fehlgeschlagen. Bitte erneut versuchen.';
    }
    if (isDeveloperError(error)) {
      return 'Google Sign-In ist für diese App noch nicht autorisiert '
          '(ApiException 10: SHA-1 Fingerabdruck fehlt in Firebase). '
          'Nutze bitte die E-Mail-Anmeldung oder hinterlege den SHA-1 Key.';
    }
    final errStr = error.toString();
    if (errStr.contains('12500')) {
      return 'Google Sign-In fehlgeschlagen (Fehler 12500). '
          'Bitte prüfe deine Google Play Services oder nutze die E-Mail-Anmeldung.';
    }
    if (errStr.contains('7:') || errStr.toLowerCase().contains('network_error')) {
      return 'Netzwerkfehler bei der Verbindung mit Google. Bitte prüfe deine Internetverbindung.';
    }
    return 'Google Sign-In fehlgeschlagen: $errStr';
  }

  static ParentAccount? get currentUser {
    if (_currentUser != null) return _currentUser;
    final gAccount = _primaryClient.currentUser ?? _fallbackClient.currentUser;
    if (gAccount != null) {
      return ParentAccount.fromGoogle(gAccount);
    }
    return null;
  }

  /// Saves session details to SharedPreferences.
  static Future<void> saveSession({
    required String id,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySessionId, id);
    await prefs.setString(_keySessionEmail, email);
    if (displayName != null) {
      await prefs.setString(_keySessionDisplayName, displayName);
    } else {
      await prefs.remove(_keySessionDisplayName);
    }
    if (photoUrl != null) {
      await prefs.setString(_keySessionPhotoUrl, photoUrl);
    } else {
      await prefs.remove(_keySessionPhotoUrl);
    }
    _currentUser = ParentAccount(
      id: id,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }

  /// Loads saved session from SharedPreferences, if available.
  static Future<ParentAccount?> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keySessionId);
    final email = prefs.getString(_keySessionEmail);
    if (id == null || email == null) {
      return null;
    }
    final displayName = prefs.getString(_keySessionDisplayName);
    final photoUrl = prefs.getString(_keySessionPhotoUrl);
    final account = ParentAccount(
      id: id,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
    );
    _currentUser = account;
    return account;
  }

  /// Clears saved session from SharedPreferences.
  static Future<void> clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySessionId);
    await prefs.remove(_keySessionEmail);
    await prefs.remove(_keySessionDisplayName);
    await prefs.remove(_keySessionPhotoUrl);
    _currentUser = null;
  }

  static Future<ParentAccount> _handleSuccessfulAccount(
    GoogleSignInAccount gAccount,
  ) async {
    final account = ParentAccount.fromGoogle(gAccount);
    await saveSession(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
    _currentUser = account;
    return account;
  }

  /// Performs Google Sign-In with intelligent fallback:
  /// First attempts sign-in using `serverClientId`. If that fails due to a configuration
  /// issue like `ApiException 10` (missing SHA-1), it attempts basic sign-in without `serverClientId`.
  /// If an error persists, sets a friendly German explanation in `lastError`.
  static Future<ParentAccount?> signIn() async {
    lastError = null;
    _isDeveloperConfigError = false;

    try {
      final gAccount = await _primaryClient.signIn();
      if (gAccount == null) {
        return null; // User cancelled
      }
      return await _handleSuccessfulAccount(gAccount);
    } catch (e) {
      debugPrint('Primary Google Sign-In failed: $e');

      if (isDeveloperError(e)) {
        _isDeveloperConfigError = true;
        debugPrint(
          'ApiException 10 (DEVELOPER_ERROR) detected. Attempting fallback sign-in without serverClientId...',
        );
        try {
          final fallbackAccount = await _fallbackClient.signIn();
          if (fallbackAccount != null) {
            _isDeveloperConfigError = false;
            return await _handleSuccessfulAccount(fallbackAccount);
          }
          // User cancelled fallback picker
          return null;
        } catch (fallbackError) {
          debugPrint('Fallback Google Sign-In also failed: $fallbackError');
          if (isDeveloperError(fallbackError)) {
            _isDeveloperConfigError = true;
          }
          lastError = parseError(fallbackError);
          return null;
        }
      }

      lastError = parseError(e);
      return null;
    }
  }

  static Future<void> signOut() async {
    await clearSavedSession();
    try {
      await _primaryClient.signOut();
    } catch (e) {
      debugPrint('Google Sign-In signOut error: $e');
    }
    try {
      await _fallbackClient.signOut();
    } catch (e) {
      debugPrint('Google Sign-In fallback signOut error: $e');
    }
  }

  static Future<ParentAccount?> signInSilently() async {
    lastError = null;
    _isDeveloperConfigError = false;
    try {
      final gAccount = await _primaryClient.signInSilently();
      if (gAccount != null) {
        return await _handleSuccessfulAccount(gAccount);
      }
    } catch (e) {
      debugPrint('Primary Google silent sign-in failed: $e');
      if (isDeveloperError(e)) {
        try {
          final fallbackAccount = await _fallbackClient.signInSilently();
          if (fallbackAccount != null) {
            return await _handleSuccessfulAccount(fallbackAccount);
          }
        } catch (fallbackError) {
          debugPrint('Fallback Google silent sign-in failed: $fallbackError');
        }
      }
    }
    return await loadSavedSession();
  }

  @visibleForTesting
  static void resetForTesting() {
    testGoogleSignIn = null;
    testGoogleSignInFallback = null;
    _defaultGoogleSignIn = null;
    _defaultGoogleSignInBasic = null;
    lastError = null;
    _isDeveloperConfigError = false;
    _currentUser = null;
  }
}
