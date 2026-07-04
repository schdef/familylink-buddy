import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/auth/sign_in_screen.dart';

void main() {
  testWidgets('SignInScreen renders correctly', (WidgetTester tester) async {
    // Build SignInScreen inside a MaterialApp context
    await tester.pumpWidget(
      const MaterialApp(
        home: SignInScreen(),
      ),
    );

    // Verify Title and Subtitle exist
    expect(find.text('FamilyLink Buddy'), findsOneWidget);
    expect(find.text('Eltern-App'), findsOneWidget);

    // Verify Sign In Button exists
    expect(find.text('Mit Google anmelden'), findsOneWidget);

    // Verify Bypass Button exists
    expect(find.text('Bypass Google Login (für Simulator/Test)'), findsOneWidget);
  });
}
