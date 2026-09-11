import 'package:flutter_test/flutter_test.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/int_extension.dart';
import 'package:mary_ai_pos/core/pricing/order_totals.dart';
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
    super.tableAmount = 0,
    super.pausePeriods = const [],
    super.activePeriods = const [],
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
  group('a fractional price is money, not a rounding error', () {
    // Reconstructed from a payment this repository actually lost.
    //
    // Order 62879273 held four lines — 50000, 10000, 2x2000 and one at 666.66,
    // a price the backend derives as cost x (1 + markup%). The replica stores
    // canonicalised numerics as strings, so that line arrived as "666.66", and
    // `parseInt` — which is `int.tryParse(...) ?? 0` — turned it into ZERO.
    //
    // The till asked for 76933. The backend sums the exact decimals and rounds
    // once: 64666.66 + 20% = 77600. Short by 667, against a tolerance of 1, so
    // `PayOrderBill` refused the settle, the API answered 400, and the outbox
    // quarantined the payment. The customer was undercharged and the takings
    // were lost, from one `?? 0`.
    test('the line the backend charges is the line the till charges', () {
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [
            _Good(price: 50000),
            _Good(price: 10000),
            _Good(price: 2000, quantity: 2),
            _Good(price: 666.66),
          ],
          servicePercent: 20,
        ),
      );

      expect(t.itemsAmount, 64667, reason: 'the fractional line is not free');
      expect(t.grandTotal, 77600, reason: "the backend's figure, exactly");
    });

    test('cents survive the replica round trip', () {
      // The canonical string form the normalizer writes for 666.66.
      expect(parseMoney('666.66'), 666.66);
      expect(parseMoney(666.66), 666.66);
      expect(parseMoney('50000'), 50000);
      expect(parseMoney(null), 0);
      // And the integer parser no longer silently zeroes one.
      expect(parseInt('666.66'), 667);
    });
  });

  group('service is charged on items, never on the table charge', () {
    // The venue's rule, stated plainly because three different code paths
    // priced this bill and one of them disagreed: the waiter's close receipt
    // added the hourly charge into the service base, so the paper asked for
    // more than the till took and more than the cashier's receipt for the same
    // bill showed.
    //
    // 100 000 of food, 60 000 of table time, 10% service.
    // Right: 100 000 + 60 000 + 10 000 = 170 000.
    // Wrong: service on 160 000 = 16 000 → 176 000.
    test('the engine puts service on food only', () {
      final t = OrderTotals.compute(
        itemsAmount: 100000,
        tableCharge: 60000,
        servicePercent: 10,
      );

      expect(t.serviceAmount, 10000);
      expect(t.grandTotal, 170000);
    });

    test('the read path agrees with it', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 100000)], servicePercent: 10),
        tableCharge: 60000,
      );

      expect(t.serviceAmount, 10000);
      expect(t.grandTotal, 170000);
    });
  });

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

    test('a bill edited offline prices from the local rows, not the stale '
        'server grand_total', () {
      // The bill synced at 246000 + 20% = 295200. A line was then rung in
      // offline, so the local `order_items` rows now sum to 300000 while
      // `grand_total` still carries the pre-edit figure.
      //
      // This branch used to take `grand_total` whenever no line was
      // cancelled, and `offlineExtra` — which once compensated by summing the
      // legacy Hive queue — has had no callers since item writes moved onto
      // the outbox. So the cashier collected 295200 on a 360000 bill, the
      // queued pay came back 400 insufficient, and the bill reopened unpaid.
      final t = OrderTotals.fromDetail(
        _Detail(
          goods: [_Good(price: 300000)],
          servicePercent: 20,
          grandTotal: 295200, // stale — priced before the offline add
        ),
      );
      expect(t.itemsAmount, 300000);
      expect(t.serviceAmount, 60000);
      expect(t.grandTotal, 360000, reason: 'the local rows are the authority');
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

    test('time-based: service applies to items only, not table charge', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], servicePercent: 20),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 49200);
      expect(t.grandTotal, 1730000);
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
      expect(t.serviceAmount, 49200);
      expect(t.grandTotal, 1730000);
    });

    test('time-based: infers percent from food-only service_amount', () {
      final t = OrderTotals.fromDetail(
        _Detail(goods: [_Good(price: 246000)], serviceAmount: 49200),
        tableCharge: 1434800,
      );
      expect(t.serviceAmount, 49200);
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

  // Phase 3 — the pure engine. Every input is a local number; no server
  // aggregate is consulted, so these are the totals an offline terminal
  // produces and the backend re-derives at pay time.
  group('OrderTotals.compute — pure local engine', () {
    test('items only: service is a percentage of the food sum', () {
      final t = OrderTotals.compute(itemsAmount: 246000, servicePercent: 20);
      expect(t.itemsAmount, 246000);
      expect(t.serviceAmount, 49200);
      expect(t.baseTotal, 295200);
      expect(t.grandTotal, 295200);
    });

    test('service is charged on items only, never on the table charge', () {
      final t = OrderTotals.compute(
        itemsAmount: 246000,
        tableCharge: 1434800,
        servicePercent: 20,
      );
      // Servicing the whole base instead would give 336160 — the single most
      // load-bearing difference between this formula and a naive one.
      expect(t.serviceAmount, 49200);
      expect(t.baseTotal, 1730000);
      expect(t.grandTotal, 1730000);
    });

    test('a table charge with no food carries no service at all', () {
      final t = OrderTotals.compute(
        itemsAmount: 0,
        tableCharge: 100000,
        servicePercent: 20,
      );
      expect(t.serviceAmount, 0);
      expect(t.grandTotal, 100000);
    });

    test('percentage discount applies to the whole base', () {
      final t = OrderTotals.compute(
        itemsAmount: 500000,
        servicePercent: 20,
        discountPercent: 10,
      );
      expect(t.baseTotal, 600000);
      expect(t.discountValue, 60000);
      expect(t.grandTotal, 540000);
    });

    test('flat discount is capped at the base, never negative', () {
      final t = OrderTotals.compute(itemsAmount: 10000, discountAmount: 50000);
      expect(t.discountValue, 10000);
      expect(t.grandTotal, 0);
    });

    test('percent wins when both discount kinds are supplied', () {
      final t = OrderTotals.compute(
        itemsAmount: 100000,
        discountPercent: 10,
        discountAmount: 90000,
      );
      expect(t.discountValue, 10000);
      expect(t.grandTotal, 90000);
    });

    test('includeService=false drops service but still reports it', () {
      final t = OrderTotals.compute(
        itemsAmount: 246000,
        servicePercent: 20,
        includeService: false,
      );
      expect(t.serviceAmount, 49200); // the toggle still needs the number
      expect(t.baseTotal, 246000);
      expect(t.grandTotal, 246000);
    });

    test('rounds half away from zero, at service and at discount', () {
      expect(
        OrderTotals.compute(itemsAmount: 1234, servicePercent: 15)
            .serviceAmount,
        185, // 185.1
      );
      expect(
        OrderTotals.compute(itemsAmount: 5, servicePercent: 10).serviceAmount,
        1, // 0.5 -> 1
      );
      expect(
        OrderTotals.compute(itemsAmount: 105, discountPercent: 50)
            .discountValue,
        53, // 52.5 -> 53
      );
    });

    test('an empty check is all zeros, not a crash', () {
      final t = OrderTotals.compute(itemsAmount: 0);
      expect(t.itemsAmount, 0);
      expect(t.serviceAmount, 0);
      expect(t.baseTotal, 0);
      expect(t.grandTotal, 0);
    });
  });

  // The payment screen renders `forPayment(...).grandTotal` and PaymentBloc
  // charges `forPayment(...).grandTotal` off the same state. These pin the
  // input demux the two call sites used to each re-derive on their own — the
  // divergence that let a card payment charge the undiscounted total.
  group('OrderTotals.forPayment — payment input assembly', () {
    final detail = _Detail(
      goods: [_Good(price: 500000)],
      servicePercent: 20,
      grandTotal: 0,
    );

    test('percent type reads the numpad string as a percentage', () {
      final t = OrderTotals.forPayment(
        detail: detail,
        discountType: DiscountType.percent,
        discountRaw: '10',
      );
      expect(t.baseTotal, 600000);
      expect(t.discountValue, 60000);
      expect(t.grandTotal, 540000);
    });

    test('money type reads the same string as flat so\'m', () {
      final t = OrderTotals.forPayment(
        detail: detail,
        discountType: DiscountType.money,
        discountRaw: '10',
      );
      expect(t.discountValue, 10);
      expect(t.grandTotal, 599990);
    });

    test('a discount actually reaches the charged total', () {
      // The regression this whole entry point exists for: the pay path used
      // to omit the discount entirely and charge the full 600000.
      final undiscounted = OrderTotals.forPayment(detail: detail).grandTotal;
      final discounted = OrderTotals.forPayment(
        detail: detail,
        discountType: DiscountType.percent,
        discountRaw: '25',
      ).grandTotal;
      expect(undiscounted, 600000);
      expect(discounted, 450000);
    });

    test('the service toggle reaches the charged total', () {
      final withService =
          OrderTotals.forPayment(detail: detail, includeService: true);
      final without =
          OrderTotals.forPayment(detail: detail, includeService: false);
      expect(withService.grandTotal, 600000);
      expect(without.grandTotal, 500000);
    });

    test('a non-numeric numpad string is no discount, not a crash', () {
      for (final raw in const ['', '0', 'abc']) {
        expect(
          OrderTotals.forPayment(
            detail: detail,
            discountType: DiscountType.percent,
            discountRaw: raw,
          ).grandTotal,
          600000,
          reason: 'discountRaw=$raw',
        );
      }
    });

    test('table charge and offline extras both reach the total', () {
      final t = OrderTotals.forPayment(
        detail: detail,
        tableCharge: 100000,
        offlineExtra: 50000,
      );
      // items 500000 + table 100000 + service 100000 + offline 50000
      expect(t.tableCharge, 100000);
      expect(t.grandTotal, 750000);
    });

    test('branch service percent fills in when the order reports none', () {
      final noPct = _Detail(goods: [_Good(price: 100000)], grandTotal: 0);
      expect(
        OrderTotals.forPayment(detail: noPct, servicePercent: 20).grandTotal,
        120000,
      );
    });
  });
}
