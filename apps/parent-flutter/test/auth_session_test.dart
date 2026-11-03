// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/auth/google_sign_in_service.dart';
import 'package:parent_app/auth/sign_in_screen.dart';

class FakeFailingGoogleSignInPlatform extends GoogleSignInPlatform {
  @override
  bool get isMock => true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => const Stream.empty();

  @override
  Future<void> initWithParams(SignInInitParameters params) async {}

  @override
  Future<GoogleSignInUserData?> signIn() async {
    throw PlatformException(
      code: '12500',
      message: 'ApiException: 12500: Sign in failed',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParentAccount Models Tests', () {
    test('Constructs with required and optional properties', () {
      const account = ParentAccount(
        id: '12345',
        email: 'parent@example.com',
        displayName: 'Parent User',
        photoUrl: 'https://example.com/avatar.jpg',
      );

      expect(account.id, '12345');
      expect(account.email, 'parent@example.com');
      expect(account.displayName, 'Parent User');
      expect(account.photoUrl, 'https://example.com/avatar.jpg');
    });

    test('toJson and fromJson round-trip successfully', () {
      const original = ParentAccount(
        id: '98765',
        email: 'test@domain.org',
        displayName: 'Test Parent',
        photoUrl: 'https://img.domain.org/p.png',
      );

      final json = original.toJson();
      final restored = ParentAccount.fromJson(json);

      expect(restored, equals(original));
      expect(restored.id, original.id);
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.photoUrl, original.photoUrl);
    });

    test('ParentUser type alias matches ParentAccount', () {
      const ParentUser user = ParentAccount(
        id: 'uid1',
        email: 'uid1@example.com',
      );
      expect(user, isA<ParentAccount>());
    });

    test('Equality and hashCode work as expected', () {
      const a1 = ParentAccount(id: '1', email: 'a@b.c', displayName: 'A');
      const a2 = ParentAccount(id: '1', email: 'a@b.c', displayName: 'A');
      const a3 = ParentAccount(id: '2', email: 'a@b.c', displayName: 'A');

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
      expect(a1, isNot(equals(a3)));
    });
  });

  group('GoogleSignInService Session Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      GoogleSignInService.lastError = null;
      GoogleSignInService.testGoogleSignIn = null;
    });

    test('saveSession and loadSavedSession round-trip correctly', () async {
      await GoogleSignInService.saveSession(
        id: 'parent-google-id-100',
        email: 'saved@parent.de',
        displayName: 'Saved Parent',
        photoUrl: 'https://photo.url',
      );

      final loaded = await GoogleSignInService.loadSavedSession();
      expect(loaded, isNotNull);
      expect(loaded!.id, 'parent-google-id-100');
      expect(loaded.email, 'saved@parent.de');
      expect(loaded.displayName, 'Saved Parent');
      expect(loaded.photoUrl, 'https://photo.url');
      expect(GoogleSignInService.currentUser, equals(loaded));
    });

    test('clearSavedSession clears preferences and currentUser', () async {
      await GoogleSignInService.saveSession(
        id: 'temp-id',
        email: 'temp@parent.de',
      );

      expect(await GoogleSignInService.loadSavedSession(), isNotNull);

      await GoogleSignInService.clearSavedSession();
      expect(await GoogleSignInService.loadSavedSession(), isNull);
      expect(GoogleSignInService.currentUser, isNull);
    });

    test('signOut clears local session and resets state', () async {
      await GoogleSignInService.saveSession(
        id: 'signout-id',
        email: 'signout@parent.de',
      );

      await GoogleSignInService.signOut();
      expect(await GoogleSignInService.loadSavedSession(), isNull);
      expect(GoogleSignInService.currentUser, isNull);
    });

    test('signInSilently falls back to loadSavedSession when silent Google fails', () async {
      await GoogleSignInService.saveSession(
        id: 'persisted-uid',
        email: 'offline@parent.de',
        displayName: 'Offline Parent',
      );

      // In unit test environment, GoogleSignIn platform channel returns null/fails silently
      final silentAccount = await GoogleSignInService.signInSilently();

      expect(silentAccount, isNotNull);
      expect(silentAccount!.id, 'persisted-uid');
      expect(silentAccount.email, 'offline@parent.de');
      expect(silentAccount.displayName, 'Offline Parent');
    });

    test('lastError property is accessible and mutable for diagnostics', () {
      expect(GoogleSignInService.lastError, isNull);
      GoogleSignInService.lastError = 'ApiException: 12500';
      expect(GoogleSignInService.lastError, 'ApiException: 12500');
    });
  });

  group('SignInScreen Diagnostic and Fallback Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      GoogleSignInService.lastError = null;
      GoogleSignInService.testGoogleSignIn = null;
    });

    testWidgets('Shows "Als [Email] fortfahren" button when saved session exists',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'parent_session_id': 'saved-123',
        'parent_session_email': 'stefan@familie.de',
        'parent_session_displayName': 'Stefan',
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: SignInScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Als stefan@familie.de fortfahren'), findsOneWidget);
      expect(find.text('Mit Google anmelden'), findsOneWidget);
      expect(find.text('Mit E-Mail anmelden'), findsOneWidget);
      expect(find.text('Bypass Google Login (für Simulator/Test)'), findsOneWidget);
    });

    testWidgets('Tapping "Mit E-Mail anmelden" shows dialog with text field and dismisses on Abbrechen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final emailButton = find.text('Mit E-Mail anmelden');
      expect(emailButton, findsOneWidget);
      await tester.tap(emailButton);
      await tester.pumpAndSettle();

      expect(find.text('Geben Sie Ihre E-Mail-Adresse ein, um fortzufahren:'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Anmelden'), findsOneWidget);

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(find.text('Geben Sie Ihre E-Mail-Adresse ein, um fortzufahren:'), findsNothing);
    });

    testWidgets('Displays diagnostic error container when sign in fails with lastError',
        (WidgetTester tester) async {
      GoogleSignInPlatform.instance = FakeFailingGoogleSignInPlatform();
      GoogleSignInService.testGoogleSignIn = GoogleSignIn(scopes: ['email']);

      await tester.pumpWidget(
        const MaterialApp(
          home: SignInScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final googleButton = find.text('Mit Google anmelden');
      await tester.tap(googleButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('12500'), findsOneWidget);
      expect(GoogleSignInService.lastError, contains('12500'));
    });
  });
}
