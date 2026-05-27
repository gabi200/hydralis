import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_screen.dart';
import 'gas_dashboard_screen.dart';
import 'home_screen.dart';

class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key});

  Future<void> _openMode(BuildContext context, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hydralis_mode', mode);
    if (!context.mounted) return;
    final Widget next;
    if (mode == 'resident') {
      next = const HomeScreen();
    } else if (mode == 'gas') {
      next = const GasDashboardScreen();
    } else {
      next = const DashboardScreen();
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Hydralis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose your mode',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You can switch later from the side menu.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  children: [
                    _ModeTile(
                      title: 'Resident',
                      subtitle:
                          'See your building, live sensor status and get screaming alerts the moment something goes wrong.',
                      icon: Icons.apartment_rounded,
                      color: const Color(0xFF0EA5E9),
                      onTap: () => _openMode(context, 'resident'),
                    ),
                    const SizedBox(height: 16),
                    _ModeTile(
                      title: 'Field Worker',
                      subtitle:
                          'Live water levels, dispatcher alerts, evacuation routes, SOS for on-site workers.',
                      icon: Icons.water,
                      color: const Color(0xFF2C74FF),
                      onTap: () => _openMode(context, 'flood'),
                    ),
                    const SizedBox(height: 16),
                    _ModeTile(
                      title: 'Gas Operator',
                      subtitle:
                          'Sensor-by-sensor CH4 / CO / LPG view for maintenance and dispatch staff.',
                      icon: Icons.local_fire_department,
                      color: const Color(0xFFEF4444),
                      onTap: () => _openMode(context, 'gas'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
