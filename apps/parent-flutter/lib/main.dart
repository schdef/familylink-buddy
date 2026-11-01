import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'auth/google_sign_in_service.dart';
import 'auth/sign_in_screen.dart';
import 'pairing/device_list_screen.dart';
import 'volume/volume_repository.dart';
import 'time_bank/time_bank_repository.dart';
import 'bedtime/bedtime_repository.dart';
import 'screenshot/screenshot_repository.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const useEmulator = String.fromEnvironment('USE_EMULATOR') == 'true';
  if (useEmulator) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyDZsqoZitT74-scNBcxkGBIc60pLmkWaZo',
        appId: '1:260707499739:android:8e68a6feffbfa2700c56fe',
        messagingSenderId: '260707499739',
        projectId: 'dev~familylink-buddy',
      ),
    );
    try {
      final host = defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      debugPrint('Redirected Firebase clients to local emulator suite ($host)');
    } catch (e) {
      debugPrint('Firestore emulator redirection failed: $e');
    }
  } else {
    await Firebase.initializeApp();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VolumeRepository()),
        ChangeNotifierProvider(create: (_) => TimeBankRepository()),
        ChangeNotifierProvider(create: (_) => BedtimeRepository()),
        ChangeNotifierProvider(create: (_) => ScreenshotRepository()),
      ],
      child: const FamilyLinkBuddyParentApp(),
    ),
  );
}

class FamilyLinkBuddyParentApp extends StatelessWidget {
  const FamilyLinkBuddyParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyLink Buddy Parent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF1E293B),
          background: Color(0xFF0F172A),
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
  Widget _targetScreen = const SignInScreen();

  @override
  void initState() {
    super.initState();
    _routeInitialScreen();
  }

  Future<void> _routeInitialScreen() async {
    // Check silent login first
    final account = await GoogleSignInService.signInSilently();
    
    if (account != null) {
      _targetScreen = DeviceListScreen(account: account);
    } else {
      _targetScreen = const SignInScreen();
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
        ),
      );
    }
    return _targetScreen;
  }
}
