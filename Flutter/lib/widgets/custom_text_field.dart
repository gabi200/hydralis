import 'package:flutter/material.dart';
import '../theme.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hint;
  final bool obscureText;
  final Widget? suffixIcon;
  final IconData? prefixIcon;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final String? helperText;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.readOnly = false,
    this.onTap,
    this.controller,
    this.keyboardType,
    this.helperText,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? AppColors.skyCyan : AppColors.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.bodyStrong,
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: borderColor, width: _focused ? 1.6 : 1),
            boxShadow: _focused
                ? const [
                    BoxShadow(
                      color: Color(0x330EA5E9),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                      spreadRadius: -8,
                    ),
                  ]
                : AppShadows.soft,
          ),
          child: TextField(
            focusNode: _focus,
            controller: widget.controller,
            obscureText: widget.obscureText,
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            keyboardType: widget.keyboardType,
            style: AppTextStyles.bodyLG,
            cursorColor: AppColors.skyCyan,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(color: AppColors.inkSubtle, fontSize: 14),
              filled: true,
              fillColor: Colors.white,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon,
                      color: _focused ? AppColors.skyCyan : AppColors.inkSubtle,
                      size: 20)
                  : null,
              suffixIcon: widget.suffixIcon,
            ),
          ),
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(widget.helperText!, style: AppTextStyles.caption),
        ],
      ],
    );
  }
}
