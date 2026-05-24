import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backend_service.dart';
import '../theme.dart';
import 'alert_screen.dart';
import 'profile_screen.dart';

enum DemoState {
  safe,
  smsReceived,
  crisis,
  evacuation,
  reroute,
  manDown,
  sosTriggered,
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _currentStatus = 'Safe';
  DemoState _demoState = DemoState.safe;
  bool _showSmsBanner = false;
  final FlutterTts _flutterTts = FlutterTts();
  String? _lastTriggeredBroadcastKey;

  // Backend data
  String _copernicusRisk = 'LOADING...';
  String? _activeAlertMessage;
  StreamSubscription? _wsSubscription;
  Timer? _telemetryTimer;

  // Simulated movement state
  LatLng _workerPosition = const LatLng(45.4353, 28.0080);
  Timer? _movementTimer;
  Timer? _manDownTimer;
  final int _manDownCountdown = 30;

  final List<LatLng> _routeA = [
    const LatLng(45.4353, 28.0080),
    const LatLng(45.4365, 28.0090),
    const LatLng(45.4380, 28.0120),
    const LatLng(45.4400, 28.0150),
  ];

  final List<LatLng> _routeB = [
    const LatLng(45.4353, 28.0080),
    const LatLng(45.4360, 28.0060),
    const LatLng(45.4385, 28.0050),
    const LatLng(45.4410, 28.0100),
    const LatLng(45.4400, 28.0150), // Assembly Point North
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initBackend();
  }

  Future<void> _fetchMapData() async {
    final data = await BackendService().fetchMapData(_workerPosition);
    if (data != null && mounted) {
      setState(() {
        final copernicus = data['flood_warning']?['copernicus'];
        if (copernicus != null && copernicus['error'] == null) {
          final status = copernicus['status'];
          if (status == 'likely_flooding') {
            _copernicusRisk = 'HIGH RISK';
          } else if (status == 'possible_flooding') {
            _copernicusRisk = 'MEDIUM RISK';
          } else if (status == 'no_flood_signal') {
            _copernicusRisk = 'LOW RISK';
          } else {
            _copernicusRisk = 'UNKNOWN RISK';
          }
        } else {
          _copernicusRisk = 'ERROR';
        }
      });
    }
  }

