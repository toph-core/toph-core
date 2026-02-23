import 'package:device_preview/device_preview.dart' hide VirtualKeyboard;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/detail_screen_mixin.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/order_side_bar_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/produc_grid_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/top_bar_widget.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> with DetailScreenMixin {
  late final args =
      ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
  late final CafeTableModel? cafeTable = args['table'];
  late final int guestCount = args['guest_count'] ?? 0;
  late final TableStatus tableStatus = args['table_status'];
  late ValueNotifier<bool> showVirtualKeyboard = ValueNotifier<bool>(false);
  final TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => inject<DetailCubit>()..getCategories(),
      child: KeyboardDismisser(
        child: Scaffold(
          backgroundColor: context.colors.bgSecondary,
          body: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (showVirtualKeyboard.value) {
                    showVirtualKeyboard.value = false;
                  }
                },
                child: Row(
                  spacing: 16,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        spacing: 12,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TopBarWidget(
                            cafeTable: cafeTable,
                            showKeyboard: showVirtualKeyboard,
                            textEditingController: controller,
                          ),
                          const Expanded(child: ProductGridWidget()),
                        ],
                      ),
                    ),
                    Expanded(
                      child: OrderSidebar(
                        tableId: cafeTable?.id,
                        guestCount: guestCount,
                        tableStatus: tableStatus,
                      ),
                    ),
                  ],
                ).paddingAll(32),
              ),
              ValueListenableBuilder(
                valueListenable: showVirtualKeyboard,
                builder: (context, value, child) {
                  return value
                      ? Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.bgSecondary,
                            ),
                            child: SafeArea(
                              child: VirtualKeyboard(
                                height: context.h * .3,
                                customLayoutKeys:
                                    VirtualKeyboardDefaultLayoutKeys([
                                      VirtualKeyboardDefaultLayouts.English,
                                    ]),
                                textColor: Colors.black,
                                fontSize: 24,
                                textController: controller,
                                type: VirtualKeyboardType.Alphanumeric,
                                // postKeyPress: _onKeyPress,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
