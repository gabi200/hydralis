import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backend_service.dart';
import '../theme.dart';
import '../widgets/custom_button.dart';
import 'building_select_screen.dart';
import 'mode_select_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _hasMobilityIssues = false;
  String _gravity = 'Low';
  final List<String> _gravityOptions = ['Low', 'Medium', 'High', 'Extreme'];

  // Gas profile
  late TextEditingController _deviceLabelController;
  String _currentMode = 'resident';
  String _buildingLabel = 'Not selected';
  String? _buildingId;

  static const String _userName = 'Andrei Ionescu';
  static const String _userEmail = 'andrei.ionescu@hydralis.com';

  static const _modeOptions = <_ModeOption>[
    _ModeOption(
      value: 'resident',
      label: 'Resident',
      icon: Icons.apartment_rounded,
      color: AppColors.skyDeep,
    ),
    _ModeOption(
      value: 'flood',
      label: 'Field Worker',
      icon: Icons.water,
      color: AppColors.oceanMid,
    ),
    _ModeOption(
      value: 'gas',
      label: 'Gas Operator',
      icon: Icons.local_fire_department,
      color: AppColors.emergencyRed,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _deviceLabelController = TextEditingController(
      text: BackendService().deviceLabel ?? '',
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _deviceLabelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasMobilityIssues = prefs.getBool('hasMobilityIssues') ?? false;
      _gravity = prefs.getString('mobilityGravity') ?? 'Low';
      _currentMode = prefs.getString('hydralis_mode') ?? 'resident';
      _buildingId = BackendService().selectedBuildingId;
    });
    final buildings = await BackendService().fetchBuildings();
    final id = _buildingId;
    if (id != null && mounted) {
      final match = buildings.firstWhere(
        (b) => b['buildingId'] == id,
        orElse: () => <String, dynamic>{},
      );
      setState(() {
        _buildingLabel = match['locationName']?.toString() ?? id;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasMobilityIssues', _hasMobilityIssues);
    await prefs.setString('mobilityGravity', _gravity);
    final label = _deviceLabelController.text.trim();
    if (label.isNotEmpty && label != BackendService().deviceLabel) {
      await BackendService().setDeviceLabel(label);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  Future<void> _changeMode(String mode) async {
    if (mode == _currentMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hydralis_mode', mode);
    if (!mounted) return;
    setState(() => _currentMode = mode);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ModeSelectScreen()),
    );
  }

  Future<void> _pickBuilding() async {
    final buildings = await BackendService().fetchBuildings();
    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingSelectScreen(
          buildings: buildings,
          selectedId: _buildingId,
        ),
      ),
    );
    if (result != null) {
      final id = result['buildingId']?.toString();
      await BackendService().setSelectedBuilding(id);
      setState(() {
        _buildingId = id;
        _buildingLabel =
            result['locationName']?.toString() ?? id ?? 'Not selected';
      });
    }
  }

  Color _gravityColor(String gravity) {
    switch (gravity) {
      case 'Low':
        return AppColors.safeGreen;
      case 'Medium':
        return AppColors.monitorAmber;
      case 'High':
        return AppColors.needHelpOrange;
      case 'Extreme':
        return AppColors.emergencyRed;
      default:
        return AppColors.skyCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroHeader(context),
            const SizedBox(height: 64),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _userName,
                    style: AppTextStyles.titleXL,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _userEmail,
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionCard(
                    title: 'Personal Information',
                    child: Column(
                      children: [
                        _buildInfoTile(
                          icon: Icons.person_outline,
                          label: 'Name',
                          value: _userName,
                        ),
                        const Divider(
                          color: AppColors.divider,
                          height: AppSpacing.lg,
                        ),
                        _buildInfoTile(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: _userEmail,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildSectionCard(
                    title: 'App Mode',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Switch how the app behaves for you.',
                          style: AppTextStyles.body,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: _modeOptions.map(_modeChip).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildSectionCard(
                    title: 'Gas Safety Profile',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoTile(
                          icon: Icons.cellphone_link,
                          label: 'Device ID',
                          value: BackendService().deviceId ?? '—',
                        ),
                        const Divider(
                          color: AppColors.divider,
                          height: AppSpacing.lg,
                        ),
                        const Text(
                          'Device label',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _deviceLabelController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Phone iOS-AB12',
                            filled: true,
                            fillColor: AppColors.inputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadii.md,
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        InkWell(
                          onTap: _pickBuilding,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.skyCyan.withOpacity(0.18),
                                    borderRadius:
                                        BorderRadius.circular(AppRadii.md),
                                  ),
                                  child: const Icon(
                                    Icons.apartment_rounded,
                                    color: AppColors.skyDeep,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Building',
                                        style: AppTextStyles.caption,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _buildingLabel,
                                        style: AppTextStyles.bodyStrong,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildSectionCard(
                    title: 'Mobility & Accessibility',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMobilitySwitch(),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _hasMobilityIssues
                              ? _buildSeveritySection()
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  CustomButton(
                    text: 'Save Profile',
                    onPressed: _saveSettings,
                    variant: HydraButtonVariant.primary,
                    icon: Icons.check_rounded,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 220 + topPadding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 220 + topPadding,
            decoration: const BoxDecoration(
              gradient: AppGradients.hero,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: AppShadows.medium,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: topPadding + AppSpacing.sm,
                left: AppSpacing.sm,
                right: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Text(
                          'User Profile',
                          style: AppTextStyles.titleLG.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -48,
            child: Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: AppShadows.soft,
                ),
                child: const Center(
                  child: Icon(
                    Icons.person,
                    size: 52,
                    color: AppColors.skyDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleMD),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Icon(icon, color: AppColors.skyDeep, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyStrong,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeChip(_ModeOption option) {
    final selected = _currentMode == option.value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => _changeMode(option.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected ? option.color : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? option.color : AppColors.border,
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                option.icon,
                color: selected ? Colors.white : option.color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobilitySwitch() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(
            Icons.accessible_outlined,
            color: AppColors.skyDeep,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mobility Issues', style: AppTextStyles.bodyStrong),
              const SizedBox(height: 2),
              Text(
                'Do you have any conditions affecting movement?',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        Switch(
          value: _hasMobilityIssues,
          onChanged: (val) => setState(() => _hasMobilityIssues = val),
        ),
      ],
    );
  }

  Widget _buildSeveritySection() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Severity', style: AppTextStyles.eyebrow),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _gravityOptions.map((opt) {
              final isSelected = _gravity == opt;
              final color = _gravityColor(opt);
              return _SeverityChip(
                label: opt,
                color: color,
                selected: isSelected,
                onTap: () => setState(() => _gravity = opt),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ModeOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _ModeOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _SeverityChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SeverityChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: 1.4,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
