/// Totals for the archives window currently being filtered — the four numbers
/// in the Orders screen header.
///
/// Separate from `ArchivesResponseEntity` on purpose: that carries one *page*
/// of bills, and folding the header out of it made the header describe the
/// page instead of the window. These come from their own aggregate over the
/// same `WHERE` (`ArchivesQuery.summary`), so they stay correct however few
/// rows the list has loaded.
class ArchivesSummaryEntity {
  /// Bills in the window, whether or not they have been loaded into the list.
  final int count;

  /// How many of those are still open.
  final int openCount;

  /// Sum of the bills' displayed totals, in so'm.
  final int revenue;

  /// [revenue] / [count], truncated. Zero when the window is empty.
  final int avgCheck;

  const ArchivesSummaryEntity({
    this.count = 0,
    this.openCount = 0,
    this.revenue = 0,
    this.avgCheck = 0,
  });

  factory ArchivesSummaryEntity.fromJson(Map<String, dynamic> json) =>
      ArchivesSummaryEntity(
        count: _int(json['count']),
        openCount: _int(json['open_count']),
        revenue: _int(json['revenue']),
        avgCheck: _int(json['avg_check']),
      );

  static int _int(Object? v) => switch (v) {
    int i => i,
    num n => n.toInt(),
    String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is ArchivesSummaryEntity &&
      other.count == count &&
      other.openCount == openCount &&
      other.revenue == revenue &&
      other.avgCheck == avgCheck;

  @override
  int get hashCode => Object.hash(count, openCount, revenue, avgCheck);
}
