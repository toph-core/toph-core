import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/utils/order_totals.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/archive_detail_entity.dart';
import 'package:mary_ai_pos/features/view/main/domain/entities/order_food_entity.dart';

class _Good extends OrderFoodEntity {
  _Good({required super.price, super.quantity = 1, super.status})
      : super(id: 'g', name: 'test', comment: '');
}

class _Detail extends ArchiveDetailEntity {
  _Detail({
    super.goods = const [],
    super.servicePercent = 0,
    super.serviceAmount = 0,
    super.grandTotal = 0,
  }) : super(
          id: 'order',
          bilNumber: 1,
          status: OrderStatus.open,
          opened: null,
          paymentType: '',
          tableId: '',
          tableNumber: 1,
          hallName: '',
          cashierId: '',
          cashierName: '',
          guestCount: 0,
          foodCost: 0,
          foodTotal: 0,
          discountPercent: 0,
          discountAmount: 0,
          customerPaidAmount: 0,
          changeAmount: 0,
          comment: '',
        );
}

void main() {
  group('OrderTotals — main formula', () {
    test('simple table: trusts API grand_total when no cancelled lines', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 246000)],
          servicePercent: 20,
          serviceAmount: 49200,
          grandTotal: 295200,
        ),
      );
      expect(t.grandTotal, 295200);
      expect(t.serviceAmount, 49200);
    });

    test('simple table: recomputes when cancelled lines present', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [
            _Good(price: 100000),
            _Good(price: 50000, status: 'cancelled'),
          ],
          servicePercent: 20,
          serviceAmount: 30000, // stale API value
          grandTotal: 180000, // stale — includes cancelled
        ),
      );
      expect(t.itemsAmount, 100000);
      expect(t.serviceAmount, 30000); // prefers API service_amount
      expect(t.grandTotal, 130000); // items + service, ignores stale grand
    });

    test('time-based: service applies to items + table charge', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], servicePercent: 20),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160);
      expect(t.grandTotal, 2016960);
    });

    test('time-based: ignores read-path service_amount, recomputes', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 246000)],
          servicePercent: 20,
          serviceAmount: 49200,
          grandTotal: 295200,
        ),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160);
      expect(t.grandTotal, 2016960);
    });

    test('time-based: infers percent from food-only service_amount', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], serviceAmount: 49200),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160);
    });

    test('cancelled items excluded from items amount', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [
            _Good(price: 100000),
            _Good(price: 50000, status: 'cancelled'),
          ],
          servicePercent: 20,
          grandTotal: 0,
        ),
      );
      expect(t.itemsAmount, 100000);
      expect(t.grandTotal, 120000);
    });

    test('10% discount off base', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 500000)],
          servicePercent: 20,
          grandTotal: 0,
        ),
        discountPercent: 10,
      );
      expect(t.baseTotal, 600000);
      expect(t.discountValue, 60000);
      expect(t.grandTotal, 540000);
    });

    test('flat discount capped at base', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 10000)], grandTotal: 0),
        discountAmount: 50000,
      );
      expect(t.discountValue, 10000);
      expect(t.grandTotal, 0);
    });

    test('includeService=false excludes service from payable total', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 246000)],
          servicePercent: 20,
          grandTotal: 0,
        ),
        includeService: false,
      );
      expect(t.serviceAmount, 49200); // still exposed for toggle UI
      expect(t.grandTotal, 246000);
    });

    test('offline extra added on top of core total', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 100000)],
          servicePercent: 20,
          grandTotal: 0,
        ),
        offlineExtra: 50000,
      );
      // core = 120000, then +50000 offline
      expect(t.grandTotal, 170000);
    });

    test('ROUND half away from zero via .round()', () {
      final a = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 1234)], servicePercent: 15, grandTotal: 0),
      );
      expect(a.serviceAmount, 185);
      final b = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 5)], servicePercent: 10, grandTotal: 0),
      );
      expect(b.serviceAmount, 1);
    });
  });
}
