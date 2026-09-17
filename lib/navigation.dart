/// Screen identities and the stack entries the app navigates between.
library;

import 'models.dart';

enum Screen {
  home,
  gig,
  band,
  bandPreview,
  bandJoin,
  gigInvite,
  venue,
  explore,
  myGigs,
  auth,
  bandCreate,
  bandEdit,
  bandMedia,
  editProfile,
  settings,
  gigMgr,
  hostedGig,
  gigCreate,
  analytics,
  orgApply,
  orgApplicationStatus,
  orgJoin,
  orgDash,
  orgVenues,
  orgVenueEdit,
  orgTeam,
  orgSettings,
  orgFinance,
  orgTransactions,
  adminQueue,
  adminApplication,
  orgOpportunities,
  orgOpportunity,
  opportunityEdit,
  opportunityApplicants,
  applicantReview,
  opportunityDetail,
  bookingDetail,
  reviewCompose,
  bandPayouts,
  checkoutReturn,
  checkoutCancel,
  stripeReturn,
  myTickets,
  ticket,
  ticketCheckoutReturn,
  ticketCheckoutCancel,
  hostApply,
  privateLocations,
  privateLocationEdit,
  adminSafety,
  adminDisputes,
  adminBookings,
  exploreCollection,
  people,
}

sealed class ActiveIdentity {
  const ActiveIdentity();
}

class PersonalIdentity extends ActiveIdentity {
  const PersonalIdentity();
}

class BandIdentity extends ActiveIdentity {
  final String bandId;

  const BandIdentity(this.bandId);
}

class OrganizerIdentity extends ActiveIdentity {
  final String organizationId;
  final OrganizationRole? role;

  const OrganizerIdentity(this.organizationId, this.role);
}

class AdminIdentity extends ActiveIdentity {
  const AdminIdentity();
}

const fanTabScreens = {
  Screen.band,
  Screen.hostApply,
  Screen.home,
  Screen.explore,
  Screen.exploreCollection,
  Screen.people,
  Screen.myGigs,
  Screen.myTickets,
  Screen.ticket,
  Screen.ticketCheckoutReturn,
  Screen.ticketCheckoutCancel,
};
const bandTabScreens = {
  Screen.bandPreview,
  Screen.bandEdit,
  Screen.gigMgr,
  Screen.hostedGig,
  Screen.analytics,
  Screen.opportunityDetail,
  Screen.bookingDetail,
  Screen.reviewCompose,
  Screen.bandPayouts,
  Screen.stripeReturn,
};
const organizerTabScreens = {
  Screen.privateLocations,
  Screen.privateLocationEdit,
  Screen.orgDash,
  Screen.orgVenues,
  Screen.orgVenueEdit,
  Screen.orgTeam,
  Screen.orgSettings,
  Screen.orgFinance,
  Screen.orgTransactions,
  Screen.orgOpportunities,
  Screen.orgOpportunity,
  Screen.opportunityEdit,
  Screen.opportunityApplicants,
  Screen.applicantReview,
  Screen.bookingDetail,
  Screen.reviewCompose,
  Screen.checkoutReturn,
  Screen.checkoutCancel,
  Screen.stripeReturn,
};
/// Edit menus and pushed detail views: on phones these render without the
/// bottom tab bar so the whole screen belongs to the task. Tabs, dashboards,
/// lists, profile previews and settings hubs keep the bar.
const tabBarHiddenScreens = {
  Screen.opportunityEdit,
  Screen.orgOpportunity,
  Screen.applicantReview,
  Screen.orgVenueEdit,
  Screen.privateLocationEdit,
  Screen.bandEdit,
  Screen.bandMedia,
  Screen.gigCreate,
  Screen.hostedGig,
  Screen.bookingDetail,
  Screen.opportunityApplicants,
  Screen.orgFinance,
  Screen.orgTransactions,
  Screen.orgTeam,
};
const adminScreens = {
  Screen.adminQueue,
  Screen.adminApplication,
  Screen.adminSafety,
  Screen.adminDisputes,
  Screen.adminBookings,
};

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}
