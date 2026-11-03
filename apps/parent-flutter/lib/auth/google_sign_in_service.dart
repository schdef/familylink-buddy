import 'package:flutter/foundation.dart';
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

  static GoogleSignIn get _googleSignIn =>
      testGoogleSignIn ?? _defaultGoogleSignIn;

  static final _defaultGoogleSignIn = GoogleSignIn(
    scopes: ['email'],
    // The Web Application Client ID from Google Cloud Console.
    // Necessary to exchange serverAuthCode on the backend for a refresh token.
    serverClientId:
        '260707499739-ddph8jsvipvr0atq59gpvo7i7l47rgab.apps.googleusercontent.com',
  );

  static const String _keySessionId = 'parent_session_id';
  static const String _keySessionEmail = 'parent_session_email';
  static const String _keySessionDisplayName = 'parent_session_displayName';
  static const String _keySessionPhotoUrl = 'parent_session_photoUrl';

  static String? lastError;
  static ParentAccount? _currentUser;

  static ParentAccount? get currentUser {
    if (_currentUser != null) return _currentUser;
    final gAccount = _googleSignIn.currentUser;
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

  static Future<ParentAccount?> signIn() async {
    lastError = null;
    try {
      final gAccount = await _googleSignIn.signIn();
      if (gAccount == null) {
        return null;
      }
      final account = ParentAccount.fromGoogle(gAccount);
      await saveSession(
        id: account.id,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
      _currentUser = account;
      return account;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Google Sign-In failed: $e');
      return null;
    }
  }

  static Future<void> signOut() async {
    await clearSavedSession();
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google Sign-In signOut error: $e');
    }
  }

  static Future<ParentAccount?> signInSilently() async {
    lastError = null;
    try {
      final gAccount = await _googleSignIn.signInSilently();
      if (gAccount != null) {
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
    } catch (e) {
      debugPrint('Google silent sign-in failed: $e');
    }
    return await loadSavedSession();
  }
}
