/// OFFLINE_FIRST_EVERYWHERE_PLAN.md Phase 0 — change-log payload → model shape.
///
/// The replication feed carries `to_jsonb(NEW)`: the raw Postgres row. Every
/// Flutter model in this codebase was written against the **REST** shape. The
/// two agree on field names (both snake_case, both the column name) but differ
/// on two points, and this file is the whole of that difference.
library;

import 'entity_registry.dart';

/// Coerces a raw change-log row into the shape the app's `fromJson`
/// constructors already expect.
///
/// Two transforms, both driven by [EntitySpec]:
///
/// 1. **Numerics to strings.** A Postgres `numeric` serialises through
///    `to_jsonb` as a JSON number (`15000.00`), but the REST API marshals
///    `pgtype.Numeric` as a JSON string (`"15000.00"`). `GoodsModel.price`,
///    `OrderItem.price` and ~60 other fields are declared `String`, so a raw
///    replicated row would throw a type error in `fromJson`. The key list comes
///    from the backend's own sqlc models, not from guesswork.
///
/// 2. **Redaction.** Raw rows carry columns the REST API never exposes —
///    `users.hash_password` and `users.pincode` most importantly. Those are
///    dropped before the row reaches disk.
///
/// Everything else passes through untouched. Timestamps need no conversion:
/// Postgres emits `2026-07-12T13:17:20+00:00` and Go emits
/// `2026-07-12T13:17:20Z`, and `DateTime.parse` accepts both. Enum columns
/// serialise as their string label in both paths. `deleted_at` is present in
/// raw rows and absent from REST responses, which is additive and harmless —
/// and useful, since it is how a soft-deleted row is recognised.
class PayloadNormalizer {
  const PayloadNormalizer._();

  /// Returns a new map; [raw] is never mutated.
  static Map<String, dynamic> normalize(
    EntitySpec spec,
    Map<String, dynamic> raw,
  ) {
    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (spec.redactKeys.contains(key)) continue;

      final value = entry.value;
      if (value != null && spec.numericKeys.contains(key) && value is num) {
        out[key] = numToCanonicalString(value);
      } else {
        out[key] = value;
      }
    }
    return out;
  }

  /// Renders a JSON number the way the REST API renders the same `numeric`.
  ///
  /// Exact decimal *scale* is deliberately not reproduced — the API returns
  /// `"15000.00"` where this returns `"15000"`. Every consumer parses these
  /// (`double.tryParse`) and formats for display separately, so scale carries
  /// no information; what matters is that the value round-trips numerically and
  /// never arrives as `"15000.0"` where a cashier might see it raw.
  ///
  /// Integral values render without a fractional part; fractional values keep
  /// their natural representation (`42.86`).
  static String numToCanonicalString(num value) {
    if (value is int) return value.toString();
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return '0';
    // 1e15 stays inside double's exact-integer range (2^53), so the
    // toStringAsFixed(0) below can never render a rounded approximation as if
    // it were exact. So'm amounts are orders of magnitude below this.
    if (d == d.roundToDouble() && d.abs() < 1e15) {
      return d.toStringAsFixed(0);
    }
    return d.toString();
  }

  /// Reads the soft-delete marker from a raw row.
  ///
  /// `deleted_at` is `*int64` (epoch seconds) across this schema, not a
  /// timestamp — a non-null value means the row is soft-deleted server-side.
  /// Tolerates a string encoding in case a future column changes type.
  static int? deletedAtOf(Map<String, dynamic> row) {
    final raw = row['deleted_at'];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
