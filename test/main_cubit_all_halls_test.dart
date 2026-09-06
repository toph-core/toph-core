import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/db/entity_registry.dart';
import 'package:mary_ai_pos/core/db/local_database.dart';
import 'package:mary_ai_pos/core/db/payload_normalizer.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/features/view/main/data/repository/tables_repository_impl.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/orders_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/main/main_cubit.dart';

class _FakeLanHub implements LanHubService {
  @override
  Stream<({String tableId, String status})> get onRemoteTableUpdate =>
      const Stream.empty();
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeOrders implements OrdersRepository {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late LocalDatabase db;

  void put(String entity, Map<String, dynamic> data) {
    final spec = kEntitiesByName[entity]!;
    db.upsert(spec, data['id'] as String, PayloadNormalizer.normalize(spec, data));
  }

  setUp(() {
    db = LocalDatabase.open(':memory:');
    put('halls', {
      'id': 'h-1', 'branch_id': 'b-1', 'name': 'Zal 1',
      'width': 1000, 'height': 800, 'deleted_at': null,
    });
    put('halls', {
      'id': 'h-2', 'branch_id': 'b-1', 'name': 'Zal 2',
      'width': 1000, 'height': 800, 'deleted_at': null,
    });
    for (final t in [
      ('t-1', 'h-1', 1),
      ('t-2', 'h-1', 2),
      ('t-3', 'h-2', 3),
    ]) {
      put('cafe_tables', {
        'id': t.$1, 'hall_id': t.$2, 'number': t.$3,
        'pos_x': 10, 'pos_y': 10, 'width': 80, 'height': 80,
        'capacity': 4, 'status': 'free', 'deleted_at': null,
        'rotation': 0, 'shape': 'square', 'table_type': 'simple',
        'price_per_hour': '0',
      });
    }
  });



  test('All pill widens the selection back to every hall', () async {
    final cubit = MainCubit(
      TablesRepositoryImpl(localDb: db),
      _FakeLanHub(),
      _FakeOrders(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.tables?.length, 3, reason: 'initial = all tables');

    cubit.setSelectedHallId('h-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.selectedHallId, 'h-1');
    expect(cubit.state.tables?.length, 2, reason: 'hall filter applied');

    cubit.clearSelectedHallId();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.selectedHallId, isNull, reason: 'All clears the filter');
    expect(cubit.state.tables?.length, 3, reason: 'All shows every table');

    await cubit.close();
  });
}
