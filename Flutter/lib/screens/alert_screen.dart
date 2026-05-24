import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import '../theme.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();

  late final AnimationController _pulseController;
  late final AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _playSiren();
  }

  Future<void> _playSiren() async {
    // Play a siren sound. In a real app we'd bundle an asset.
    // Here we can use a generated beep or an asset if we have one.
    // For the hackathon, we'll try to play a high pitched beep or just mock the sound player.
    // We'll set a loop mode.
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    // As a mock for the demo, we will just use a beep asset or skip if not available,
    // assuming there's an asset or we will just let it be silent if missing.
    // Let's assume there is an asset "siren.mp3" eventually, for now we will just mock the call.
    // _audioPlayer.play(AssetSource('siren.mp3'));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.emergencyDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.emergencyDeep,
        body: Stack(
          children: [
            // Full-bleed danger gradient
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF87171),
                      Color(0xFFDC2626),
                      Color(0xFF7F1D1D),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Subtle radial overlay for depth
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 1.1,
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.xl,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - (AppSpacing.xl * 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          _buildLiveAlertBadge(),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildPulseIcon(),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildTitle(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildInfoCard(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildEvacuationButton(),
                          const SizedBox(height: AppSpacing.md),
                          _buildEmergencyButton(),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveAlertBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _dotController,
            builder: (context, _) {
              final t = _dotController.value;
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.55 * (1 - t)),
                      blurRadius: 14,
                      spreadRadius: 4 * t,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'LIVE ALERT',
            style: AppTextStyles.eyebrow.copyWith(
              color: Colors.white.withOpacity(0.92),
              letterSpacing: 1.8,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseIcon() {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Three concentric pulse rings
          _buildPulseRing(delay: 0.0),
          _buildPulseRing(delay: 0.33),
          _buildPulseRing(delay: 0.66),
          // White circle with warning icon
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                  spreadRadius: -8,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.emergencyDeep,
                size: 64,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseRing({required double delay}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final raw = (_pulseController.value + delay) % 1.0;
        final size = 124.0 + (raw * 96.0);
        final opacity = (1.0 - raw).clamp(0.0, 1.0) * 0.55;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(opacity),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle() {
    return Text(
      'FLOOD WARNING',
      textAlign: TextAlign.center,
      style: AppTextStyles.displayLarge.copyWith(
        color: Colors.white,
        fontSize: 38,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        height: 1.05,
        shadows: const [
          Shadow(
            color: Color(0x66000000),
            offset: Offset(0, 4),
            blurRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        children: [
          // High risk line with chip
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Text(
                'There is a',
                style: AppTextStyles.bodyLG.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  'HIGH RISK',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: AppColors.emergencyDeep,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Text(
                'of flooding in your area.',
                style: AppTextStyles.bodyLG.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.22),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Please seek higher ground or a safe place immediately.',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleLG.copyWith(
              color: Colors.white,
              fontSize: 19,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                color: Colors.white.withOpacity(0.85),
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Check the map for safe locations nearby.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvacuationButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          // Go back and indicate evacuation started
          Navigator.pop(context, true);
        },
        icon: const Icon(
          Icons.directions_run,
          color: AppColors.emergencyDeep,
          size: 22,
        ),
        label: Text(
          'START EVACUATION',
          style: AppTextStyles.titleMD.copyWith(
            color: AppColors.emergencyDeep,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.emergencyDeep,
          minimumSize: const Size(double.infinity, 58),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor:
              WidgetStatePropertyAll(AppColors.emergencyDeep.withOpacity(0.08)),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          // Logic to call emergency services
        },
        icon: const Icon(
          Icons.phone_in_talk_outlined,
          color: Colors.white,
          size: 20,
        ),
        label: Text(
          'Call Emergency Services',
          style: AppTextStyles.titleMD.copyWith(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white, width: 1.6),
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withOpacity(0.06),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(Colors.white.withOpacity(0.1)),
        ),
      ),
    );
  }
}
