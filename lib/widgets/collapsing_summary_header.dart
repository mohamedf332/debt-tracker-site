import 'package:flutter/material.dart';
import 'collapsing_app_bar_title.dart';

/// How tall the summary card is allowed to look before we know its real
/// height. The card is measured after the first frame (see
/// [measureExtent]) and the header snaps to the measured value, so this only
/// decides how the very first frame looks.
const double kSummaryCardInitialExtent = 200;

/// The collapsed strip is small enough that the estimate is close on any
/// device; it is re-measured the same way as the card.
const double kSummaryStripInitialExtent = 52;

/// Natural height of [key]'s render box, or `null` when it has not been laid
/// out yet. Used to give the pinned header an `maxExtent` that matches the
/// card instead of guessing from font sizes.
double? measureExtent(GlobalKey key) {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return null;
  if (!renderObject.hasSize) return null;
  final height = renderObject.size.height;
  if (!height.isFinite || height <= 0) return null;
  return height;
}

/// The summary card shrunk to a single row: the two amounts, nothing else.
///
/// This is what stays on screen once the full [BalanceCard] has collapsed, so
/// the numbers are never scrolled away.
class SummaryStrip extends StatelessWidget {
  const SummaryStrip({
    super.key,
    required this.theyOweMe,
    required this.iOweThem,
  });

  final double theyOweMe;
  final double iOweThem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CompactBalanceBar(theyOweMe: theyOweMe, iOweThem: iOweThem),
    );
  }
}

/// A pinned sliver header holding the summary card, which collapses into a
/// slim [SummaryStrip] as it is scrolled up.
///
/// The progress is scroll-driven only: `t` is read from the header's own
/// height inside [LayoutBuilder] — never from a timer — so it can never run
/// ahead of or behind the finger. [build] caches its subtree, because the
/// sliver calls it on every offset change; returning an identical instance
/// makes those calls a no-op and leaves only the constraint change for
/// [LayoutBuilder] to react to.
class CollapsingSummaryHeader extends SliverPersistentHeaderDelegate {
  CollapsingSummaryHeader({
    required this.card,
    required this.strip,
    required this.cardKey,
    required this.stripKey,
    required this.maxHeight,
    required this.minHeight,
  });

  /// The full summary card, laid out at its natural height and top-aligned so
  /// its lower rows are clipped away as the header shrinks.
  final Widget card;

  /// The slim row that takes over once the card has collapsed.
  final Widget strip;

  /// Keys used to measure both widgets after layout.
  final GlobalKey cardKey;
  final GlobalKey stripKey;

  final double maxHeight;
  final double minHeight;

  Widget? _cached;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _cached ??= ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Exactly `shrinkOffset / (maxExtent - minExtent)`, expressed with
          // the height the sliver actually gave us: 0 while the card is whole,
          // 1 once only the strip is left.
          final span = maxHeight - minHeight;
          final height = constraints.maxHeight;
          final t = span <= 0
              ? 1.0
              : ((maxHeight - height) / span).clamp(0.0, 1.0);

          // The two cross-fade over the same range, so the header is never
          // blank at the hand-over point.
          final cardOpacity = (1 - t / 0.6).clamp(0.0, 1.0);
          final stripOpacity = ((t - 0.3) / 0.4).clamp(0.0, 1.0);

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: KeyedSubtree(
                  key: cardKey,
                  child: Opacity(opacity: cardOpacity, child: card),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: t < 0.5,
                  child: Opacity(
                    opacity: stripOpacity,
                    child: KeyedSubtree(key: stripKey, child: strip),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CollapsingSummaryHeader oldDelegate) => true;
}
