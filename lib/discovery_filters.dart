/// The fan-facing discovery filter model: date, price, genre and distance
/// choices, plus where discovery is centred.
library;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart' show DateTimeRange;

import 'models.dart';

enum DateFilter { all, tonight, week, custom }

enum PriceFilter { any, free, paid }

enum DiscoveryLocation { sf, oak, home, current }

DiscoveryLocation discoveryLocationForFanCity(FanCity city) => switch (city) {
  FanCity.sf => DiscoveryLocation.sf,
  FanCity.oak => DiscoveryLocation.oak,
  _ => DiscoveryLocation.home,
};

class DiscoveryFilters {
  const DiscoveryFilters({
    this.date = DateFilter.all,
    this.dateRange,
    this.genres = const {},
    this.price = PriceFilter.any,
    this.maxDistanceMiles,
  });

  final DateFilter date;
  final DateTimeRange? dateRange;
  final Set<String> genres;
  final PriceFilter price;
  final double? maxDistanceMiles;

  static const _unset = Object();

  DiscoveryFilters copyWith({
    DateFilter? date,
    Object? dateRange = _unset,
    Set<String>? genres,
    PriceFilter? price,
    Object? maxDistanceMiles = _unset,
  }) {
    return DiscoveryFilters(
      date: date ?? this.date,
      dateRange: identical(dateRange, _unset)
          ? this.dateRange
          : dateRange as DateTimeRange?,
      genres: genres == null ? this.genres : Set.unmodifiable(genres),
      price: price ?? this.price,
      maxDistanceMiles: identical(maxDistanceMiles, _unset)
          ? this.maxDistanceMiles
          : maxDistanceMiles as double?,
    );
  }

  int get activeCount =>
      (date == DateFilter.all ? 0 : 1) +
      (genres.isEmpty ? 0 : 1) +
      (price == PriceFilter.any ? 0 : 1) +
      (maxDistanceMiles == null ? 0 : 1);

  @override
  bool operator ==(Object other) =>
      other is DiscoveryFilters &&
      other.date == date &&
      other.dateRange == dateRange &&
      setEquals(other.genres, genres) &&
      other.price == price &&
      other.maxDistanceMiles == maxDistanceMiles;

  @override
  int get hashCode => Object.hash(
    date,
    dateRange,
    Object.hashAllUnordered(genres),
    price,
    maxDistanceMiles,
  );
}
