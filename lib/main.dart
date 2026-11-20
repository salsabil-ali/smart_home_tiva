import 'package:flutter/material.dart';
import 'screens/scan_screen.dart';
import 'services/bt_service.dart';

/// Single shared service instance (simple, no extra state-management package).
final BtService btService = BtService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B6EF5),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Smart Home Tiva',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E1220),
        cardTheme: CardThemeData(
          color: const Color(0xFF181D31),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}