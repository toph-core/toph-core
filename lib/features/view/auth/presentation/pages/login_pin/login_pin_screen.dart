import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart'; // for SystemUiMode (optional fullscreen)

class LoginPinScreen extends StatefulWidget {
  const LoginPinScreen({super.key});

  @override
  State<LoginPinScreen> createState() => _LoginPinScreenState();
}

class _LoginPinScreenState extends State<LoginPinScreen> {
  final TextEditingController _brandController = TextEditingController();
  String _pin = '';
  static const int _pinLength = 6;

  void _onKeyPressed(String value) {
    if (value == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else if (_pin.length < _pinLength) {
      setState(() => _pin += value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: context.h,
        width: context.w,
        alignment: .center,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppImages.imgLoginBg),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 492),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "2-6 raqam kiriting",
                  style: context.textStyles.bodyMd.copyWith(
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pinLength, (index) {
                    final filled = index < _pin.length;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                        border: Border.all(color: Colors.white, width: 0.5),
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? Colors.white : Colors.white24,
                            border: Border.all(
                              color: Colors.white54,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 40),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ...List.generate(9, (i) => _buildKey('${i + 1}')),
                    _buildKey('⌫', isSpecial: true),
                    _buildKey('0'),
                    _buildKey('✓', isConfirm: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKey(
    String label, {
    bool isSpecial = false,
    bool isConfirm = false,
  }) {
    return GestureDetector(
      onTap: () => _onKeyPressed(
        label == '✓'
            ? 'confirm'
            : label == '⌫'
            ? '⌫'
            : label,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isConfirm
              ? Colors.blue
              : isSpecial
              ? Colors.white.withOpacity(0.15)
              : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: isConfirm
              ? null
              : Border.all(color: Colors.white24, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: isConfirm ? Colors.white : Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _brandController.dispose();
    super.dispose();
  }
}
