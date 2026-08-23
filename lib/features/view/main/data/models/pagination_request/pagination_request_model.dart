import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/pagination_request_entity.dart';

part 'pagination_request_model.freezed.dart';
part 'pagination_request_model.g.dart';

@freezed
class PaginationRequestModel
    with _$PaginationRequestModel
    implements PaginationRequestEntity {
  const PaginationRequestModel._();

  const factory PaginationRequestModel({
    @Default(10) int limit,
    @Default(0) int offset,
  }) = _PaginationRequestModel;

  factory PaginationRequestModel.fromJson(Map<String, dynamic> json) =>
      _$PaginationRequestModelFromJson(json);

  /// The request that continues a list already holding [items] rows.
  ///
  /// [offset] is a **row** offset — it is spent directly as SQL's
  /// `OFFSET ?` (`ArchivesQuery.page`) and was spent the same way by the REST
  /// endpoint this replaced. It used to be computed as `items ~/ limit`, which
  /// is a *page index*: with a full page of 20 on screen it asked for offset
  /// 1, so the next fetch returned rows 2..21 and the newest bill silently
  /// dropped off the top of the list. The same arithmetic broke bill-number
  /// search outright — a search dispatched over a full page skipped its single
  /// match and reported "not found" for a check that was sitting in the
  /// database.
  factory PaginationRequestModel.calculate({
    required int items,
    required int limit,
  }) {
    final safeLimit = limit <= 0 ? 1 : limit;
    return PaginationRequestModel(
      limit: safeLimit,
      offset: items < 0 ? 0 : items,
    );
  }

  @override
  Map<String, dynamic> request() {
    return {'limit': limit, 'offset': offset};
  }
}

class PaginationRequestEntityConverter
    implements JsonConverter<PaginationRequestEntity?, Map<String, dynamic>?> {
  const PaginationRequestEntityConverter();

  @override
  PaginationRequestEntity? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return PaginationRequestModel.fromJson(json);
  }

  @override
  Map<String, dynamic>? toJson(PaginationRequestEntity? object) {
    if (object == null) return null;
    return object is PaginationRequestModel
        ? object.toJson()
        : {'limit': object.limit, 'offset': object.offset};
  }
}
