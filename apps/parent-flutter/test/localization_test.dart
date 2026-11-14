import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parent_app/l10n/app_strings.dart';

void main() {
  group('Localization Architecture (AppStrings) Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppStrings.manualLocale = null;
    });

    tearDown(() {
      AppStrings.manualLocale = null;
    });

    test('getStrings resolves correct language instance', () {
      final en = AppStrings.getStrings('en');
      expect(en, isA<AppStringsEn>());
      expect(en.languageCode, 'en');
      expect(en.myChildren, 'My Children');
      expect(en.liveScreenTitle, 'Live Screen');
      expect(en.appLimitsTitle, 'App Limits & Blocking');
      expect(en.bedtimeTitle, 'Bedtime & Wi-Fi');
      expect(en.timeBankTitle, 'Time Bank');
      expect(en.walkieTalkieTitle, 'Walkie-Talkie Comms');
      expect(en.connectionFailedHint('192.168.1.1', 8085), contains('Not Guest Wi-Fi'));
      expect(en.deviceNotFoundOnLan('123456'), contains('was not found on the local Wi-Fi'));

      final de = AppStrings.getStrings('de');
      expect(de, isA<AppStringsDe>());
      expect(de.languageCode, 'de');
      expect(de.myChildren, 'Meine Kinder');
      expect(de.liveScreenTitle, 'Live-Bildschirm');
      expect(de.appLimitsTitle, 'App-Limits & Sperren');
      expect(de.bedtimeTitle, 'WLAN-Nachtruhe');
      expect(de.timeBankTitle, 'Zeitkonto');
      expect(de.walkieTalkieTitle, 'Walkie-Talkie Comms');
      expect(de.connectionFailedHint('192.168.1.1', 8085), contains('Kein Gast-WLAN'));
      expect(de.deviceNotFoundOnLan('123456'), contains('im lokalen WLAN nicht gefunden'));
    });

    test('Unknown language codes fall back to English by default', () {
      final fr = AppStrings.getStrings('fr');
      expect(fr, isA<AppStringsEn>());
      expect(fr.languageCode, 'en');

      final es = AppStrings.getStrings('es');
      expect(es, isA<AppStringsEn>());

      final empty = AppStrings.getStrings('');
      expect(empty, isA<AppStringsEn>());
    });

    test('Manual locale override sets current strings and notifies listeners', () {
      int notifyCount = 0;
      void listener() => notifyCount++;

      AppStrings.addListener(listener);

      try {
        AppStrings.manualLocale = const Locale('de');
        expect(AppStrings.manualLocale, const Locale('de'));
        expect(AppStrings.currentLocale, const Locale('de'));
        expect(AppStrings.current.languageCode, 'de');
        expect(AppStrings.current.myChildren, 'Meine Kinder');
        expect(notifyCount, 1);

        AppStrings.manualLocale = const Locale('en');
        expect(AppStrings.manualLocale, const Locale('en'));
        expect(AppStrings.currentLocale, const Locale('en'));
        expect(AppStrings.current.languageCode, 'en');
        expect(AppStrings.current.myChildren, 'My Children');
        expect(notifyCount, 2);

        AppStrings.manualLocale = null;
        expect(AppStrings.manualLocale, isNull);
        expect(notifyCount, 3);
      } finally {
        AppStrings.removeListener(listener);
      }
    });

    test('Persistence with SharedPreferences works correctly', () async {
      SharedPreferences.setMockInitialValues({});

      await AppStrings.setSavedLocale('de');
      expect(AppStrings.manualLocale, const Locale('de'));
      expect(AppStrings.current.languageCode, 'de');

      // Clear memory override to simulate fresh app restart
      AppStrings.manualLocale = null;
      expect(AppStrings.manualLocale, isNull);

      // Load saved locale
      await AppStrings.loadSavedLocale();
      expect(AppStrings.manualLocale, const Locale('de'));
      expect(AppStrings.current.languageCode, 'de');

      // Revert to system default (null)
      await AppStrings.setSavedLocale(null);
      expect(AppStrings.manualLocale, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('app_language_override'), isFalse);
    });

    testWidgets('context.strings resolves correctly in widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final strings = context.strings;
              return Scaffold(
                appBar: AppBar(title: Text(strings.myChildren)),
                body: Column(
                  children: [
                    Text(strings.liveScreenTitle),
                    Text(strings.appLimitsTitle),
                    Text(strings.bedtimeTitle),
                    Text(strings.timeBankTitle),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Test German mode
      AppStrings.manualLocale = const Locale('de');
      await tester.pumpWidget(
        MaterialApp(
          locale: AppStrings.currentLocale,
          home: Builder(
            builder: (context) {
              final strings = context.strings;
              return Scaffold(
                appBar: AppBar(title: Text(strings.myChildren)),
                body: Column(
                  children: [
                    Text(strings.liveScreenTitle),
                    Text(strings.appLimitsTitle),
                    Text(strings.bedtimeTitle),
                    Text(strings.timeBankTitle),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meine Kinder'), findsOneWidget);
      expect(find.text('Live-Bildschirm'), findsOneWidget);
      expect(find.text('App-Limits & Sperren'), findsOneWidget);
      expect(find.text('WLAN-Nachtruhe'), findsOneWidget);
      expect(find.text('Zeitkonto'), findsOneWidget);

      // Test English mode
      AppStrings.manualLocale = const Locale('en');
      await tester.pumpWidget(
        MaterialApp(
          locale: AppStrings.currentLocale,
          home: Builder(
            builder: (context) {
              final strings = context.strings;
              return Scaffold(
                appBar: AppBar(title: Text(strings.myChildren)),
                body: Column(
                  children: [
                    Text(strings.liveScreenTitle),
                    Text(strings.appLimitsTitle),
                    Text(strings.bedtimeTitle),
                    Text(strings.timeBankTitle),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Children'), findsOneWidget);
      expect(find.text('Live Screen'), findsOneWidget);
      expect(find.text('App Limits & Blocking'), findsOneWidget);
      expect(find.text('Bedtime & Wi-Fi'), findsOneWidget);
      expect(find.text('Time Bank'), findsOneWidget);
    });
  });
}
