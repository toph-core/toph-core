import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_button.dart';
import 'package:mary_ai_pos/core/components/app_flush_bar.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/mixins/form_validation_mixin.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/size_config.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_state.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/widgets/liquid_text_field.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/widgets/obsecure_icon_button_widget.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _OnlineOfflineStudentScreenState();
}

class _OnlineOfflineStudentScreenState extends State<LoginScreen>
    with FormValidationMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    context.unfocusKeyboard();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AuthCubit>();

    return KeyboardDismisser(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Form(
            key: formKey,
            child: BlocConsumer<AuthCubit, AuthState>(
              listenWhen: (prev, curr) => prev.status != curr.status,
              listener: (context, state) {
                if (state.status == Status.ERROR) {
                  showAppFlushbarMessage(
                    context,
                    msg: state.failure.getLocalizedMessage(context),
                    type: .failure,
                  );
                } else if (state.status == Status.SUCCESS) {
                  Navigator.pushReplacementNamed(context, AppRoutes.mainScreen);
                }
              },
              builder: (context, state) {
                return Container(
                  height: context.h,
                  width: context.w,
                  alignment: .center,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(AppImages.imgLoginBg),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      mainAxisAlignment: .center,
                      children: [
                        Text(
                          'Brand_id*',
                          style: context.textStyles.bodyMd.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        8.verticalSpace,
                        const LiquidTextField(
                          hintText: "Brand id ni yozing",
                          textInputType: TextInputType.text,
                        ),
                        16.verticalSpace,
                        Text(
                          'Parol*',
                          style: context.textStyles.bodyMd.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        8.verticalSpace,
                        LiquidTextField(
                          hintText: "Kodni yozing",
                          textInputType: TextInputType.text,
                          suffix: ObsecureIconButtonWidget(
                            obsecure: state.obsecure,
                            onToggle: () => cubit.toggle(),
                          ),
                        ),
                        36.verticalSpace,
                        CustomButton(
                          text: "Kirish",
                          onTap: () {
                            Navigator.pushReplacementNamed(
                              context,
                              AppRoutes.loginPinScreen,
                            );
                          },
                          bgColor: AppColors.black.withOpacity(.3),
                          borderColor: AppColors.white,
                          radius: context.radius.segmentedControl,
                        ),
                      ],
                    ).paddingSymmetric(horizontal: wi(16)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
