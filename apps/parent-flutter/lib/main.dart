import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'auth/google_sign_in_service.dart';
import 'auth/sign_in_screen.dart';
import 'pairing/pairing_repository.dart';
import 'pairing/pairing_screen.dart';
import 'volume/volume_repository.dart';
import 'volume/volume_control_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase App
  await Firebase.initializeApp();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VolumeRepository()),
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
    final account = await GoogleSignInService.signInSilently();
    if (account != null) {
      final pairingRepo = PairingRepository();
      final device = await pairingRepo.loadPairedDevice();
      if (device != null) {
        // If already paired, go straight to volume control dashboard
        _targetScreen = VolumeControlScreen(
          account: account,
          device: device,
        );
      } else {
        // If logged in but not paired, go to pairing screen
        _targetScreen = PairingScreen(account: account);
      }
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
