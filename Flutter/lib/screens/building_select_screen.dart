import 'package:flutter/material.dart';

import '../theme.dart';

class BuildingSelectScreen extends StatelessWidget {
  final List<Map<String, dynamic>> buildings;
  final String? selectedId;

  const BuildingSelectScreen({
    super.key,
    required this.buildings,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Choose your building'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: buildings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final b = buildings[index];
          final id = b['buildingId']?.toString() ?? '';
          final name = (b['locationName'] ?? id).toString();
          final sensorCount = (b['sensorCount'] ?? 0) as int;
          final alertCount = (b['alertCount'] ?? 0) as int;
          final selected = id == selectedId;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              onTap: () => Navigator.pop(context, b),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: selected ? AppColors.skyDeep : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: AppShadows.soft,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.skyCyan.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: const Icon(
                        Icons.apartment_rounded,
                        color: AppColors.skyDeep,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.bodyStrong),
                          const SizedBox(height: 2),
                          Text(
                            '$id · $sensorCount sensors · $alertCount alerts',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: AppColors.skyDeep),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
