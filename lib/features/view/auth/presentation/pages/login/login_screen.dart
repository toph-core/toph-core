import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/auth/models/brand_id_token_pair/brand_id_token_pair.dart';
import 'package:mary_ai_pos/core/common/custom_button.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/mixins/form_validation_mixin.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/utils/validator.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/core/values/app_colors.dart';
import 'package:mary_ai_pos/core/values/app_strings.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_cubit.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/auth/auth_state.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/widgets/liquid_text_field.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/pages/login/widgets/obsecure_icon_button_widget.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _OnlineOfflineStudentScreenState();
}

class _OnlineOfflineStudentScreenState extends State<LoginScreen>
    with FormValidationMixin {
  final TextEditingController _brandIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _brandIdController.dispose();
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
                  showErrorMessage(
                    context,
                    state.failure.getLocalizedMessage(context),
                  );
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
                          AppStrings.strBrandId,
                          style: context.textStyles.bodyMd.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        8.verticalSpace,
                        LiquidTextField(
                          hintText: S.current.strEnterBrandID,
                          textInputType: TextInputType.text,
                          onChange: (value) => updateFormValidity(),
                          validator: (value) =>
                              Validator.nameChecker(value ?? ''),
                          textEditingController: _brandIdController,
                        ),
                        16.verticalSpace,
                        Text(
                          '${S.current.strPassword}*',
                          style: context.textStyles.bodyMd.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                        8.verticalSpace,
                        LiquidTextField(
                          hintText: S.current.strEnterCode,
                          textInputType: TextInputType.text,
                          obscure: state.obsecure,
                          onChange: (value) => updateFormValidity(),
                          textEditingController: _passwordController,
                          validator: (value) =>
                              Validator.passwordCheck(value ?? ''),
                          suffix: ObsecureIconButtonWidget(
                            obsecure: state.obsecure,
                            onToggle: () => cubit.toggle(),
                          ),
                        ),
                        36.verticalSpace,
                        ValueListenableBuilder(
                          valueListenable: formValidNotifier,
                          builder: (_, isValid, _) {
                            return CustomButton(
                              text: S.current.strLogin,
                              paddingV: 8,
                              isLoading: state.status == Status.LOADING,
                              onTap: () {
                                if (isValid) {
                                  cubit.loginWithBrandId(
                                    req: BrandIdTokenPair(
                                      brandId: _brandIdController.text,
                                      password: _passwordController.text,
                                    ),
                                    onSuccess: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.loginPinScreen,
                                      );
                                    },
                                  );
                                }
                              },
                              borderColor: AppColors.white,
                              bgColor: AppColors.black.withOpacity(.3),
                              radius: context.radius.segmentedControl,
                            );
                          },
                        ),
                      ],
                    ),
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
