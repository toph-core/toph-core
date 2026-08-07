// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'print_job.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PrintJobAdapter extends TypeAdapter<PrintJob> {
  @override
  final int typeId = 12;

  @override
  PrintJob read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PrintJob(
      id: fields[0] as String,
      jobType: fields[1] as String,
      entryId: fields[2] as String,
      payloadBase64: fields[3] as String,
      connectionType: fields[4] as String,
      ip: fields[5] as String,
      port: fields[6] as int,
      state: fields[7] as String,
      createdAt: fields[8] as DateTime,
      claimedAt: fields[9] as DateTime?,
      printedAt: fields[10] as DateTime?,
      retryCount: fields[11] as int,
      lastError: fields[12] as String?,
      ownerTerminalId: fields[13] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PrintJob obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.jobType)
      ..writeByte(2)
      ..write(obj.entryId)
      ..writeByte(3)
      ..write(obj.payloadBase64)
      ..writeByte(4)
      ..write(obj.connectionType)
      ..writeByte(5)
      ..write(obj.ip)
      ..writeByte(6)
      ..write(obj.port)
      ..writeByte(7)
      ..write(obj.state)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.claimedAt)
      ..writeByte(10)
      ..write(obj.printedAt)
      ..writeByte(11)
      ..write(obj.retryCount)
      ..writeByte(12)
      ..write(obj.lastError)
      ..writeByte(13)
      ..write(obj.ownerTerminalId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrintJobAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
