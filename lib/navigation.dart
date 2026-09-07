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
  bandDash,
  bandEdit,
  bandMedia,
  editProfile,
  settings,
  gigMgr,
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
  opportunityEdit,
  opportunityApplicants,
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
  Screen.hostApply,
  Screen.home,
  Screen.explore,
  Screen.myGigs,
  Screen.myTickets,
  Screen.ticket,
  Screen.ticketCheckoutReturn,
  Screen.ticketCheckoutCancel,
};
const bandTabScreens = {
  Screen.bandDash,
  Screen.bandEdit,
  Screen.gigMgr,
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
  Screen.opportunityEdit,
  Screen.opportunityApplicants,
  Screen.bookingDetail,
  Screen.reviewCompose,
  Screen.checkoutReturn,
  Screen.checkoutCancel,
  Screen.stripeReturn,
};
const adminScreens = {
  Screen.adminQueue,
  Screen.adminApplication,
  Screen.adminSafety,
};

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}
