import 'package:mary_ai_pos/core/database/local_database.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';

class TransactionsRepositoryImpl implements TransactionsRepository {
  final LocalDatabase _localDb;

  TransactionsRepositoryImpl({required LocalDatabase localDb}) : _localDb = localDb;

  @override
  Stream<List<Map<String, dynamic>>> watchTransactionGroups() =>
      _localDb.watchTransactionGroups();

  @override
  List<Map<String, dynamic>> getTransactionGroups() => _localDb.getTransactionGroups();

  @override
  Stream<List<Map<String, dynamic>>> watchCashRegisters() => _localDb.watchCashRegisters();

  @override
  List<Map<String, dynamic>> getCashRegisters() => _localDb.getCashRegisters();
}
