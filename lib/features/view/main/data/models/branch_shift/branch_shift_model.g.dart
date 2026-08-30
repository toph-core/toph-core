// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'branch_shift_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BranchShiftModelImpl _$$BranchShiftModelImplFromJson(
        Map<String, dynamic> json) =>
    _$BranchShiftModelImpl(
      id: json['id'] as String? ?? '',
      branchId: json['branch_id'] as String? ?? '',
      openedBy: json['opened_by'] as String?,
      closedBy: json['closed_by'] as String?,
      openedAt: _parseLocal(json['opened_at']),
      closedAt: _parseLocal(json['closed_at']),
      openingCash: json['opening_cash'] == null
          ? 0
          : _parseIntFlex(json['opening_cash']),
      openingCard: json['opening_card'] == null
          ? 0
          : _parseIntFlex(json['opening_card']),
      closingCash: json['closing_cash'] == null
          ? 0
          : _parseIntFlex(json['closing_cash']),
      closingCard: json['closing_card'] == null
          ? 0
          : _parseIntFlex(json['closing_card']),
      notes: json['notes'] as String?,
      createdAt: _parseLocal(json['created_at']),
      updatedAt: _parseLocal(json['updated_at']),
    );

Map<String, dynamic> _$$BranchShiftModelImplToJson(
        _$BranchShiftModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'branch_id': instance.branchId,
      'opened_by': instance.openedBy,
      'closed_by': instance.closedBy,
      'opened_at': instance.openedAt?.toIso8601String(),
      'closed_at': instance.closedAt?.toIso8601String(),
      'opening_cash': instance.openingCash,
      'opening_card': instance.openingCard,
      'closing_cash': instance.closingCash,
      'closing_card': instance.closingCard,
      'notes': instance.notes,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
