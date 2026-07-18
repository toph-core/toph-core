import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/save_order_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/department_selection/department_selection_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/detail/detail_bloc.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/table_timer/table_timer_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/department_selection/widgets/category_selection_grid.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/order_actions_bar.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/order_side_bar_widget.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/detail/widgets/top_bar_widget.dart';

/// Intermediate screen: pick a department filter, then a category.
/// Uses the same chrome as [DetailScreen] (top bar, actions, sidebar).
class DepartmentSelectionScreen extends StatefulWidget {
  const DepartmentSelectionScreen({super.key});

  @override
  State<DepartmentSelectionScreen> createState() =>
      _DepartmentSelectionScreenState();
}

class _DepartmentSelectionScreenState extends State<DepartmentSelectionScreen> {
  late final args =
      ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ?? {};
  late final CafeTableModel? cafeTable = args['table'] as CafeTableModel?;
  late final int guestCount = args['guest_count'] as int? ?? 0;
  late final SaveOrderEntity? savedOrders =
      args['saved_orders'] as SaveOrderEntity?;

  late ValueNotifier<bool> showVirtualKeyboard = ValueNotifier<bool>(false);
  final TextEditingController controller = TextEditingController();

  late final TableTimerCubit _timerCubit = inject<TableTimerCubit>();
  late DetailBloc _detailBloc;
  late final DepartmentSelectionCubit _deptCubit =
      inject<DepartmentSelectionCubit>()..load();

  TableStatus tableStatus = TableStatus.none;
  bool _initDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;

    tableStatus = args['table_status'] as TableStatus? ?? TableStatus.none;

    final hasSavedGoods =
        savedOrders != null && savedOrders!.createOrderRequest.foods.isNotEmpty;

    _detailBloc = inject<DetailBloc>()
      ..add(const DetailEvent.started())
      ..add(
        DetailEvent.initSavedGoods(
          savedGoods: savedOrders?.createOrderRequest.foods ?? [],
        ),
      );

    if (tableStatus == TableStatus.busy &&
        cafeTable != null &&
        !hasSavedGoods) {
      _detailBloc.add(DetailEvent.fetchBillOrders(billId: cafeTable!.id));
    }

    final isTimeBased = cafeTable?.tableType?.toLowerCase() == 'time_based';
    if (isTimeBased && tableStatus == TableStatus.free) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _autoStartTimedOrder(),
      );
    }
  }

  @override
  void dispose() {
    _timerCubit.close();
    _detailBloc.close();
    _deptCubit.close();
    showVirtualKeyboard.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _autoStartTimedOrder() async {
    if (!mounted || cafeTable == null) return;
    final orderId = await _timerCubit.createTimedOrderAndStart(
      tableId: cafeTable!.id,
      guestCount: guestCount,
    );
    if (!mounted) return;

    if (orderId != null) {
      _detailBloc.add(DetailEvent.setActiveOrderId(orderId: orderId));
    }
    setState(() => tableStatus = TableStatus.busy);
    context.read<MainCubit>().updateTableStatus(
      cafeTable!.id,
      TableStatus.busy,
    );
    _detailBloc.add(
      DetailEvent.fetchBillOrders(billId: cafeTable!.id, force: true),
    );
  }

  void _openMenu(CategoryModel category) {
    Navigator.pushNamed(
      context,
      AppRoutes.detailScreen,
      arguments: {
        'table': cafeTable,
        'guest_count': guestCount,
        'table_status': tableStatus,
        'saved_orders': savedOrders,
        'initial_category_id': category.id,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _detailBloc),
        BlocProvider.value(value: _timerCubit),
        BlocProvider.value(value: _deptCubit),
      ],
      child: KeyboardDismisser(
        child: BlocListener<DetailBloc, DetailState>(
          listenWhen: (prev, curr) =>
              prev.activeOrderId != curr.activeOrderId &&
              curr.activeOrderId != null &&
              !_timerCubit.state.shouldShow,
          listener: (context, state) {
            _timerCubit.fetchTimer(orderId: state.activeOrderId!);
          },
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
                  child: Column(
                    children: [
                      TopBarWidget(
                        cafeTable: cafeTable,
                        showKeyboard: showVirtualKeyboard,
                        textEditingController: controller,
                        guestCount: guestCount,
                      ),
                      OrderActionsBar(
                        tableId: cafeTable?.id,
                        guestCount: guestCount,
                        tableStatus: tableStatus,
                        cafeTable: cafeTable,
                        onTableStatusChanged: (s) =>
                            setState(() => tableStatus = s),
                      ),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final sidebarW = PosBreakpoints.pickThree<double>(
                              context,
                              compact: PosDimensions.cartPanelCompact,
                              comfortable:
                                  PosDimensions.cartPanelComfortable,
                              large: 440.0,
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: CategorySelectionGrid(
                                    onCategorySelected: _openMenu,
                                  ),
                                ),
                                SizedBox(
                                  width: sidebarW,
                                  child: OrderSidebar(
                                    tableId: cafeTable?.id,
                                    cafeTable: cafeTable,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: showVirtualKeyboard,
                  builder: (context, value, _) {
                    if (!value) return const SizedBox.shrink();
                    return Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        top: false,
                        child: StyledVirtualKeyboard(
                          controller: controller,
                          height: context.h * .32,
                          onClose: () => showVirtualKeyboard.value = false,
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
    );
  }
}
