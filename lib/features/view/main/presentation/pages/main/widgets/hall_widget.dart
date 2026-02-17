import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/common/custom_loading_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/features/view/main/data/models/cafe_tables/cafe_tables_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/hall/hall_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/show_table_guest_count.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/table_widget.dart';

class HallWidget extends StatefulWidget {
  final HallModel? hall;
  final List<CafeTableModel> tables;
  final bool isLoading;
  const HallWidget({
    super.key,
    required this.tables,
    this.hall,
    required this.isLoading,
  });

  @override
  State<HallWidget> createState() => _HallWidgetState();
}

class _HallWidgetState extends State<HallWidget> {
  final TransformationController _controller = TransformationController();

  @override
  void didUpdateWidget(covariant HallWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hall?.id != widget.hall?.id) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hallWidth = widget.hall?.width ?? 2000.0;
    final hallHeight = widget.hall?.height ?? 1500.0;

    return Expanded(
      child: widget.isLoading
          ? const Center(child: LoadingWidget())
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _controller,
                      minScale: 0.1,
                      maxScale: 2.0,
                      constrained: false,
                      child: Container(
                        width: hallWidth,
                        height: hallHeight,
                        decoration: BoxDecoration(
                          color: context.colors.bgSecondary,
                          borderRadius: context.radius.card20,
                        ),
                        child: Stack(
                          children: widget.tables
                              .map(
                                (table) => TableWidget(
                                  table: table,
                                  onTap: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (context) => ShowTableGuestCount(
                                        tableNumber: table.number,
                                      ),
                                    ).then((value) {
                                      if (value != null && value is int) {
                                        Future.delayed(
                                          const Duration(milliseconds: 500),
                                          () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.detailScreen,
                                            arguments: {
                                              "table": table,
                                              "guest_count": value,
                                            },
                                          ),
                                        );
                                      }
                                    });
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    // Scrollbars
                    ValueListenableBuilder<Matrix4>(
                      valueListenable: _controller,
                      builder: (context, matrix, _) {
                        final scale = matrix.row0[0];
                        final tx = -matrix.row0[3];
                        final ty = -matrix.row1[3];

                        final viewWidth = constraints.maxWidth;
                        final viewHeight = constraints.maxHeight;

                        final contentWidth = hallWidth * scale;
                        final contentHeight = hallHeight * scale;

                        return Stack(
                          children: [
                            if (contentWidth > viewWidth)
                              Positioned(
                                left: 4,
                                right: 4,
                                bottom: 4,
                                child: _buildScrollbar(
                                  isVertical: false,
                                  viewSize: viewWidth,
                                  contentSize: contentWidth,
                                  offset: tx,
                                ),
                              ),
                            if (contentHeight > viewHeight)
                              Positioned(
                                top: 4,
                                bottom: 4,
                                right: 4,
                                child: _buildScrollbar(
                                  isVertical: true,
                                  viewSize: viewHeight,
                                  contentSize: contentHeight,
                                  offset: ty,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Text(
                        "Hall: ${hallWidth.round()}x${hallHeight.round()}",
                        style: context.textStyles.bodyMd,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildScrollbar({
    required bool isVertical,
    required double viewSize,
    required double contentSize,
    required double offset,
  }) {
    final thumbSize = (viewSize / contentSize) * viewSize;
    final maxOffset = contentSize - viewSize;
    final scrollRatio = maxOffset > 0 ? offset / maxOffset : 0.0;
    final thumbOffset = scrollRatio * (viewSize - thumbSize - 8);

    return Container(
      width: isVertical ? 6 : null,
      height: isVertical ? null : 6,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Stack(
        children: [
          Positioned(
            top: isVertical ? thumbOffset : 0,
            left: isVertical ? 0 : thumbOffset,
            child: Container(
              width: isVertical ? 6 : thumbSize,
              height: isVertical ? thumbSize : 6,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
