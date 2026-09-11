import 'package:flutter/material.dart';

int parseInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  // `int.tryParse` returns null for "666.66" — a decimal string is not an
  // integer literal — and the `?? 0` then turned a real price into nothing.
  // Falling through to a numeric parse keeps the value; callers that need
  // exactness use [parseMoney] instead, because rounding per line and summing
  // is not the same arithmetic as summing and rounding once.
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
  }
  return 0;
}

/// A money amount that may carry cents, as the backend sends it.
///
/// `NUMERIC(15,2)` columns reach the client as JSON numbers, and the replica's
/// [PayloadNormalizer] canonicalises them to strings — `666.66` stays
/// `"666.66"`. Parsed with [parseInt] that string became **0**: every
/// fractional-priced line was rung up free, the bill was short, and the
/// backend — which sums the exact decimals and rounds once — rejected the
/// payment as underpaid and the terminal quarantined it.
///
/// Prices are fractional in the ordinary course of business: `goods.price` is
/// derived as `cost_price * (1 + markup_percent / 100)`, so any markup that is
/// not a round divisor of the cost produces cents.
double parseMoney(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

extension IntExtension on int {
  Widget get wBox => SizedBox(width: toDouble());

  Widget get hBox => SizedBox(height: toDouble());
}
