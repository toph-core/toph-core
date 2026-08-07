// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quarantined_operation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class QuarantinedOperationAdapter extends TypeAdapter<QuarantinedOperation> {
  @override
  final int typeId = 13;

  @override
  QuarantinedOperation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuarantinedOperation(
      id: fields[0] as String,
      type: fields[1] as PendingOperationType,
      payload: fields[2] as String,
      tableId: fields[3] as String,
      createdAt: fields[4] as DateTime,
      quarantinedAt: fields[5] as DateTime,
      reason: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, QuarantinedOperation obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.payload)
      ..writeByte(3)
      ..write(obj.tableId)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.quarantinedAt)
      ..writeByte(6)
      ..write(obj.reason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuarantinedOperationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
