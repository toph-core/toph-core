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

  /// The ordering grids — categories on the first screen, meals on the second
  /// — which are lists of names rather than walls of pictures.
  ///
  /// [forOrderGrid] is the wrong metric for it, and deliberately so. That one
  /// exists to make a category tile the same size as the meal tiles behind it,
  /// which was right while both were picture cards. The category tile is now a
  /// single line of text, and a text tile wants the opposite of a picture
  /// tile: as much width as it can get, so the whole name fits, and no more
  /// height than it takes to read and tap.
  ///
  /// So the count is chosen from the *ceiling* alone — the fewest columns that
  /// keep a card at or under [maxCardWidth] — rather than aiming at a preferred
  /// count the way the order grid does. Fewer columns is the goal here, not a
  /// compromise, and there is no lower bracket to balance against because a
  /// text row has no content that stops being legible as the tile widens. Two
  /// is the floor so a wide name never gets a full-width banner to itself.
  ///
  /// In practice: two columns at 1024 px, three at 1366 px, four from about
  /// 1800 px up.
  ///
  /// [cardHeight] is a real height rather than an aspect ratio, because an
  /// aspect ratio would make the row taller every time the screen got wider,
  /// and a tile's height should not depend on how much room its neighbours
  /// have. 84 is two comfortable lines of 15px type plus padding, so a long
  /// name wraps instead of ellipsizing, and it is a generous touch target on a
  /// counter-top monoblock.
  /// [horizontalPadding] is the grid's own padding, which the caller has
  /// already spent out of the width it reports.
  factory PosGridMetrics.forTextTileGrid(
    double availableWidth, {
    double maxCardWidth = 500,
    double cardHeight = 84,
    double spacing = 12,
    double horizontalPadding = 40,
  }) {
    // Never narrower than one card: a width below that is a transient
    // constraint during layout, not a terminal anybody is standing at, and
    // dividing by a negative column count from it would throw.
    final available = math.max(availableWidth - horizontalPadding, maxCardWidth);
    final columns = math.max(
      ((available + spacing) / (maxCardWidth + spacing)).ceil(),
      2,
    );

    return PosGridMetrics(
      columns: columns,
      cardWidth: (available - spacing * (columns - 1)) / columns,
      cardHeight: cardHeight,
      spacing: spacing,
    );
  }
}
