// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_operation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PendingOperationAdapter extends TypeAdapter<PendingOperation> {
  @override
  final int typeId = 11;

  @override
  PendingOperation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingOperation(
      id: fields[0] as String,
      type: fields[1] as PendingOperationType,
      payload: fields[2] as String,
      tableId: fields[3] as String,
      createdAt: fields[4] as DateTime,
      // Absent on records written before these fields existed — the fields
      // map simply has no entry, so read them defensively.
      coalesceKey: fields[5] as String?,
      retryCount: fields[6] == null ? 0 : fields[6] as int,
      lastAttemptAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PendingOperation obj) {
    writer
      ..writeByte(8)
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
      ..write(obj.coalesceKey)
      ..writeByte(6)
      ..write(obj.retryCount)
      ..writeByte(7)
      ..write(obj.lastAttemptAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingOperationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PendingOperationTypeAdapter extends TypeAdapter<PendingOperationType> {
  @override
  final int typeId = 10;

  @override
  PendingOperationType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PendingOperationType.createOrder;
      case 1:
        return PendingOperationType.addItems;
      case 2:
        return PendingOperationType.payOrder;
      case 3:
        return PendingOperationType.openShift;
      case 4:
        return PendingOperationType.closeShift;
      case 5:
        return PendingOperationType.cancelLineItems;
      case 6:
        return PendingOperationType.cancelOrder;
      case 7:
        return PendingOperationType.transferTable;
      case 8:
        return PendingOperationType.timerAction;
      default:
        return PendingOperationType.createOrder;
    }
  }

  @override
  void write(BinaryWriter writer, PendingOperationType obj) {
    switch (obj) {
      case PendingOperationType.createOrder:
        writer.writeByte(0);
        break;
      case PendingOperationType.addItems:
        writer.writeByte(1);
        break;
      case PendingOperationType.payOrder:
        writer.writeByte(2);
        break;
      case PendingOperationType.openShift:
        writer.writeByte(3);
        break;
      case PendingOperationType.closeShift:
        writer.writeByte(4);
        break;
      case PendingOperationType.cancelLineItems:
        writer.writeByte(5);
        break;
      case PendingOperationType.cancelOrder:
        writer.writeByte(6);
        break;
      case PendingOperationType.transferTable:
        writer.writeByte(7);
        break;
      case PendingOperationType.timerAction:
        writer.writeByte(8);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingOperationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
