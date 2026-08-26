import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/extension/number_formatter.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/archives/archives_bloc.dart';
import 'package:mary_ai_pos/gen/assets.gen.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class CheckItem extends StatelessWidget {
  final ArchiveEntity archive;
  final String selectChekId;

  const CheckItem({
    super.key,
    required this.archive,
    required this.selectChekId,
  });

  @override
  Widget build(BuildContext context) {
    // An open bill's `grand_total` (→ [ArchiveEntity.totalPrice]) does not yet
    // include the running table (time) charge — the server folds it in only at
    // payment. Add it here for open bills so the row matches the detail card
    // and `ArchivesQuery.summary`'s revenue; a paid bill already carries it.
    final displayTotal = archive.status.isOpenBill
        ? archive.totalPrice + archive.tableAmount
        : archive.totalPrice;
    return GestureDetector(
      onTap: () => context.read<ArchivesBloc>().add(
        ArchivesEvent.selectArchive(id: archive.id),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: context.radius.buttonLg,
          color: context.colors.bgTritary,
          border: selectChekId == archive.id
              ? Border.all(color: context.colors.bgBrand, width: 1)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  "#${archive.bilNumber}",
                  style: context.textStyles.bold20.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(S.current.strCash, style: context.textStyles.bodyMd),
              ],
            ),
            Row(
              children: [
                Text(
                  "Stol ${archive.tableNumber}",
                  style: context.textStyles.bodyMd,
                ),
                const Spacer(),
                Text(
                  displayTotal.formatN,
                  style: context.textStyles.bold20.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                SvgPicture.asset(
                  Assets.icons.icCalendar.path,
                  height: 24,
                  width: 24,
                ),
                12.wBox,
                Text(
                  archive.opened.toYyyyMmDd,
                  style: context.textStyles.title14.copyWith(fontSize: 16),
                ),
                12.wBox,
                Text(
                  archive.opened.toHourMinute,
                  style: context.textStyles.title14.copyWith(fontSize: 16),
                ),
                10.wBox,
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      // "asdf",
                      "${archive.goodsQuantity} ta mahsulot",
                      style: context.textStyles.title14.copyWith(
                        fontSize: 16,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ).paddingAll(16),
      ),
    );
  }
}
