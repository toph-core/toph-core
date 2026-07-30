import 'dart:async';

import 'package:mary_ai_pos/features/view/main/data/models/table_timer/table_timer_response_model.dart';

/// App-wide cache bridging live table-timer state between the order
/// screens (`TableTimerCubit`, one active order at a time) and the
/// table-map grid (`TimeBasedTableBadge`, one card per table).
///
/// Without this, pausing/resuming a timer on the order screen only
/// updated that screen's own cubit instance — the table card kept
/// ticking with its last independently-polled state until its next
/// 60s poll or a full remount. Both sides now read/write through the
/// same cache and broadcast so a change on either screen is reflected
/// on the other immediately.
class TableTimerSyncService {
  final _controller = StreamController<String>.broadcast();
  final Map<String, TableTimerResponse> _byTableId = {};

  /// Fires with the affected tableId whenever a timer is published.
  Stream<String> get updates => _controller.stream;

  TableTimerResponse? forTable(String tableId) => _byTableId[tableId];

  void publish(String tableId, TableTimerResponse timer) {
    if (tableId.isEmpty) return;
    _byTableId[tableId] = timer;
    _controller.add(tableId);
  }
}
