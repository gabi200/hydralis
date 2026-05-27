import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_button.dart';
import '../widgets/auth_toggle.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'mode_select_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  int _safetyLevel = 1; // 0: Safe, 1: Moderate, 2: At Risk, 3: High Risk
  final TextEditingController _birthdayController = TextEditingController();

  static const List<_SafetyOption> _safetyOptions = [
    _SafetyOption(
      value: 0,
      color: Color(0xFF00C853),
      title: 'Safe',
      subtitle: 'High ground',
      icon: Icons.check_circle_outline,
    ),
    _SafetyOption(
      value: 1,
      color: Color(0xFFFFB300),
      title: 'Moderate',
      subtitle: 'Some risk',
      icon: Icons.shield_outlined,
    ),
    _SafetyOption(
      value: 2,
      color: Color(0xFFFF6D00),
      title: 'At Risk',
      subtitle: 'Low ground',
      icon: Icons.warning_amber_outlined,
    ),
    _SafetyOption(
      value: 3,
      color: Color(0xFFD50000),
      title: 'High Risk',
      subtitle: 'Flood zone',
      icon: Icons.crisis_alert_outlined,
    ),
  ];

  @override
  void dispose() {
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthdayController.text =
            "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthToggle(
                    isLogin: false,
                    onLoginPressed: () {
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation1, animation2) =>
                                  const LoginScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    },
                    onSignUpPressed: () {},
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const CustomTextField(
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    prefixIcon: Icons.person_outline,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  CustomTextField(
                    label: 'Birthday',
                    hint: 'mm/dd/yyyy',
                    controller: _birthdayController,
                    readOnly: true,
                    onTap: () => _selectDate(context),
                    prefixIcon: Icons.cake_outlined,
                    suffixIcon: const Icon(
                      Icons.calendar_today_outlined,
                      color: AppColors.inkSubtle,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const CustomTextField(
                    label: 'Primary Location',
                    hint: 'Address or nearest landmark',
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSafetySection(),
                  const SizedBox(height: AppSpacing.xxl),
                  CustomButton(
                    text: 'Sign Up',
                    icon: Icons.arrow_forward_rounded,
                    variant: HydraButtonVariant.primary,
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ModeSelectScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        topInset + AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl + AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadii.xl),
          bottomRight: Radius.circular(AppRadii.xl),
        ),
        boxShadow: AppShadows.medium,
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: AppShadows.glow,
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: AppColors.skyDeep,
                  size: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Hydralis',
            style: AppTextStyles.displayLarge.copyWith(
              color: Colors.white,
              fontSize: 30,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Stay Safe, Stay Informed',
            style: AppTextStyles.body.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location Safety Level', style: AppTextStyles.titleMD),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pick the level that best describes your area.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppSpacing.md;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: _safetyOptions
                  .map(
                    (option) => SizedBox(
                      width: tileWidth,
                      child: _SafetyTile(
                        option: option,
                        selected: _safetyLevel == option.value,
                        onTap: () =>
                            setState(() => _safetyLevel = option.value),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SafetyOption {
  final int value;
  final Color color;
  final String title;
  final String subtitle;
  final IconData icon;

  const _SafetyOption({
    required this.value,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _SafetyTile extends StatelessWidget {
  final _SafetyOption option;
  final bool selected;
  final VoidCallback onTap;

  const _SafetyTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? AppColors.skyCyan : AppColors.border;
    final backgroundColor = selected
        ? AppColors.skyCyan.withValues(alpha: 0.08)
        : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x330EA5E9),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                      spreadRadius: -10,
                    ),
                  ]
                : AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: option.color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      option.icon,
                      color: option.color,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppColors.skyCyan,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: option.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      option.title,
                      style: AppTextStyles.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                option.subtitle,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
