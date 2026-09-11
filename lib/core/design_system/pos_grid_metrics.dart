import 'dart:math' as math;

/// Column count and card size for the two order-taking grids — the category
/// grid on the first ordering screen and the product grid on the second.
///
/// Both used to compute this inline, with the same expression:
///
/// ```dart
/// final crossCount = (available / (maxCardWidth + spacing)).floor().clamp(2, 8);
/// ```
///
/// That expression does not do what its `maxCardWidth` name promises. Flooring
/// picks the *fewest* columns that still fit a 180 px card, and the grid then
/// spreads the leftover width across them — so the card is never 180 px wide,
/// it is 180 px *or wider*, and the smaller the screen the worse the overshoot.
/// On an entry-level 1366×768 terminal the product area is around 830 px, which
/// floors to four columns of 197 px; a cashier gets sixteen huge tiles per page
/// on the machine that can least afford the scrolling.
///
/// So the rule is inverted here: [maxCardWidth] is a real ceiling, and the
/// column count is chosen to *reach* [preferredColumns] whenever the cards stay
/// at least [minCardWidth] wide. Widths bracket the count instead of the other
/// way round:
///
/// * `_columnsForMaxWidth` — the fewest columns that keep a card at or under
///   the ceiling. On a 24" screen this is what stops seven columns from
///   becoming seven billboards.
/// * `_columnsForMinWidth` — the most columns that keep a card at or above
///   [minCardWidth], which is where the name and price stop being readable and
///   the tile stops being a comfortable touch target.
///
/// [preferredColumns] then sits inside that bracket. A terminal wide enough for
/// seven readable cards gets seven; one that is not gets as many as it can hold
/// (never fewer than two); a large screen gets more than seven rather than
/// inflating the cards past the ceiling.
class PosGridMetrics {
  /// Columns across.
  final int columns;

  /// Width of one card, in logical pixels.
  final double cardWidth;

  /// Height of one card, in logical pixels.
  final double cardHeight;

  /// Gap between cards, both axes.
  final double spacing;

  const PosGridMetrics({
    required this.columns,
    required this.cardWidth,
    required this.cardHeight,
    required this.spacing,
  });

  /// What `SliverGridDelegateWithFixedCrossAxisCount` wants.
  double get aspectRatio => cardWidth / cardHeight;

  /// The order-screen default: seven columns where they fit.
  ///
  /// [availableWidth] is the grid viewport's width *including* the horizontal
  /// padding the caller will apply, which is subtracted here so a caller cannot
  /// forget to and end up one column too many.
  factory PosGridMetrics.forOrderGrid(
    double availableWidth, {
    int preferredColumns = 7,
    double minCardWidth = 100,
    double maxCardWidth = 180,
    double maxCardHeight = 200,
    double widthToHeightRatio = 0.92,
    double spacing = 12,
    double horizontalPadding = 40,
  }) {
    final available = math.max(
      availableWidth - horizontalPadding,
      minCardWidth,
    );

    // Both bounds count the trailing gap that is not drawn: n cards carry
    // n - 1 gaps, so `available + spacing` divided by `card + spacing` is the
    // exact number of cards that fit.
    final forMax = ((available + spacing) / (maxCardWidth + spacing)).ceil();
    final forMin = ((available + spacing) / (minCardWidth + spacing)).floor();

    // `forMin` can fall below `forMax` on a viewport too narrow to satisfy
    // both, in which case the ceiling wins and the cards are simply small.
    final lower = math.max(forMax, 2);
    final upper = math.max(lower, forMin);
    final columns = preferredColumns.clamp(lower, upper);

    final cardWidth = (available - spacing * (columns - 1)) / columns;
    final cardHeight = (cardWidth / widthToHeightRatio).clamp(
      1.0,
      maxCardHeight,
    );

    return PosGridMetrics(
      columns: columns,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      spacing: spacing,
    );
  }
}
