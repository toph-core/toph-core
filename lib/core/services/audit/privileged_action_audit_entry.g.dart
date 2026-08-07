// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'privileged_action_audit_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PrivilegedActionAuditEntryAdapter
    extends TypeAdapter<PrivilegedActionAuditEntry> {
  @override
  final int typeId = 14;

  @override
  PrivilegedActionAuditEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PrivilegedActionAuditEntry(
      id: fields[0] as String,
      action: fields[1] as String,
      timestamp: fields[2] as DateTime,
      approved: fields[3] as bool,
      verifiedOffline: fields[4] as bool,
      reason: fields[5] as String?,
      approverUserId: fields[6] as String?,
      approverName: fields[7] as String?,
      requestedByUserId: fields[8] as String?,
      requestedByName: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PrivilegedActionAuditEntry obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.action)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.approved)
      ..writeByte(4)
      ..write(obj.verifiedOffline)
      ..writeByte(5)
      ..write(obj.reason)
      ..writeByte(6)
      ..write(obj.approverUserId)
      ..writeByte(7)
      ..write(obj.approverName)
      ..writeByte(8)
      ..write(obj.requestedByUserId)
      ..writeByte(9)
      ..write(obj.requestedByName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivilegedActionAuditEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
