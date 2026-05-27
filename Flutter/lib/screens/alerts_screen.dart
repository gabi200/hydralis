import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backend_service.dart';
import '../theme.dart';

/// Resident alert center.
///
/// Shows active and historical gas alerts for the user's building, live-updated
/// via the same WebSocket stream that drives the dashboard. Acts as the
/// recipient side of the dispatcher → mobile alert pipeline.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  StreamSubscription? _gasSub;
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    _gasSub = BackendService().gasAlertStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _gasSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await BackendService().fetchGasAlerts();
    final buildingId = BackendService().selectedBuildingId;
    List<Map<String, dynamic>> filtered = list;
    if (buildingId != null) {
      final sensors =
          await BackendService().fetchSensorsForBuilding(buildingId);
      final sensorIds = sensors.map((s) => s['id']).toSet();
      filtered = list.where((a) => sensorIds.contains(a['sensorId'])).toList();
    }
    if (!mounted) return;
    setState(() {
      _alerts = filtered;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'active':
        return _alerts.where((a) => a['resolvedAt'] == null).toList();
      case 'resolved':
        return _alerts.where((a) => a['resolvedAt'] != null).toList();
      default:
        return _alerts;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _filterChip('all', 'All'),
                const SizedBox(width: 8),
                _filterChip('active', 'Active'),
                const SizedBox(width: 8),
                _filterChip('resolved', 'Resolved'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: AppColors.safeGreen,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'No alerts',
                                style: AppTextStyles.titleMD,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Your building is currently safe.',
                                style: AppTextStyles.body,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          itemCount: _visible.length,
                          itemBuilder: (context, index) =>
                              _alertCard(_visible[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.skyDeep : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? AppColors.skyDeep : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _alertCard(Map<String, dynamic> alert) {
    final resolved = alert['resolvedAt'] != null;
    final color =
        resolved ? AppColors.inkSubtle : AppColors.emergencyRed;
    final value = alert['valuePpm'];
    final threshold = alert['threshold'];
    final valueText = value is num ? value.toStringAsFixed(0) : '$value';
    final thresholdText =
        threshold is num ? threshold.toStringAsFixed(0) : '$threshold';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: color.withOpacity(0.4), width: 1.2),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resolved ? Icons.check_circle : Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                resolved ? 'RESOLVED' : 'ACTIVE',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                (alert['sensorType'] ?? '').toString(),
                style: AppTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$valueText ppm  ·  threshold $thresholdText ppm',
            style: AppTextStyles.bodyStrong.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            (alert['location'] ?? '').toString(),
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.inkSubtle,
              ),
              const SizedBox(width: 4),
              Text(
                (alert['triggeredAt'] ?? '').toString(),
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
