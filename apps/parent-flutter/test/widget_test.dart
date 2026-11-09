import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/pairing/device_list_screen.dart';
import 'package:parent_app/l10n/app_strings.dart';

void main() {
  setUp(() => AppStrings.manualLocale = const Locale('de'));
  tearDown(() => AppStrings.manualLocale = null);

  testWidgets('DeviceListScreen renders correctly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and LAN indicator exist
    expect(find.text('Meine Kinder'), findsOneWidget);
    expect(find.text('LAN Local'), findsOneWidget);

    // Verify Empty state exists
    expect(find.text('Noch keine Kinder gekoppelt'), findsOneWidget);
    expect(find.text('Gerät koppeln'), findsOneWidget);
  });
}
