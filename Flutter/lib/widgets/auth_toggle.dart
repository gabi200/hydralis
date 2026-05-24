import 'package:flutter/material.dart';
import '../theme.dart';

class AuthToggle extends StatelessWidget {
  final bool isLogin;
  final VoidCallback onLoginPressed;
  final VoidCallback onSignUpPressed;

  const AuthToggle({
    super.key,
    required this.isLogin,
    required this.onLoginPressed,
    required this.onSignUpPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    isLogin ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: (width - 12) / 2,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppGradients.ocean,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: AppShadows.glow,
                  ),
                ),
              ),
              Row(
                children: [
                  _segment(
                    label: 'Login',
                    active: isLogin,
                    onTap: onLoginPressed,
                  ),
                  _segment(
                    label: 'Sign Up',
                    active: !isLogin,
                    onTap: onSignUpPressed,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 40,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: active ? Colors.white : AppColors.inkMuted,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
