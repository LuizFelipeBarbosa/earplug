import '../models.dart';
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
