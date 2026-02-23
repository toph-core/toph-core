import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_filter_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/pagination_request_entity.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_request/pagination_request_model.dart';

part 'archives_filter_request_model.freezed.dart';
part 'archives_filter_request_model.g.dart';

@freezed
class ArchivesFilterRequestModel
    with _$ArchivesFilterRequestModel
    implements ArchivesFilterRequestEntity {
  const ArchivesFilterRequestModel._();

  const factory ArchivesFilterRequestModel({
    String? searchName,
    @Default(ArchivesFilterType.Today) ArchivesFilterType filterType,
    DateTime? startDate,
    DateTime? endDate,
    @PaginationRequestEntityConverter() PaginationRequestEntity? pagination,
  }) = _ArchivesFilterRequestModel;

  factory ArchivesFilterRequestModel.fromJson(Map<String, dynamic> json) =>
      _$ArchivesFilterRequestModelFromJson(json);

  @override
  Map<String, dynamic> request() {
    Map<String, dynamic> req = {};
    if (pagination != null) {
      req.addAll(pagination!.request());
    }

    switch (filterType) {
      case ArchivesFilterType.All:
        break;

      case ArchivesFilterType.Today:
        req.addAll({
          "start": DateTime.now()
              .subtract(const Duration(hours: 24))
              .toString(),
          "end": DateTime.now().toString(),
        });
        break;

      case ArchivesFilterType.Week:
        req.addAll({
          "start": DateTime.now().subtract(const Duration(days: 7)).toString(),
          "end": DateTime.now().toString(),
        });
        break;

      case ArchivesFilterType.month:
        req.addAll({
          "start": DateTime.now().subtract(const Duration(days: 30)).toString(),
          "end": DateTime.now().toString(),
        });
        break;
    }
    return req;
  }
}
