import '../models.dart';
import '../money.dart';
import 'common.dart';

String slotRoleLabel(SlotRole role) => switch (role) {
  SlotRole.headliner => 'Headliner',
  SlotRole.support => 'Support',
  SlotRole.opener => 'Opener',
};

String opportunityStatusLabel(OpportunityStatus status) => switch (status) {
  OpportunityStatus.draft => 'Draft',
  OpportunityStatus.open => 'Open',
  OpportunityStatus.applicationsClosed => 'Applications closed',
  OpportunityStatus.booking => 'Booking',
  OpportunityStatus.confirmed => 'Confirmed',
  OpportunityStatus.completed => 'Completed',
  OpportunityStatus.cancelled => 'Cancelled',
};

EpStatusPillTone opportunityStatusTone(OpportunityStatus status) =>
    switch (status) {
      OpportunityStatus.open ||
      OpportunityStatus.confirmed => EpStatusPillTone.success,
      OpportunityStatus.applicationsClosed ||
      OpportunityStatus.booking => EpStatusPillTone.warning,
      _ => EpStatusPillTone.neutral,
    };

String applicationStatusLabel(ArtistApplicationStatus status) =>
    switch (status) {
      ArtistApplicationStatus.submitted => 'Submitted',
      ArtistApplicationStatus.underReview => 'Under review',
      ArtistApplicationStatus.shortlisted => 'Shortlisted',
      ArtistApplicationStatus.offered => 'Offered',
      ArtistApplicationStatus.booked => 'Booked',
      ArtistApplicationStatus.declined => 'Declined',
      ArtistApplicationStatus.withdrawn => 'Withdrawn',
      ArtistApplicationStatus.expired => 'Expired',
    };

EpStatusPillTone applicationStatusTone(ArtistApplicationStatus status) =>
    switch (status) {
      ArtistApplicationStatus.shortlisted => EpStatusPillTone.selected,
      ArtistApplicationStatus.offered ||
      ArtistApplicationStatus.booked => EpStatusPillTone.success,
      ArtistApplicationStatus.declined => EpStatusPillTone.warning,
      _ => EpStatusPillTone.neutral,
    };

String organizationRoleLabel(OrganizationRole role) => switch (role) {
  OrganizationRole.owner => 'Owner',
  OrganizationRole.manager => 'Manager',
  OrganizationRole.finance => 'Finance',
  OrganizationRole.door => 'Door',
};

/// Title-cases the wire value: `under_review` reads "Under Review".
String organizationApplicationStatusLabel(
  OrganizationApplicationStatus status,
) => status.wireValue
    .replaceAll('_', ' ')
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String venueTypeLabel(VenueType type) => switch (type) {
  VenueType.bar => 'Bar',
  VenueType.club => 'Club',
  VenueType.hall => 'Hall',
  VenueType.house => 'House',
  VenueType.outdoor => 'Outdoor',
  VenueType.private => 'Private',
  VenueType.other => 'Other',
};

String estimatedDrawLabel(EstimatedDraw? draw) {
  if (draw == null) return 'Estimated draw: No history yet';
  final basis = draw.basis == DrawBasis.checkIns ? 'check-ins' : 'RSVPs';
  return 'Estimated draw: ${draw.low}–${draw.high} · '
      '${draw.confidence.wireValue} confidence · based on $basis';
}

/// The project's trimmed title, or [fallback] while it has none.
String projectTitle(GigProject project, {String fallback = 'Untitled gig'}) {
  final title = project.title?.trim();
  return title == null || title.isEmpty ? fallback : title;
}

/// "Headliner · $300.00 · 2/2 slots booked", with " + 1 more" after the
/// guarantee when [countExtraRoles] is set and other roles are on the bill.
String bookedSlotLine(Opportunity opportunity, {bool countExtraRoles = false}) {
  final slots = [...opportunity.slots]
    ..sort((a, b) => a.order.compareTo(b.order));
  final booked = slots.where((slot) => slot.status == SlotStatus.booked).length;
  final lead = slots.firstOrNull;
  final roles = <SlotRole>{for (final slot in slots) slot.role};
  final extraRoles = countExtraRoles && roles.length > 1
      ? ' + ${roles.length - 1} more'
      : '';
  return [
    if (lead != null)
      '${slotRoleLabel(lead.role)} · '
          '${Money(lead.guaranteeMinor, opportunity.currency).label}'
          '$extraRoles',
    '$booked/${slots.length} slots booked',
  ].join(' · ');
}
