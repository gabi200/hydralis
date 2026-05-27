import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/dashboard_screen.dart';
import 'screens/gas_dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mode_select_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayLight);
  runApp(const HydralisApp());
}

class HydralisApp extends StatelessWidget {
  const HydralisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hydralis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _ModeBootstrap(),
    );
  }
}

class _ModeBootstrap extends StatefulWidget {
  const _ModeBootstrap();

  @override
  State<_ModeBootstrap> createState() => _ModeBootstrapState();
}

class _ModeBootstrapState extends State<_ModeBootstrap> {
  Widget? _next;

  @override
  void initState() {
    super.initState();
    _resolveMode();
  }

  Future<void> _resolveMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('hydralis_mode');
    if (!mounted) return;
    setState(() {
      if (mode == 'resident') {
        _next = const HomeScreen();
      } else if (mode == 'flood') {
        _next = const DashboardScreen();
      } else if (mode == 'gas') {
        _next = const GasDashboardScreen();
      } else {
        _next = const ModeSelectScreen();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_next == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _next!;
  }
}
