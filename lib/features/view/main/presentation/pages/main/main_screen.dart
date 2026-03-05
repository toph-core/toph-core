import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_loading_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/list_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/orders/orders_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/shift/shift_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/hall_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/tab_filter.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((v) {
      print("bu user malumotlari ${context.read<UserBloc>().state.userMOdel?.toJson()}");
      if (context.read<UserBloc>().state.userMOdel != null &&
          context.read<UserBloc>().state.userMOdel!.role == UserRole.admin) {
        context.read<ShiftBloc>().add(const ShiftEvent.checkShift());
      }
    });
    context.read<MainCubit>().getHalls();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bgSecondary,
      body: BlocProvider(
        create: (context) =>
            inject<SavedOrdersBloc>()..add(const SavedOrdersEvent.started()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MainHeader(),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: context.radius.card24,
                ),
                child: BlocBuilder<MainCubit, MainState>(
                  builder: (context, state) {
                    if (state.isLoading) {
                      return const Expanded(
                        child: Center(child: LoadingWidget()),
                      );
                    }

                    return Column(
                      spacing: 16,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TabFilter(
                          halls: state.halls ?? [],
                          selectedHallId: state.selectedHallId,
                          isLoading: state.status == Status.OTHER_LOADING,
                        ),
                        HallWidget(
                          isLoading: state.status == Status.LOADING,
                          tables: state.tables ?? [],
                          hall: state.halls?.firstWhereOrNull(
                            (item) => item.id == state.selectedHallId,
                          ),
                        ),
                      ],
                    ).paddingAll(16);
                  },
                ),
              ),
            ),
          ],
        ),
      ).paddingSymmetric(vertical: 20, horizontal: 32),
    );
  }
}
