import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_service.dart';
import '../theme.dart';
import '../widgets/alarm_overlay.dart';
import 'alerts_screen.dart';
import 'building_select_screen.dart';
import 'gas_dashboard_screen.dart';
import 'mode_select_screen.dart';
import 'profile_screen.dart';

/// User-facing landing screen.
///
/// Replaces the dispatcher-style dashboard with a resident view: the user's
/// building, its sensors, live status, recent alerts, and quick actions.
/// Connected to the dispatcher dashboard via the existing WebSocket stream so
/// alerts dispatched there appear here as a full-screen screaming alarm.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _gasSub;
  StreamSubscription? _floodSub;

  List<Map<String, dynamic>> _buildings = [];
  Map<String, dynamic>? _building;
  List<Map<String, dynamic>> _sensors = [];
  List<Map<String, dynamic>> _recentAlerts = [];
  bool _loading = true;
  Timer? _refreshTimer;
  OverlayEntry? _activeAlarm;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await BackendService().initialize();
    _gasSub = BackendService().gasAlertStream.listen(_onGasEvent);
    _floodSub = BackendService().eventStream.listen(_onAnyEvent);

    _buildings = await BackendService().fetchBuildings();
    final savedId = BackendService().selectedBuildingId;
    if (savedId != null) {
      _building = _buildings.firstWhere(
        (b) => b['buildingId'] == savedId,
        orElse: () => _buildings.isEmpty ? <String, dynamic>{} : _buildings.first,
      );
    } else if (_buildings.isNotEmpty) {
      _building = _buildings.first;
    }

    if (_building == null && mounted) {
      // No buildings available yet — show empty state.
      setState(() => _loading = false);
      return;
    }

    final buildingId = _building?['buildingId']?.toString();
    if (buildingId != null && buildingId.isNotEmpty) {
      await BackendService().setSelectedBuilding(buildingId);
      await _refreshBuildingData();
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshBuildingData();
    });

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshBuildingData() async {
    final id = _building?['buildingId']?.toString();
    if (id == null || id.isEmpty) return;
    final sensors = await BackendService().fetchSensorsForBuilding(id);
    final alerts = await BackendService().fetchGasAlerts();
    if (!mounted) return;
    setState(() {
      _sensors = sensors;
      _recentAlerts = alerts
          .where((a) =>
              sensors.any((s) => s['id'] == a['sensorId']))
          .take(6)
          .toList();
      // Update building summary numbers from fresh data.
      final updated = _buildings.firstWhere(
        (b) => b['buildingId'] == id,
        orElse: () => _building!,
      );
      _building = {..._building!, ...updated};
    });
  }

  @override
  void dispose() {
    _gasSub?.cancel();
    _floodSub?.cancel();
    _refreshTimer?.cancel();
    _dismissActiveAlarm();
    super.dispose();
  }

  void _onAnyEvent(Map<String, dynamic> data) {
    final event = data['event'];
    if (event == 'gas:reading_update') {
      _refreshBuildingData();
      return;
    }
    if (event != 'alert:updated') return;
    final payload = data['payload'];
    if (payload == null) return;
    final broadcastSentRaw =
        payload['broadcastSent'] ?? payload['broadcast_sent'];
    final broadcastSent = broadcastSentRaw == true ||
        broadcastSentRaw == 1 ||
        broadcastSentRaw == '1';
    final status = (payload['status'] ?? '').toString().toLowerCase();
    if (!(broadcastSent && status == 'published')) return;
    final type = (payload['type'] ?? '').toString();
    if (!(type == 'evacuation' ||
        type == 'flood' ||
        type == 'flash-flood' ||
        type == 'storm')) return;
    _showAlarm(
      AlarmPayload(
        title: 'EVACUATION ORDER',
        severity: 'EMERGENCY',
        location: (payload['location'] ?? _building?['locationName'] ?? 'Your area')
            .toString(),
        message: (payload['message'] ??
                'Dispatcher ordered evacuation. Follow nearest safe route.')
            .toString(),
        source: 'flood',
        receivedOn: BackendService().deviceLabel,
      ),
    );
  }

  void _onGasEvent(Map<String, dynamic> data) {
    final event = data['event'];
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};
    if (event == 'gas:alert') {
      // Only scream if this is our building (or we have no building filter).
      final buildingId = _building?['buildingId']?.toString();
      final sensorId = payload['sensorId']?.toString();
      final ourSensor = sensorId != null &&
          _sensors.any((s) => s['id'] == sensorId);
      if (buildingId != null && !ourSensor) return;
      _showAlarm(
        AlarmPayload(
          title: 'GAS ALERT',
          severity: 'CRITICAL',
          location: (payload['locationName'] ??
                  payload['location'] ??
                  _building?['locationName'] ??
                  'Unknown')
              .toString(),
          subtitle: _sensorNameFor(sensorId),
          sensorType: payload['sensorType']?.toString(),
          valuePpm: payload['valuePpm'] is num ? payload['valuePpm'] as num : null,
          threshold:
              payload['threshold'] is num ? payload['threshold'] as num : null,
          message: 'Evacuate the area immediately and call emergency services.',
          source: 'gas',
          receivedOn: BackendService().deviceLabel,
        ),
      );
      final alertId = payload['id'];
      if (alertId is int) {
        BackendService().ackGasAlert(alertId);
      } else if (alertId is String) {
        final p = int.tryParse(alertId);
        if (p != null) BackendService().ackGasAlert(p);
      }
      _refreshBuildingData();
    } else if (event == 'gas:resolved') {
      _dismissActiveAlarm();
      _refreshBuildingData();
    }
  }

  String? _sensorNameFor(String? sensorId) {
    if (sensorId == null) return null;
    final match = _sensors.firstWhere(
      (s) => s['id'] == sensorId,
      orElse: () => <String, dynamic>{},
    );
    return match['name']?.toString();
  }

  void _showAlarm(AlarmPayload payload) {
    _dismissActiveAlarm();
    final entry = OverlayEntry(
      builder: (context) => AlarmOverlay(
        payload: payload,
        evacuateLabel: 'EVACUATE',
        onEvacuate: () {
          _dismissActiveAlarm();
          _openAlerts();
        },
        onAcknowledge: _dismissActiveAlarm,
      ),
    );
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    overlay.insert(entry);
    _activeAlarm = entry;
  }

  void _dismissActiveAlarm() {
    _activeAlarm?.remove();
    _activeAlarm = null;
  }

  Future<void> _pickBuilding() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingSelectScreen(
          buildings: _buildings,
          selectedId: _building?['buildingId']?.toString(),
        ),
      ),
    );
    if (result != null) {
      await BackendService().setSelectedBuilding(result['buildingId']);
      setState(() => _building = result);
      await _refreshBuildingData();
    }
  }

  void _openAlerts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_building == null || _building!.isEmpty) {
      return _buildNoBuilding();
    }
    final activeGasAlerts = BackendService().activeGasAlerts;
    final hasActiveAlert = activeGasAlerts.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.ink),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppGradients.ocean,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Hydralis', style: AppTextStyles.titleLG),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.ink,
                ),
                if (hasActiveAlert)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.emergencyRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _openAlerts,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _refreshBuildingData,
        child: ListView(
          padding: const EdgeInsets.only(
            top: kToolbarHeight + 8,
            bottom: 32,
          ),
          children: [
            _buildHeroBuildingCard(),
            const SizedBox(height: AppSpacing.md),
            _buildStatusBar(),
            const SizedBox(height: AppSpacing.md),
            _buildBuildingMap(),
            const SizedBox(height: AppSpacing.md),
            _buildSensorsSection(),
            const SizedBox(height: AppSpacing.md),
            _buildRecentAlertsSection(),
            const SizedBox(height: AppSpacing.md),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildNoBuilding() {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Welcome'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.apartment_outlined,
                color: AppColors.skyDeep,
                size: 64,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('No building configured', style: AppTextStyles.titleMD),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pick the building you live or work in so Hydralis can monitor it for you.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _pickBuilding,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Choose your building'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBuildingCard() {
    final b = _building!;
    final name = (b['locationName'] ?? b['buildingId'] ?? 'Your Building').toString();
    final id = (b['buildingId'] ?? '').toString();
    final alertCount = (b['alertCount'] ?? 0) as int;
    final hasAlerts = alertCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          gradient: hasAlerts ? AppGradients.danger : AppGradients.hero,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: AppShadows.medium,
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR BUILDING',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        id,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  onPressed: _pickBuilding,
                  tooltip: 'Change building',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _heroBadge(
                  icon: Icons.sensors,
                  label: '${b['sensorCount'] ?? _sensors.length} sensors',
                ),
                const SizedBox(width: 8),
                _heroBadge(
                  icon: Icons.check_circle_outline,
                  label: '${b['onlineCount'] ?? 0} online',
                ),
                const SizedBox(width: 8),
                _heroBadge(
                  icon: Icons.warning_amber_rounded,
                  label: '$alertCount active',
                  emphasize: hasAlerts,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBadge({
    required IconData icon,
    required String label,
    bool emphasize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(emphasize ? 0.32 : 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final alertCount = (_building?['alertCount'] ?? 0) as int;
    final status = alertCount > 0 ? 'DANGER' : 'ALL CLEAR';
    final color = alertCount > 0 ? AppColors.emergencyRed : AppColors.safeGreen;
    final icon = alertCount > 0
        ? Icons.warning_amber_rounded
        : Icons.shield_outlined;
    final message = alertCount > 0
        ? 'Gas threshold exceeded. Follow evacuation guidance.'
        : 'All sensors normal. Connected to dispatcher.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: color.withOpacity(0.35), width: 1.4),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(message, style: AppTextStyles.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingMap() {
    final lat = (_building?['latitude'] as num?)?.toDouble();
    final lng = (_building?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return const SizedBox.shrink();
    final center = LatLng(lat, lng);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hydralis.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.apartment_rounded,
                        color: AppColors.emergencyDeep,
                        size: 36,
                      ),
                    ),
                    for (final s in _sensors)
                      if ((s['latitude'] as num?) != null &&
                          (s['longitude'] as num?) != null)
                        Marker(
                          point: LatLng(
                            (s['latitude'] as num).toDouble(),
                            (s['longitude'] as num).toDouble(),
                          ),
                          width: 18,
                          height: 18,
                          child: Container(
                            decoration: BoxDecoration(
                              color: s['status'] == 'alert'
                                  ? AppColors.emergencyRed
                                  : s['status'] == 'offline'
                                      ? AppColors.inkSubtle
                                      : AppColors.safeGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSensorsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sensors in your building', style: AppTextStyles.titleMD),
              Text('${_sensors.length}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_sensors.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'No sensors registered for this building yet.',
                style: AppTextStyles.body,
              ),
            )
          else
            ..._sensors.map(_sensorTile),
        ],
      ),
    );
  }

  Widget _sensorTile(Map<String, dynamic> sensor) {
    final status = sensor['status']?.toString() ?? 'offline';
    final reading = sensor['lastReading'];
    final readingText =
        reading is num ? reading.toStringAsFixed(0) : reading?.toString() ?? '—';
    final color = status == 'alert'
        ? AppColors.emergencyRed
        : status == 'offline'
            ? AppColors.inkSubtle
            : AppColors.safeGreen;
    final type = sensor['sensorType']?.toString() ?? 'MULTI';
    IconData icon;
    switch (type) {
      case 'CH4':
        icon = Icons.local_fire_department_outlined;
        break;
      case 'CO':
        icon = Icons.cloud_outlined;
        break;
      case 'LPG':
        icon = Icons.propane_tank;
        break;
      default:
        icon = Icons.sensors;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sensor['name']?.toString() ?? sensor['id'].toString(),
                  style: AppTextStyles.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$type · ${sensor['locationName'] ?? ''}',
                  style: AppTextStyles.caption,
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
                readingText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const Text(
                'ppm',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: AppColors.inkSubtle,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAlertsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Alerts', style: AppTextStyles.titleMD),
              TextButton(
                onPressed: _openAlerts,
                child: const Text('See all'),
              ),
            ],
          ),
          if (_recentAlerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline,
                      color: AppColors.safeGreen, size: 22),
                  SizedBox(width: 8),
                  Expanded(child: Text('No alerts recently.')),
                ],
              ),
            )
          else
            ..._recentAlerts.map(_alertRow),
        ],
      ),
    );
  }

  Widget _alertRow(Map<String, dynamic> alert) {
    final resolved = alert['resolvedAt'] != null;
    final color =
        resolved ? AppColors.inkSubtle : AppColors.emergencyRed;
    final value = alert['valuePpm'];
    final valueText = value is num ? value.toStringAsFixed(0) : '$value';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            resolved ? Icons.check_circle : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert['sensorType']} · $valueText ppm',
                  style: AppTextStyles.bodyStrong.copyWith(color: color),
                ),
                Text(
                  (alert['location'] ?? '').toString(),
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            resolved ? 'resolved' : 'active',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _actionTile(
              icon: Icons.notifications_active_outlined,
              label: 'Alerts',
              color: AppColors.emergencyRed,
              onTap: _openAlerts,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _actionTile(
              icon: Icons.dashboard_outlined,
              label: 'Sensors',
              color: AppColors.skyDeep,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GasDashboardScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _actionTile(
              icon: Icons.person_outline,
              label: 'Profile',
              color: AppColors.oceanMid,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(label, style: AppTextStyles.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(gradient: AppGradients.deep),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          BackendService().userName ?? 'Resident',
                          style: AppTextStyles.titleMD.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _building?['locationName']?.toString() ?? '',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: const Text('Change building'),
              onTap: () {
                Navigator.pop(context);
                _pickBuilding();
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Alerts history'),
              onTap: () {
                Navigator.pop(context);
                _openAlerts();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Sensors dashboard'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GasDashboardScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch mode'),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('hydralis_mode');
                if (!mounted) return;
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ModeSelectScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Test alarm'),
              onTap: () {
                Navigator.pop(context);
                _showAlarm(
                  AlarmPayload(
                    title: 'TEST ALARM',
                    severity: 'CRITICAL',
                    location: _building?['locationName']?.toString() ?? 'Demo',
                    subtitle: 'Triggered manually for verification',
                    sensorType: 'CH4',
                    valuePpm: 5400,
                    threshold: 5000,
                    message:
                        'This is a drill. Tap acknowledge when ready to clear.',
                    receivedOn: BackendService().deviceLabel,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
