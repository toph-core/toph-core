import 'package:freezed_annotation/freezed_annotation.dart';

part 'branch_shift_model.freezed.dart';
part 'branch_shift_model.g.dart';

/// The branch's shift, in the exact shape both delivery paths produce.
///
/// One class parses two sources on purpose: the REST response from
/// `/api/v1/branch-shifts`, and the replicated row from `/sync/pull` or a LAN
/// peer's broadcast. The backend's `BranchShiftResponse` field names mirror the
/// `branch_shifts` columns one-for-one so that stays true; if the two ever
/// diverge, this model is the thing that breaks and says so.
///
/// Money arrives as a string in both ("100", "0.00"): the REST layer marshals
/// `numeric` as a string, and the registry's `numericKeys` coerces the
/// replicated row's JSON number to one so both agree. [_parseIntFlex] accepts
/// either anyway rather than trusting that.
@freezed
class BranchShiftModel with _$BranchShiftModel {
  const factory BranchShiftModel({
    @Default('') String id,
    @JsonKey(name: 'branch_id') @Default('') String branchId,
    @JsonKey(name: 'opened_by') String? openedBy,
    @JsonKey(name: 'closed_by') String? closedBy,
    @JsonKey(name: 'opened_at', fromJson: _parseLocal) DateTime? openedAt,
    @JsonKey(name: 'closed_at', fromJson: _parseLocal) DateTime? closedAt,
    @JsonKey(name: 'opening_cash', fromJson: _parseIntFlex)
    @Default(0)
    int openingCash,
    @JsonKey(name: 'opening_card', fromJson: _parseIntFlex)
    @Default(0)
    int openingCard,
    @JsonKey(name: 'closing_cash', fromJson: _parseIntFlex)
    @Default(0)
    int closingCash,
    @JsonKey(name: 'closing_card', fromJson: _parseIntFlex)
    @Default(0)
    int closingCard,
    String? notes,
    @JsonKey(name: 'created_at', fromJson: _parseLocal) DateTime? createdAt,
    @JsonKey(name: 'updated_at', fromJson: _parseLocal) DateTime? updatedAt,
  }) = _BranchShiftModel;

  const BranchShiftModel._();

  factory BranchShiftModel.fromJson(Map<String, dynamic> json) =>
      _$BranchShiftModelFromJson(json);

  /// Whether this is the shift the venue is currently trading under.
  ///
  /// The same predicate the backend's partial unique index and
  /// `BranchShiftQuery.activeShift` use, so the three cannot drift.
  bool get isOpen => closedAt == null;
}

/// Money as an int, from whichever of the three shapes it arrives in: an int
/// (replicated row, whole number), a num ("100.50" decoded from JSON), or a
/// string (REST). A value that will not parse is 0 — the same fallback the
/// shift screens already apply to their own numpad input.
int _parseIntFlex(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final asInt = int.tryParse(v);
    if (asInt != null) return asInt;
    return double.tryParse(v)?.toInt() ?? 0;
  }
  return 0;
}

/// Backend timestamps are UTC; the UI shows local. Converted once, here, so no
/// screen has to remember to.
DateTime? _parseLocal(Object? v) {
  if (v == null) return null;
  if (v is String) {
    if (v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }
  if (v is DateTime) return v.toLocal();
  return null;
}
