import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile', 'https://www.googleapis.com/auth/kid.family'],
    // The Web Application Client ID from Google Cloud Console.
    // Necessary to exchange serverAuthCode on the backend for a refresh token.
    serverClientId:
        '260707499739-ddph8jsvipvr0atq59gpvo7i7l47rgab.apps.googleusercontent.com',
  );

  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      return null;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  static Future<GoogleSignInAccount?> signInSilently() async {
    return await _googleSignIn.signInSilently();
  }
}
