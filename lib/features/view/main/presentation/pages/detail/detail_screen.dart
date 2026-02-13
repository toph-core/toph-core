import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/order_side_bar_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/produc_grid_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/top_bar_widget.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final CafeTableModel cafeTable =
      ModalRoute.of(context)?.settings.arguments as CafeTableModel;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => inject<DetailCubit>()..getCategories(),
      child: KeyboardDismisser(
        child: Scaffold(
          backgroundColor: context.colors.bgSecondary,
          body: Row(
            spacing: 16, 
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  spacing: 12,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TopBarWidget(cafeTable: cafeTable),
                    const Expanded(child: ProductGridWidget()),
                  ],
                ),
              ),
              const Expanded(child: OrderSidebar()),
            ],
          ).paddingAll(32),
        ),
      ),
    );
  }
}
