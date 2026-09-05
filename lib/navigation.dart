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
  adminQueue,
  adminApplication,
  orgOpportunities,
  opportunityEdit,
  opportunityApplicants,
  opportunityDetail,
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

const fanTabScreens = {Screen.home, Screen.explore, Screen.myGigs};
const bandTabScreens = {
  Screen.bandDash,
  Screen.bandEdit,
  Screen.gigMgr,
  Screen.analytics,
  Screen.opportunityDetail,
};
const organizerTabScreens = {
  Screen.orgDash,
  Screen.orgVenues,
  Screen.orgVenueEdit,
  Screen.orgTeam,
  Screen.orgSettings,
  Screen.orgOpportunities,
  Screen.opportunityEdit,
  Screen.opportunityApplicants,
};
const adminScreens = {Screen.adminQueue, Screen.adminApplication};

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}
