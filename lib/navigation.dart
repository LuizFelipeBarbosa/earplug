/// Screen identities and the stack entries the app navigates between.
library;

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
}

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}
