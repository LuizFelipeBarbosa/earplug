import 'models.dart';

/// The booking and hosting history shown in a band's My Gigs tab.
class BandGigBuckets {
  const BandGigBuckets._({
    required this.upcoming,
    required this.hosting,
    required this.drafts,
    required this.past,
  });

  /// Live bookings that start after `now`, earliest first.
  final List<Booking> upcoming;
  final List<GigProject> hosting;
  final List<GigProject> drafts;
  final List<BandPastEntry> past;

  int get cancelledCount => past
      .where(
        (entry) => switch (entry) {
          BandPastBooking(:final cancelled) => cancelled,
          BandPastProject() => true,
          BandPastLedger() => false,
        },
      )
      .length;

  static BandGigBuckets from({
    required List<Booking> bookings,
    required List<GigProject> projects,
    required List<PastGig> ledger,
    required DateTime now,
  }) {
    final futureBookings = <Booking>[];
    final hosting = <GigProject>[];
    final drafts = <GigProject>[];
    final datedPast = <({DateTime date, BandPastEntry entry})>[];

    for (final booking in bookings) {
      if (booking.status.isLive && booking.startsAt.isAfter(now)) {
        futureBookings.add(booking);
      }

      final cancelled = switch (booking.status) {
        BookingStatus.cancelledByOrganizer ||
        BookingStatus.cancelledByArtist ||
        BookingStatus.forceMajeure ||
        BookingStatus.refunded => true,
        _ => false,
      };
      if (cancelled ||
          booking.status == BookingStatus.completed ||
          booking.status == BookingStatus.paid ||
          (booking.status.isLive && booking.startsAt.isBefore(now))) {
        datedPast.add((
          date: booking.startsAt,
          entry: BandPastBooking(booking, cancelled: cancelled),
        ));
      }
    }

    for (final project in projects) {
      switch (project.status) {
        case GigProjectStatus.published:
          hosting.add(project);
        case GigProjectStatus.draft:
          drafts.add(project);
        case GigProjectStatus.cancelled:
          datedPast.add((
            date: project.startsAt ?? project.updatedAt,
            entry: BandPastProject(project),
          ));
        case GigProjectStatus.deleted:
          break;
      }
    }

    futureBookings.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    hosting.sort((a, b) {
      // Published gigs normally have a date; keep undated ones at the end.
      final aDate = a.startsAt;
      final bDate = b.startsAt;
      if (aDate == null) return bDate == null ? 0 : 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    datedPast.sort((a, b) => b.date.compareTo(a.date));

    return BandGigBuckets._(
      upcoming: List.unmodifiable(futureBookings),
      hosting: List.unmodifiable(hosting),
      drafts: List.unmodifiable(drafts),
      past: List.unmodifiable([
        for (final item in datedPast) item.entry,
        // Ledger metadata is free text, so preserve its supplied order.
        for (final pastGig in ledger) BandPastLedger(pastGig),
      ]),
    );
  }
}

sealed class BandPastEntry {
  const BandPastEntry();
}

class BandPastBooking extends BandPastEntry {
  const BandPastBooking(this.booking, {required this.cancelled});

  final Booking booking;
  final bool cancelled;
}

class BandPastProject extends BandPastEntry {
  const BandPastProject(this.project);

  final GigProject project;
}

class BandPastLedger extends BandPastEntry {
  const BandPastLedger(this.pastGig);

  final PastGig pastGig;
}
