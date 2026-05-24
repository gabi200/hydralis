import 'package:flutter/material.dart';
import '../theme.dart';

enum HydraButtonVariant { primary, secondary, danger, ghost }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final HydraButtonVariant? variant;
  final IconData? icon;
  final bool loading;
  final double height;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.variant,
    this.icon,
    this.loading = false,
    this.height = 56,
  });

  HydraButtonVariant get _variant =>
      variant ?? (isPrimary ? HydraButtonVariant.primary : HydraButtonVariant.secondary);

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case HydraButtonVariant.primary:
        return _GradientButton(
          text: text,
          onPressed: onPressed,
          icon: icon,
          loading: loading,
          height: height,
          gradient: AppGradients.ocean,
          textColor: Colors.white,
        );
      case HydraButtonVariant.danger:
        return _GradientButton(
          text: text,
          onPressed: onPressed,
          icon: icon,
          loading: loading,
          height: height,
          gradient: AppGradients.danger,
          textColor: Colors.white,
        );
      case HydraButtonVariant.secondary:
        return SizedBox(
          width: double.infinity,
          height: height,
          child: OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.border, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            child: _ButtonChild(text: text, icon: icon, loading: loading, color: AppColors.ink),
          ),
        );
      case HydraButtonVariant.ghost:
        return SizedBox(
          width: double.infinity,
          height: height,
          child: TextButton(
            onPressed: loading ? null : onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.skyDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            child: _ButtonChild(text: text, icon: icon, loading: loading, color: AppColors.skyDeep),
          ),
        );
    }
  }
}

class _GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;
  final LinearGradient gradient;
  final Color textColor;

  const _GradientButton({
    required this.text,
    required this.onPressed,
    required this.gradient,
    required this.textColor,
    required this.height,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: enabled ? AppShadows.glow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: _ButtonChild(text: text, icon: icon, loading: loading, color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonChild extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool loading;
  final Color color;
  const _ButtonChild({
    required this.text,
    required this.color,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
    }
    final label = Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
    if (icon == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        label,
      ],
    );
  }
}
