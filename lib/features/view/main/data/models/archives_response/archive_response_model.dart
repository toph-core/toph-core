import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/features/view/main/data/models/archive/archive_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/pagination_response/pagination_response_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archives_response_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/pagination_response_entity.dart';

part 'archive_response_model.freezed.dart';
part 'archive_response_model.g.dart';

@freezed
class ArchiveResponseModel
    with _$ArchiveResponseModel
    implements ArchivesResponseEntity {
  const ArchiveResponseModel._();

  const factory ArchiveResponseModel({
    @ArchiveEntityListConverter()
    required List<ArchiveEntity> archives,
    @PaginationResponseEntityConverter()
    required PaginationResponseEntity pagination,
  }) = _ArchiveResponseModel;

  factory ArchiveResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ArchiveResponseModelFromJson(json);

  @override
  ArchivesResponseEntity updateModel(ArchivesResponseEntity newModel) {
    final Map<String, ArchiveEntity> uniqueMap = {};
    for (final item in newModel.archives) {
      uniqueMap[item.id] = item;
    }

    return copyWith(
      archives: uniqueMap.values.toList(),
      pagination: newModel.pagination,
    );
  }
}
