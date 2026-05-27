import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Full-screen, dashboard-style "screaming" alarm overlay.
///
/// Mirrors the web dashboard pattern: flashing red background, diagonal stripe
/// pattern, shaking icon, pulsing core card, oscillating siren tone, repeated
/// haptic feedback, and TTS announcement. Persists until the user explicitly
/// acknowledges so it can't be missed.
class AlarmPayload {
  final String title; // e.g. "GAS ALERT", "FLOOD EMERGENCY"
  final String severity; // "CRITICAL" | "WARNING" | "EMERGENCY"
  final String location; // e.g. "Floreasca Business Park - Lobby"
  final String? subtitle; // sensor name / address line
  final String? sensorType; // "CH4" / "CO" / "LPG" / "MULTI"
  final num? valuePpm;
  final num? threshold;
  final String message; // free-form instruction
  final String? receivedOn; // e.g. "Phone iOS-AB12"
  final String? source; // "gas" | "flood"

  const AlarmPayload({
    required this.title,
    required this.severity,
    required this.location,
    required this.message,
    this.subtitle,
    this.sensorType,
    this.valuePpm,
    this.threshold,
    this.receivedOn,
    this.source,
  });
}

class AlarmOverlay extends StatefulWidget {
  final AlarmPayload payload;
  final VoidCallback onAcknowledge;
  final VoidCallback? onEvacuate;
  final String acknowledgeLabel;
  final String? evacuateLabel;

  const AlarmOverlay({
    super.key,
    required this.payload,
    required this.onAcknowledge,
    this.onEvacuate,
    this.acknowledgeLabel = 'I ACKNOWLEDGE',
    this.evacuateLabel,
  });

  @override
  State<AlarmOverlay> createState() => _AlarmOverlayState();
}

class _AlarmOverlayState extends State<AlarmOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  late final AnimationController _shakeController;
  late final AnimationController _stripeController;

  final AudioPlayer _sirenPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  Timer? _sirenSweepTimer;
  Timer? _hapticTimer;
  Timer? _ttsTimer;
  bool _highTone = true;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _stripeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _initAudio();
    _initHaptics();
    _initTts();
  }

  Future<void> _initAudio() async {
    try {
      _sirenPlayer.setReleaseMode(ReleaseMode.loop);
      await _sirenPlayer
          .play(AssetSource('alarm.mp3'))
          .catchError((_) {});
    } catch (_) {}
    // Mimic the dashboard's oscillating sweep by retriggering volume nudges.
    _sirenSweepTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      _highTone = !_highTone;
      try {
        _sirenPlayer.setVolume(_highTone ? 1.0 : 0.65);
      } catch (_) {}
    });
  }

  void _initHaptics() {
    HapticFeedback.heavyImpact();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.1);
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
    _speakAlarm();
    _ttsTimer = Timer.periodic(const Duration(seconds: 8), (_) => _speakAlarm());
  }

  void _speakAlarm() {
    final p = widget.payload;
    final loc = p.location;
    final type = p.sensorType ?? '';
    final value = p.valuePpm;
    final spoken = value is num ? value.toStringAsFixed(0) : '';
    final phrase = type.isNotEmpty && spoken.isNotEmpty
        ? '${p.title}. $type at $loc reading $spoken parts per million. ${p.message}'
        : '${p.title} at $loc. ${p.message}';
    try {
      _tts.stop();
      _tts.speak(phrase);
    } catch (_) {}
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    _stripeController.dispose();
    _sirenSweepTimer?.cancel();
    _hapticTimer?.cancel();
    _ttsTimer?.cancel();
    try {
      _sirenPlayer.stop();
      _sirenPlayer.dispose();
    } catch (_) {}
    try {
      _tts.stop();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    return WillPopScope(
      onWillPop: () async => false,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: Listenable.merge([_bgController, _stripeController]),
          builder: (context, _) {
            final t = _bgController.value;
            final bg = Color.lerp(
              const Color(0xE67F1D1D), // red-900/90
              const Color(0xE6EF4444), // red-500/90
              t,
            )!;
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(color: bg),
                _buildStripes(),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        _buildSeverityChip(p.severity),
                        const SizedBox(height: 12),
                        Expanded(child: _buildCore(p)),
                        const SizedBox(height: 16),
                        _buildActions(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStripes() {
    return ClipRect(
      child: CustomPaint(
        painter: _StripesPainter(offset: _stripeController.value),
        child: Container(),
      ),
    );
  }

  Widget _buildSeverityChip(String severity) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          severity.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFB91C1C),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCore(AlarmPayload p) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = 1.0 + (_pulseController.value * 0.025);
          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xCC450A0A), // red-950/80
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFFFCA5A5),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x99EF4444),
                    blurRadius: 60,
                    spreadRadius: 4 + (_pulseController.value * 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildShakeIcon(),
              const SizedBox(height: 16),
              Text(
                p.title.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.location,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFECACA),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (p.subtitle != null && p.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFEE2E2),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (p.sensorType != null && p.valuePpm != null)
                _buildReadingBlock(p),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  p.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (p.receivedOn != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Received on ${p.receivedOn}',
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShakeIcon() {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, _) {
        final v = _shakeController.value;
        final dx = sin(v * pi * 2) * 4;
        final angle = sin(v * pi * 2) * 0.08;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEF4444),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReadingBlock(AlarmPayload p) {
    final value = p.valuePpm;
    final threshold = p.threshold;
    final valueText =
        value is num ? value.toStringAsFixed(0) : value?.toString() ?? '—';
    final thresholdText = threshold is num
        ? threshold.toStringAsFixed(0)
        : threshold?.toString() ?? '—';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _readingTile('SENSOR', p.sensorType ?? '—'),
        _readingTile('READING', '$valueText ppm'),
        _readingTile('THRESHOLD', '$thresholdText ppm'),
      ],
    );
  }

  Widget _readingTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFCA5A5),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        if (widget.onEvacuate != null && widget.evacuateLabel != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onEvacuate,
              icon: const Icon(Icons.directions_run, size: 20),
              label: Text(
                widget.evacuateLabel!.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFB91C1C),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        if (widget.onEvacuate != null) const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.onAcknowledge,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.acknowledgeLabel.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StripesPainter extends CustomPainter {
  final double offset;
  _StripesPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.07);
    const stripeWidth = 22.0;
    const gap = 22.0;
    final period = stripeWidth + gap;
    final shift = offset * period * 2;
    // Diagonal stripes (45deg) covering the screen by extending past edges.
    final diag = size.width + size.height;
    for (double x = -diag - shift; x < diag; x += period) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripeWidth, 0)
        ..lineTo(x + stripeWidth + diag, diag)
        ..lineTo(x + diag, diag)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripesPainter oldDelegate) =>
      oldDelegate.offset != offset;
}
