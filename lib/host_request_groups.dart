import 'models.dart';

/// Whether every slot the organizer still wants has an artist in it.
///
/// A confirmed status settles it; otherwise cancelled slots are ignored and at
/// least one live slot must exist, all of them booked.
bool isFullyBooked(Opportunity opportunity) {
  if (opportunity.status == OpportunityStatus.confirmed) return true;
  final live = opportunity.slots.where(
    (slot) => slot.status != SlotStatus.cancelled,
  );
  return live.isNotEmpty &&
      live.every((slot) => slot.status == SlotStatus.booked);
}

/// The CONFIRMED / ACTIVE / PAST split shared by the organizer dash and the
/// requests list, so the two never disagree about what counts as confirmed.
class HostRequestGroups {
  const HostRequestGroups._({
    required this.confirmed,
    required this.active,
    required this.past,
  });

  /// Fully booked, still live, and not yet started; soonest first.
  final List<Opportunity> confirmed;

  /// Still looking for artists (drafts included, listed last); soonest first.
  final List<Opportunity> active;

  /// Completed, cancelled, or started before today; newest first.
  final List<Opportunity> past;

  int get cancelledCount => past
      .where((opportunity) => opportunity.status == OpportunityStatus.cancelled)
      .length;

  Opportunity? get nextEvent => confirmed.firstOrNull;

  static HostRequestGroups from(
    List<Opportunity> all, {
    required DateTime now,
  }) {
    final today = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day);
    final confirmed = <Opportunity>[];
    final active = <Opportunity>[];
    final past = <Opportunity>[];

    for (final opportunity in all) {
      final ended = switch (opportunity.status) {
        OpportunityStatus.completed || OpportunityStatus.cancelled => true,
        _ => false,
      };
      if (ended || opportunity.startsAt.isBefore(today)) {
        past.add(opportunity);
      } else if (isFullyBooked(opportunity)) {
        confirmed.add(opportunity);
      } else {
        active.add(opportunity);
      }
    }

    int soonestFirst(Opportunity a, Opportunity b) =>
        a.startsAt.compareTo(b.startsAt);
    confirmed.sort(soonestFirst);
    active.sort((a, b) {
      final aDraft = a.status == OpportunityStatus.draft;
      final bDraft = b.status == OpportunityStatus.draft;
      if (aDraft != bDraft) return aDraft ? 1 : -1;
      return soonestFirst(a, b);
    });
    past.sort((a, b) => b.startsAt.compareTo(a.startsAt));

    return HostRequestGroups._(
      confirmed: List.unmodifiable(confirmed),
      active: List.unmodifiable(active),
      past: List.unmodifiable(past),
    );
  }
}
