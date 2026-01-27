/// Extension methods on [DateTime] for formatting and simple arithmetic.
extension DateTimeExtension on DateTime {
  /// Formats this [DateTime] using the provided pattern.
  ///
  /// Defaults to 'dd MMM yyyy' (e.g. '01 Jan 2020').
  // String format([String pattern = 'dd MMM yyyy']) =>
  //     DateFormat(pattern, inject<SettingsCubit>().state.language).format(this);

  /// Returns a short "time ago" string relative to now.
  ///
  /// Examples: '10s ago', '5m ago', '3h ago', '2d ago'.
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  /// Returns a new [DateTime] by adding [days] to this date.
  DateTime addDays(int days) => add(Duration(days: days));

  /// Returns a new [DateTime] by subtracting [days] from this date.
  DateTime subtractDays(int days) => subtract(Duration(days: days));

  int get getWeekOfMonth {
    final firstDayOfMonth = DateTime(year, month, 1);

    final firstWeekday = firstDayOfMonth.weekday;
    final dayOfMonth = day;

    return ((dayOfMonth + firstWeekday - 1) / 7).ceil();
  }
}
