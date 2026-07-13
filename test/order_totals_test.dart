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
  // docs/order-total-calculation.md §10 misollari — backend bilan bir xil.
  group('OrderTotals — guide worked examples', () {
    test('Example A: oddiy stol, naqd', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], servicePercent: 20),
      );
      expect(t.itemsAmount, 246000);
      expect(t.serviceAmount, 49200);
      expect(t.baseTotal, 295200);
      expect(t.grandTotal, 295200);
    });

    test('Example B: time-based stol — xizmat stol haqiga ham', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], servicePercent: 20),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160); // ROUND((246000+1434800)×20%)
      expect(t.grandTotal, 2016960); // 295200 EMAS
    });

    test('Example C: 10% chegirma base_total dan', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 500000)], servicePercent: 20),
        discountPercent: 10,
      );
      expect(t.baseTotal, 600000);
      expect(t.discountValue, 60000);
      expect(t.grandTotal, 540000);
    });
  });

  group('OrderTotals — qoidalar', () {
    test('bekor qilingan itemlar hisobga olinmaydi', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [
          _Good(price: 100000),
          _Good(price: 50000, status: 'cancelled'),
        ], servicePercent: 20),
      );
      expect(t.itemsAmount, 100000);
      expect(t.grandTotal, 120000);
    });

    test('fiks chegirma baseTotal dan oshsa grand 0 ga qisqaradi', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 10000)]),
        discountAmount: 50000,
      );
      expect(t.discountValue, 10000); // base bilan cheklangan
      expect(t.grandTotal, 0);
    });

    test('stol haqi yo\'q — server service_amount ga ishonamiz', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 246000)],
          servicePercent: 20,
          serviceAmount: 50000, // server bergani ustun
        ),
      );
      expect(t.serviceAmount, 50000);
    });

    test('stol haqi bor — read-path service_amount e\'tiborsiz, qayta hisob', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 246000)],
          servicePercent: 20,
          serviceAmount: 49200, // faqat mahsulot ustidan (read path)
        ),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160);
    });

    test('foiz kelmagan — service_amount dan foiz tiklanadi', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], serviceAmount: 49200),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 336160); // pct = 49200/246000 = 20%
    });

    test('foiz navigatsiya fallback dan olinadi', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)]),
        servicePercentFallback: 20,
      );
      expect(t.serviceAmount, 49200);
    });

    test('includeService=false — xizmat 0', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], servicePercent: 20),
        includeService: false,
      );
      expect(t.serviceAmount, 0);
      expect(t.grandTotal, 246000);
    });

    test('offline extra xizmat bazasiga kiradi', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 100000)], servicePercent: 20),
        offlineExtra: 50000,
      );
      expect(t.itemsAmount, 150000);
      expect(t.serviceAmount, 30000);
    });

    test('ROUND — truncate emas (x.5 yuqoriga)', () {
      // 1234 × 15% = 185.1 → 185; 5 × 10% = 0.5 → 1
      final a = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 1234)], servicePercent: 15),
      );
      expect(a.serviceAmount, 185);
      final b = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 5)], servicePercent: 10),
      );
      expect(b.serviceAmount, 1);
    });

    test('items bo\'sh — grand_total fallback saqlanadi', () {
      final t = OrderTotals.fromDetail(_Detail(grandTotal: 100000));
      expect(t.grandTotal, 100000);
    });
  });
}
