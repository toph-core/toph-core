import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/common/custom_loading_widget.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/features/view/main/data/models/restaurant_table.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/tab_filter.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/table_widget.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    context.read<MainCubit>().getTables();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MainHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: TabFilter(),
                    ),
                    BlocBuilder<MainCubit, MainState>(
                      builder: (context, state) {
                        if (state.status == Status.LOADING) {
                          return const LoadingWidget();
                        }

                        return Expanded(
                          child: InteractiveViewer(
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(100),
                            minScale: 0.1,
                            maxScale: 2.0,
                            child: Padding(
                              padding: const EdgeInsets.all(100.0),
                              child: Container(
                                width: 2000,
                                height: 1500,
                                decoration: BoxDecoration(
                                  color: context.colors.bgSecondary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Stack(
                                  children:
                                      state.tables
                                          ?.map(
                                            (table) => TableWidget(
                                              table: table,
                                              onTap: () {},
                                            ),
                                          )
                                          .toList() ??
                                      [],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ).paddingSymmetric(vertical: 20),
    );
  }
}