  Future<void> _initBackend() async {
    await BackendService().initialize();

    // Initial data fetch
    _fetchMapData();

    // Telemetry reporting
    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      BackendService().postUserStatus(_workerPosition, _currentStatus);
    });

    // Listen to WebSocket events from Dispatcher
    _wsSubscription = BackendService().eventStream.listen((data) {
      print("Dashboard received event: ${data['event']}");
      if (!mounted) return;
      final event = data['event'];

      // Update status from Web Dashboard
      if (event == 'user:status_update') {
        final payload = data['payload'];
        if (payload != null && payload['user_id'] == BackendService().userId) {
          setState(() {
            _currentStatus = payload['status'] ?? 'Safe';
          });
        }
      }

      // Only trigger on mobile when the dispatcher explicitly presses Broadcast.
      // alert:new and alert:updated for draft/review/approved do NOT affect the mobile app.
      if (event == 'alert:updated') {
        final payload = data['payload'];
        final broadcastSentRaw =
            payload?['broadcastSent'] ?? payload?['broadcast_sent'];
        final broadcastSent =
            broadcastSentRaw == true ||
            broadcastSentRaw == 1 ||
            broadcastSentRaw == '1';
        final status = (payload?['status'] ?? '').toString().toLowerCase();
        final isPublished = status == 'published';
        final alertId = payload?['id']?.toString();
        final createdBy =
            (payload?['createdBy'] ?? payload?['created_by'] ?? '').toString();
        final title = (payload?['title'] ?? '').toString();
        final isMobileEmergencyRaw =
            payload?['isMobileEmergency'] ?? payload?['is_mobile_emergency'];
        final isMobileEmergency =
            isMobileEmergencyRaw == true ||
            title.startsWith('SOS:') ||
            createdBy.startsWith('mob-');
        final broadcastMoment =
            (payload?['publishedAt'] ??
                    payload?['published_at'] ??
                    payload?['updatedAt'] ??
                    payload?['updated_at'] ??
                    '')
                .toString();
        final broadcastKey = alertId != null
            ? '$alertId:$broadcastMoment'
            : null;
        print(
          "Alert payload type: ${payload?['type']} status: $status sourceMobile: $isMobileEmergency broadcastSent: $broadcastSent",
        );
        if (payload != null &&
            payload['type'] == 'evacuation' &&
            broadcastSent &&
            isPublished &&
            !isMobileEmergency &&
            alertId != null &&
            broadcastKey != null &&
            broadcastKey != _lastTriggeredBroadcastKey) {
          _activeAlertMessage = payload['message'];
          if (_demoState == DemoState.safe ||
              _demoState == DemoState.smsReceived) {
            _lastTriggeredBroadcastKey = broadcastKey;
            print("TRIGGERING CRISIS from WebSocket broadcast!");
            setState(() {
              _demoState = DemoState.crisis;
            });
            _triggerCrisis();
          }
        }
      }
    });
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _movementTimer?.cancel();
    _manDownTimer?.cancel();
    _telemetryTimer?.cancel();
    _wsSubscription?.cancel();
    super.dispose();
  }

  void _advanceDemo() async {
    setState(() {
      switch (_demoState) {
        case DemoState.safe:
          _demoState = DemoState.smsReceived;
          _showSmsBanner = true;
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showSmsBanner = false);
          });
          break;
        case DemoState.smsReceived:
          _demoState = DemoState.crisis;
          _triggerCrisis();
          break;
        case DemoState.crisis:
          // Normally advances via AlertScreen
          break;
        case DemoState.evacuation:
          _demoState = DemoState.reroute;
          _triggerReroute();
          break;
        case DemoState.reroute:
          _demoState = DemoState.manDown;
          _triggerManDown();
          break;
        case DemoState.manDown:
          // SOS triggers automatically after 30s
          break;
        case DemoState.sosTriggered:
          // Reset
          _demoState = DemoState.safe;
          _workerPosition = const LatLng(45.4353, 28.0080);
          _currentStatus = 'Safe';
          break;
      }
    });
  }

  void _triggerCrisis() async {
    _currentStatus = 'Emergency';
    final startedEvac = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlertScreen()),
    );
    if (startedEvac == true && mounted) {
      setState(() {
        _demoState = DemoState.evacuation;
        _startSimulatedMovement();
      });
    }
  }

  void _startSimulatedMovement() {
    _movementTimer?.cancel();
    int ticks = 0;
    _movementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      ticks++;
      setState(() {
        // Move worker slowly north-east
        _workerPosition = LatLng(
          _workerPosition.latitude + 0.0002,
          _workerPosition.longitude + 0.0002,
        );
      });

      // Auto-trigger reroute after 8 seconds of movement
      if (ticks == 8 && _demoState == DemoState.evacuation) {
        setState(() {
          _demoState = DemoState.reroute;
        });
        _triggerReroute();
      }

      // Auto-trigger man-down after 16 seconds (8 seconds after reroute)
      if (ticks == 16 && _demoState == DemoState.reroute) {
        setState(() {
          _demoState = DemoState.manDown;
        });
        _triggerManDown();
      }
    });
  }

  void _triggerReroute() {
    _flutterTts.speak(
      "Route A flooded. Proceed to Assembly Point North via the elevated walkway.",
    );
  }

  String? _currentAlertId;

  void _triggerManDown() async {
    _movementTimer?.cancel();
    setState(() {
      _demoState = DemoState.sosTriggered;
      _currentStatus = 'Emergency';
    });

    // Immediately send the SOS alert so it appears on the dashboard
    _currentAlertId = await _notifyManDown();

    // Show the dialog with the countdown
    _showSosDialog();
  }

  Future<String?> _notifyManDown() async {
    final prefs = await SharedPreferences.getInstance();
    final hasIssues = prefs.getBool('hasMobilityIssues') ?? false;
    final gravity = prefs.getString('mobilityGravity') ?? 'Low';

    final Map<String, dynamic> mobility = {
      "has_issues": hasIssues,
      "gravity": gravity,
      "level": gravity,
    };

    return await BackendService().triggerManDown(
      _workerPosition,
      mobilityInfo: mobility,
      userStatus: "Man Down",
    );
  }

  void _showSosDialog() {
    int countdown = 30;
    Timer? dialogTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (mounted) {
                setDialogState(() {
                  if (countdown > 0) {
                    countdown--;
                  } else {
                    timer.cancel();
                  }
                });
              }
            });

            return AlertDialog(
              backgroundColor: Colors.red[900],
              title: const Text(
                'MAN-DOWN ALERT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                'Zero movement detected.\nAuto-SOS triggered. Precise coordinates sent to Dispatcher.\n\nTime remaining: $countdown seconds',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    dialogTimer?.cancel();
                    Navigator.pop(context);
                    if (mounted) {
                      setState(() {
                        _demoState = DemoState.safe;
                        _currentStatus = 'Safe';
                      });
                    }
                    await BackendService().postUserStatus(
                      _workerPosition,
                      'Safe',
                    );
                    if (_currentAlertId != null) {
                      await BackendService().cancelAlert(_currentAlertId!);
                    } else {
                      await BackendService().cancelLatestAlert();
                    }
                    _currentAlertId = null;
                  },
                  child: const Text(
                    'I\'M FINE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    dialogTimer?.cancel();
                    Navigator.pop(context);
                    if (mounted) {
                      setState(() {
                        _demoState = DemoState.safe; // Reset for next demo run
                      });
                    }
                  },
                  child: const Text(
                    'DISMISS',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      dialogTimer?.cancel();
    });
  }

  final Map<String, Color> _statusColors = {
    'Safe': const Color(0xFF00C853),
    'Monitor': const Color(0xFFFF6D00),
    'Need Help': const Color(0xFFFFB300),
    'Emergency': const Color(0xFFD50000),
  };

  final Map<String, IconData> _statusIcons = {
    'Safe': Icons.check,
    'Monitor': Icons.bolt,
    'Need Help': Icons.warning_amber_rounded,
    'Emergency': Icons.campaign_outlined,
  };

  // ---------------------------------------------------------------------------
  // UI helpers (visual only — no business logic)
  // ---------------------------------------------------------------------------

  LinearGradient _gradientForStatus(String status) {
    switch (status) {
      case 'Safe':
        return AppGradients.safe;
      case 'Monitor':
        return AppGradients.warning;
      case 'Need Help':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
        );
      case 'Emergency':
        return AppGradients.danger;
      default:
        return AppGradients.ocean;
    }
  }

  String _statusSubtitle(String status) {
    switch (status) {
      case 'Safe':
        return 'All systems normal';
      case 'Monitor':
        return 'Stay alert · conditions changing';
      case 'Need Help':
        return 'Assistance requested';
      case 'Emergency':
        return 'SOS active · dispatcher notified';
      default:
        return 'Status unknown';
    }
  }

  Color _copernicusColor(String risk) {
    switch (risk) {
      case 'HIGH RISK':
        return AppColors.emergencyRed;
      case 'MEDIUM RISK':
        return AppColors.needHelpOrange;
      case 'LOW RISK':
        return AppColors.safeGreen;
      default:
        return AppColors.inkSubtle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
                boxShadow: AppShadows.soft,
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
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.ink,
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          // Sky-tinted gradient backdrop behind the AppBar
          Container(
            height: 220,
            decoration: const BoxDecoration(gradient: AppGradients.skyTint),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Spacer matching AppBar height so content starts below it.
                const SizedBox(height: kToolbarHeight),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hero status card
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: _buildHeroStatusCard(),
                        ),

                        // Active dispatcher alert (conditional)
                        if (_activeAlertMessage != null &&
                            (_demoState == DemoState.crisis ||
                                _demoState == DemoState.evacuation ||
                                _demoState == DemoState.reroute))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: _buildAlertBanner(),
                          ),

                        // SMS pre-alert banner (conditional)
                        if (_showSmsBanner)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: _buildSmsBanner(),
                          ),

                        // Map card
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: _buildMapCard(),
                        ),

                        // Metrics row (only in passive states)
                        if (_demoState == DemoState.safe ||
                            _demoState == DemoState.smsReceived)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.lg,
                              0,
                            ),
                            child: _buildMetricsRow(),
                          ),

                        // Man-down banner (conditional)
                        if (_demoState == DemoState.manDown)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.lg,
                              AppSpacing.lg,
                              0,
                            ),
                            child: _buildManDownBanner(),
                          ),

                        // Nearby safe locations
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xl,
                            AppSpacing.lg,
                            0,
                          ),
                          child: _buildSafeLocations(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hero status card
  // ---------------------------------------------------------------------------
  Widget _buildHeroStatusCard() {
    final gradient = _gradientForStatus(_currentStatus);
    final IconData icon =
        _statusIcons[_currentStatus] ?? Icons.shield_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.medium,
      ),
      child: Row(
        children: [
          // Icon chip
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStatus.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusSubtitle(_currentStatus),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.engineering_outlined,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Worker · Site 7B',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dispatcher alert banner
  // ---------------------------------------------------------------------------
  Widget _buildAlertBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: AppColors.emergencyRed.withOpacity(0.35),
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.emergencyRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.emergencyRed,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dispatcher Message',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: AppColors.emergencyDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _activeAlertMessage ?? '',
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.inkSubtle,
              size: 20,
            ),
            onPressed: () => setState(() => _activeAlertMessage = null),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SMS pre-alert banner
  // ---------------------------------------------------------------------------
  Widget _buildSmsBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.skyCyan.withOpacity(0.3)),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.skyCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.sms_outlined,
              color: AppColors.skyDeep,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-Alert',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: AppColors.skyDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Storm forecasted in 3 days. Prepare for potential evacuation.',
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Map card
  // ---------------------------------------------------------------------------
  Widget _buildMapCard() {
    Color activeColor = _statusColors[_currentStatus]!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: SizedBox(
          height: 360,
          child: Stack(
            children: [
              FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(45.4353, 28.0080),
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.hydralis.floodguard',
                  ),
                  if (_demoState == DemoState.evacuation ||
                      _demoState == DemoState.reroute ||
                      _demoState == DemoState.manDown)
                    PolylineLayer(
                      polylines: [
                        if (_demoState == DemoState.evacuation)
                          Polyline(
                            points: _routeA,
                            color: AppColors.skyDeep,
                            strokeWidth: 5.0,
                          ),
                        if (_demoState == DemoState.reroute ||
                            _demoState == DemoState.manDown) ...[
                          Polyline(
                            points: _routeA,
                            color: AppColors.emergencyRed,
                            strokeWidth: 5.0,
                          ),
                          Polyline(
                            points: _routeB,
                            color: AppColors.skyDeep,
                            strokeWidth: 5.0,
                          ),
                        ],
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _workerPosition,
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.person_pin_circle,
                          color: activeColor,
                          size: 40,
                        ),
                      ),
                      const Marker(
                        point: LatLng(45.4400, 28.0150),
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.location_on,
                          color: AppColors.safeGreen,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Map attribution pill
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Text(
                    'Map Data © Hydralis',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),

              // Floating navigation button (gradient)
              Positioned(
                bottom: 16,
                left: 16,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: AppGradients.ocean,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.glow,
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Metrics row (Copernicus + Galileo)
  // ---------------------------------------------------------------------------
  Widget _buildMetricsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _metricCard(
            eyebrow: 'COPERNICUS',
            subLabel: 'Site Risk Gauge',
            value: _copernicusRisk,
            valueColor: _copernicusColor(_copernicusRisk),
            footnote: '10-day forecast',
            icon: Icons.satellite_alt_rounded,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _metricCard(
            eyebrow: 'GALILEO + EGNOS',
            subLabel: 'Precision Heartbeat',
            value: 'ACTIVE',
            valueColor: AppColors.safeGreen,
            footnote: 'Within geofence',
            icon: Icons.radar_rounded,
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String eyebrow,
    required String subLabel,
    required String value,
    required Color valueColor,
    required String footnote,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.skyCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, color: AppColors.skyDeep, size: 18),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(eyebrow, style: AppTextStyles.eyebrow),
          const SizedBox(height: 2),
          Text(subLabel, style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTextStyles.titleMD.copyWith(color: valueColor),
          ),
          const SizedBox(height: 2),
          Text(footnote, style: AppTextStyles.caption),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Man-down banner
  // ---------------------------------------------------------------------------
  Widget _buildManDownBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppGradients.danger,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.medium,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: Colors.white.withOpacity(0.35)),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Movement Watchdog',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Zero movement detected · SOS in $_manDownCountdown s',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Nearby safe locations
  // ---------------------------------------------------------------------------
  Widget _buildSafeLocations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Nearby Safe Locations', style: AppTextStyles.titleMD),
            Text('10 km radius', style: AppTextStyles.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.safeGreen.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.safeGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'City Hall Emergency Center',
                      style: AppTextStyles.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text('Approx. 1.2 km · safe', style: AppTextStyles.caption),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppGradients.ocean,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  boxShadow: AppShadows.soft,
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Drawer
  // ---------------------------------------------------------------------------
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient header
          Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              MediaQuery.of(context).padding.top + AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            decoration: const BoxDecoration(gradient: AppGradients.deep),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: const Icon(
                        Icons.water_drop_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: AppShadows.glow,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: AppColors.deepNavy,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Andrei Ionescu',
                            style: AppTextStyles.titleLG.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'andrei.ionescu@hydralis.com',
                            style: AppTextStyles.body.copyWith(
                              color: Colors.white.withOpacity(0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              children: [
                _drawerTile(
                  icon: Icons.person_outline,
                  label: 'Profile Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
                _drawerTile(
                  icon: Icons.contacts_outlined,
                  label: 'Emergency Contacts',
                  onTap: () {},
                ),
                _drawerTile(
                  icon: Icons.tips_and_updates_outlined,
                  label: 'Safety Tips',
                  onTap: () {},
                ),
                _drawerTile(
                  icon: Icons.info_outline,
                  label: 'About',
                  onTap: () {},
                ),
              ],
            ),
          ),

          // Footer with logo + version
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Row(
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
                    size: 14,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Hydralis',
                  style: AppTextStyles.bodyStrong,
                ),
                const Spacer(),
                Text(
                  'v1.0.0',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.skyCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, color: AppColors.skyDeep, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(label, style: AppTextStyles.bodyStrong),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkSubtle,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
