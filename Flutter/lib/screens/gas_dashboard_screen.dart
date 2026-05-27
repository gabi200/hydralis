import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../services/backend_service.dart';
import 'mode_select_screen.dart';

class GasDashboardScreen extends StatefulWidget {
  const GasDashboardScreen({super.key});

  @override
  State<GasDashboardScreen> createState() => _GasDashboardScreenState();
}

class _GasDashboardScreenState extends State<GasDashboardScreen> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audio = AudioPlayer();
  StreamSubscription? _gasSub;
  StreamSubscription? _eventSub;

  List<Map<String, dynamic>> _sensors = [];
  final List<Map<String, dynamic>> _activeAlerts = [];
  int _onlineCount = 0;
  int _alertCount = 0;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await BackendService().initialize();
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);

    await _refreshSensors();

    _gasSub = BackendService().gasAlertStream.listen(_onGasEvent);
    _eventSub = BackendService().eventStream.listen(_onAnyEvent);

    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshSensors();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gasSub?.cancel();
    _eventSub?.cancel();
    _audio.dispose();
    super.dispose();
  }

  Future<void> _refreshSensors() async {
    try {
      final url = '${BackendService().apiV1Url}/gas/sensors';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final list = (data['sensors'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _sensors = list;
        _onlineCount = list.where((s) => s['status'] == 'online').length;
        _alertCount = list.where((s) => s['status'] == 'alert').length;
        _loading = false;
      });
    } catch (e) {
      print('Gas sensor refresh error: $e');
    }
  }

  void _onAnyEvent(Map<String, dynamic> data) {
    if (data['event'] == 'gas:reading_update') {
      _refreshSensors();
    }
  }

  void _onGasEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final event = data['event'];
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};
    if (event == 'gas:alert') {
      setState(() {
        _activeAlerts.removeWhere((a) => a['sensorId'] == payload['sensorId']);
        _activeAlerts.add(payload);
      });
      _scream(payload);
      final alertId = payload['id'];
      if (alertId is int) {
        BackendService().ackGasAlert(alertId);
      } else if (alertId is String) {
        final p = int.tryParse(alertId);
        if (p != null) BackendService().ackGasAlert(p);
      }
      _refreshSensors();
    } else if (event == 'gas:resolved') {
      setState(() {
        _activeAlerts.removeWhere((a) => a['sensorId'] == payload['sensorId']);
      });
      if (_activeAlerts.isEmpty) {
        _audio.stop();
      }
      _refreshSensors();
    }
  }

  void _scream(Map<String, dynamic> payload) {
    final sensorType = payload['sensorType']?.toString() ?? 'gas';
    final location = (payload['locationName'] ?? payload['location'] ?? '')
        .toString();
    final value = payload['valuePpm'];
    final spokenValue = value is num ? value.toStringAsFixed(0) : '$value';
    _tts.speak(
      'Gas alert at $location. $sensorType reading $spokenValue parts per million. Evacuate the area immediately.',
    );
    try {
      _audio.stop();
      _audio.setReleaseMode(ReleaseMode.loop);
      _audio.play(AssetSource('alarm.mp3')).catchError((_) {});
    } catch (_) {}
  }

  Future<void> _switchMode() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ModeSelectScreen()),
    );
  }

  Color _statusColor(String status) {
    if (status == 'alert') return const Color(0xFFEF4444);
    if (status == 'offline') return const Color(0xFF6B7280);
    return const Color(0xFF22C55E);
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'CH4':
        return Icons.local_fire_department_outlined;
      case 'CO':
        return Icons.cloud_outlined;
      case 'LPG':
        return Icons.propane_tank;
      default:
        return Icons.sensors;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceLabel = BackendService().deviceLabel ?? 'this device';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Gas Safety',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFEF4444),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch mode',
            onPressed: _switchMode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSensors,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cellphone_link,
                    color: Color(0xFF2C74FF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Registered as',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          deviceLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Listening',
                      style: TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SummaryChip(
                  label: 'Sensors',
                  value: '${_sensors.length}',
                  color: const Color(0xFF2C74FF),
                  icon: Icons.radar,
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  label: 'Online',
                  value: '$_onlineCount',
                  color: const Color(0xFF22C55E),
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  label: 'Alerts',
                  value: '$_alertCount',
                  color: const Color(0xFFEF4444),
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_activeAlerts.isNotEmpty) ...[
              const Text(
                'Active Alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 8),
              ..._activeAlerts.map(_buildAlertCard),
              const SizedBox(height: 16),
            ],
            const Text(
              'Monitored Sensors',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_sensors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No sensors registered yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ..._sensors.map(_buildSensorTile),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final sensorType = alert['sensorType']?.toString() ?? 'GAS';
    final location = (alert['locationName'] ?? alert['location'] ?? 'Unknown')
        .toString();
    final value = alert['valuePpm'];
    final valueText = value is num ? value.toStringAsFixed(0) : '$value';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$sensorType — $valueText ppm',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB91C1C),
                  ),
                ),
                Text(
                  location,
                  style: const TextStyle(color: Color(0xFF7F1D1D)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Evacuate the area immediately.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFB91C1C)),
            onPressed: () {
              setState(() => _activeAlerts.remove(alert));
              if (_activeAlerts.isEmpty) {
                _audio.stop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSensorTile(Map<String, dynamic> sensor) {
    final type = sensor['sensorType']?.toString() ?? 'MULTI';
    final reading = sensor['lastReading'];
    final readingText = reading is num
        ? reading.toStringAsFixed(0)
        : reading?.toString() ?? '—';
    final status = sensor['status']?.toString() ?? 'offline';
    final statusColor = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_typeIcon(type), color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sensor['name']?.toString() ?? sensor['id']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sensor['locationName']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$readingText',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  fontSize: 16,
                ),
              ),
              const Text(
                'ppm',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
