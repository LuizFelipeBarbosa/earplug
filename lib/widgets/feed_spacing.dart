import 'package:flutter/material.dart';

/// Vertical space from the previous section's last content to the header top.
const double kFeedSectionGap = 28;

/// Vertical space from the header bottom to its section's first content.
const double kFeedHeaderGap = 12;

/// Fixed top padding inside an ExploreEventRow before its visible content.
/// See ExploreEventRow/_ExploreHairlineRow in explore_tiles.dart. Callers use
/// this inset to keep the painted gap equal to [kFeedHeaderGap]; it is not
/// independently tunable.
const double kFeedRowLeadingInset = 12;

/// Fixed bottom padding (12px) plus trailing hairline (1px) in ExploreEventRow.
/// Callers compensate for this inset to keep the painted gap equal to
/// [kFeedSectionGap]; it is not independently tunable.
const double kFeedRowTrailingInset = 13;

/// Section-header padding that compensates for adjacent compact row lists.
/// Set [afterRowList] when the previous content is a row list, and
/// [beforeRowList] when the next content is a row list. Flush rail/carousel
/// neighbours need no compensation, so leave their corresponding flag false.
EdgeInsets feedSectionHeaderPadding({
  bool afterRowList = false,
  bool beforeRowList = false,
}) => EdgeInsets.only(
  top: kFeedSectionGap - (afterRowList ? kFeedRowTrailingInset : 0),
  bottom: kFeedHeaderGap - (beforeRowList ? kFeedRowLeadingInset : 0),
);
