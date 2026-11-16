import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pairing/device_list_screen.dart';
import 'pairing/pairing_repository.dart';
import 'volume/volume_control_screen.dart';
import 'volume/volume_repository.dart';
import 'time_bank/time_bank_repository.dart';
import 'bedtime/bedtime_repository.dart';
import 'screenshot/screenshot_repository.dart';
import 'app_limits/app_limits_repository.dart';
import 'comms/comms_repository.dart';
import 'l10n/app_strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStrings.loadSavedLocale();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VolumeRepository()),
        ChangeNotifierProvider(create: (_) => TimeBankRepository()),
        ChangeNotifierProvider(create: (_) => BedtimeRepository()),
        ChangeNotifierProvider(create: (_) => ScreenshotRepository()),
        ChangeNotifierProvider(create: (_) => AppLimitsRepository()),
        ChangeNotifierProvider(create: (_) => CommsRepository()),
      ],
      child: const FamilyLinkBuddyParentApp(),
    ),
  );
}

class FamilyLinkBuddyParentApp extends StatefulWidget {
  const FamilyLinkBuddyParentApp({super.key});

  @override
  State<FamilyLinkBuddyParentApp> createState() => _FamilyLinkBuddyParentAppState();
}

class _FamilyLinkBuddyParentAppState extends State<FamilyLinkBuddyParentApp> {
  @override
  void initState() {
    super.initState();
    AppStrings.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    AppStrings.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyLink Buddy Parent',
      debugShowCheckedModeBanner: false,
      locale: AppStrings.currentLocale,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const InitialRouter(),
    );
  }
}

class InitialRouter extends StatefulWidget {
  const InitialRouter({super.key});

  @override
  State<InitialRouter> createState() => _InitialRouterState();
}

class _InitialRouterState extends State<InitialRouter> {
  bool _isLoading = true;
  Widget _targetScreen = const DeviceListScreen();

  @override
  void initState() {
    super.initState();
    _routeInitialScreen();
  }

  Future<void> _routeInitialScreen() async {
    try {
      final pairedDevice = await PairingRepository().loadPairedDevice();
      if (mounted) {
        setState(() {
          if (pairedDevice != null) {
            _targetScreen = VolumeControlScreen(device: pairedDevice);
          } else {
            _targetScreen = const DeviceListScreen();
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _targetScreen = const DeviceListScreen();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }
    return _targetScreen;
  }
}
