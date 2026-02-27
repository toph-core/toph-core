import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:mary_ai_pos/core/api/api.dart';
import 'package:mary_ai_pos/core/common/custom_hover_effect_widget.dart';
import 'package:mary_ai_pos/core/common/custom_text_field.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/notification/notification_bloc.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

enum NotificationFilterType { all, today, week, month }

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final TextEditingController _searchController = TextEditingController();
  NotificationFilterType _selectedFilter = NotificationFilterType.today;

  final List<_NotificationItem> _items = List.generate(
    18,
    (_) => const _NotificationItem(
      orderNumber: '#1025',
      tableName: '13-stol',
      description: '16-stol buyurtmasi yetkazildi.',
    ),
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _getCrossAxisCount(double width) {
    if (width < 820) return 1;
    if (width < 1280) return 2;
    return 3;
  }

  final List<String> names = [
    S.current.all,
    S.current.today,
    S.current.week,
    S.current.month,
  ];

  @override
  Widget build(BuildContext context) {
    final List<_FilterChipData> filters = [
      const _FilterChipData(label: 'Hammasi', type: NotificationFilterType.all),
      const _FilterChipData(label: 'Bugun', type: NotificationFilterType.today),
      const _FilterChipData(label: 'Hafta', type: NotificationFilterType.week),
      const _FilterChipData(label: 'Oy', type: NotificationFilterType.month),
    ];

    return Scaffold(
      backgroundColor: context.colors.bgTritary,
      body: BlocProvider(
        create: (context) =>
            NotificationBloc()..add(const NotificationEvent.started()),
        child: BlocBuilder<NotificationBloc, NotificationState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.bgDefault,
                    borderRadius: context.radius.card24,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: CustomHoverEffectWidget(
                          bgColor: context.colors.bgSecondary,
                          onTap: () => Navigator.pop(context),
                          borderRadius: context.radius.buttonLg,
                          child: SvgPicture.asset(
                            AppIcons.icArrowLeft,
                            colorFilter: ColorFilter.mode(
                              context.colors.iconDefault,
                              BlendMode.srcIn,
                            ),
                          ).paddingAll(14),
                        ),
                      ),
                      12.wBox,
                      Text(
                        'Bildirishnomalar',
                        style: context.textStyles.bold24.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      24.wBox,
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: CustomTextField(
                            hintText: 'Qidirish',
                            textInputType: TextInputType.text,
                            textEditingController: _searchController,
                            suffixIcon: SvgPicture.asset(
                              AppIcons.icSearch,
                              colorFilter: ColorFilter.mode(
                                context.colors.iconSecondary,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                      8.wBox,
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: CustomHoverEffectWidget(
                          onTap: () async {
                            final pickedRange = await showDateRangePicker(
                          context: context,
                          initialDateRange: DateTimeRange(
                            start: DateTime.now(),
                            end: DateTime.now(),
                          ),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 10),
                          ),
                          initialEntryMode: DatePickerEntryMode.calendarOnly,
                          builder: (context, child) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 400.0,
                                  maxHeight: 600.0,
                                ),
                                child: child,
                              ),
                            );
                          },
                        );
                        if (pickedRange != null) {
                          context.read<NotificationBloc>().add(
                            NotificationEvent.updateDateFilterEvent(
                              start: pickedRange.start,
                              end: pickedRange.end,
                            ),
                          );
                        }
                          },
                          bgColor: state.filterType == ArchivesFilterType.date? context.colors.buttonBrand : context.colors.bgSecondary,
                          borderRadius: context.radius.buttonLg,
                          child: SvgPicture.asset(
                            AppIcons.icCalendar,
                            colorFilter: ColorFilter.mode(
                              state.filterType == ArchivesFilterType.date? context.colors.buttonSecondary : context.colors.buttonBrand,
                              BlendMode.srcIn,
                            ),
                          ).paddingAll(12),
                        ),
                      ),
                      8.wBox,
                      Row(
                        children: List.generate(
                          ArchivesFilterType.values.length - 1,
                          (index) => SizedBox(
                            height: 52,
                            child: CustomHoverEffectWidget(
                              onTap: () => context.read<NotificationBloc>().add(NotificationEvent.updateFilterType(filterType: ArchivesFilterType.values[index])),
                              bgColor: state.filterType == ArchivesFilterType.values[index]
                                  ? context.colors.buttonBrand
                                  : context.colors.bgSecondary,
                              borderRadius: context.radius.buttonLg,
                              child: Center(
                                child: Text(
                                  names[index],
                                  style: context.textStyles.bold16.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color:  state.filterType == ArchivesFilterType.values[index]
                                        ? context.colors.textOnBrand
                                        : context.colors.textDefault,
                                  ),
                                ).paddingSymmetric(horizontal: 20),
                              ),
                            ).paddingSymmetric(horizontal: 8),
                          ).paddingOnly(),
                        ),
                      ),
                    ],
                  ).paddingAll(16),
                ),
                16.hBox,
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.bgDefault,
                      borderRadius: context.radius.card24,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = _getCrossAxisCount(
                          constraints.maxWidth,
                        );

                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 120,
                              ),
                          itemBuilder: (context, index) =>
                              _NotificationCard(item: _items[index]),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ).paddingAll(32),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final _NotificationItem item;

  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bgSecondary,
        borderRadius: context.radius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.orderNumber,
                style: context.textStyles.semibold24.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                item.tableName,
                style: context.textStyles.bold24.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          8.hBox,
          Text(
            item.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.bodyMd.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ).paddingAll(16),
    );
  }
}

class _NotificationItem {
  final String orderNumber;
  final String tableName;
  final String description;

  const _NotificationItem({
    required this.orderNumber,
    required this.tableName,
    required this.description,
  });
}

class _FilterChipData {
  final String label;
  final NotificationFilterType type;

  const _FilterChipData({required this.label, required this.type});
}
