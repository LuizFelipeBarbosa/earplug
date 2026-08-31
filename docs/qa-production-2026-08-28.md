# EarPlug production QA report

Date: 2026-08-28  
Target: `https://earplug.dev`  
Environment: production web client, existing account (signed out after testing)  
Browser: Codex in-app browser

## Executive summary

EarPlug's main discovery, profile, band-management, media, gig-management,
RSVP, and cleanup flows were exercised end to end. A temporary public band and
gig were created, published, viewed as a fan, updated through their lifecycle,
and cleaned up. The public QA band remains because the product has no band
deletion operation. Its media, gigs, active invitation, fan save/RSVP, and test
follow were removed.

The most important defects are broken advertised public slugs for gigs and
bands, silent member-invitation creation while saving an unchanged band,
automatic persistence of empty gig drafts, and a raw backend exception shown
for invalid gig URLs.

Final sign-out and the resulting authentication gate were verified. Precise
location was attempted with approval, but the request remained on “Finding
you…” indefinitely without a browser prompt, error, or timeout; consequently
the dependent distance controls never became enabled. Account deletion was
validated through its confirmation UI but was not performed.

## Test fixture and final state

- Public band created: **Codex QA Tape Aug 28 2026**
- Public gig created: **Codex QA Gig Aug 29 2026**
- QA media uploaded: one MP4 clip, one PNG photo, and one profile photo
- Gig lifecycle tested: draft, publish, unpublish, republish, cancel, republish,
  duplicate, and delete
- Final gig state: no drafts, published gigs, or cancelled gigs
- Final fan state: no test RSVP, saved show, or test follow
- Final band media state: no media and initials used for the profile image
- Final invitation state: no active member invitation
- Remaining fixture: public QA band, because no band deletion feature exists

## Feature map and interaction coverage

The production client's 19 declared screen destinations were cross-checked
against this map and all 19 were opened. The two invitation screens were
exercised in their invalid/revoked states; valid acceptance requires a second
eligible account and is listed under coverage boundaries below.

### Public Gigs home

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Gigs navigation | Opened from primary navigation | Pass |
| List / Map toggle | Switched in both directions | Pass |
| Manual area selector | Mission and Oakland options selected | Pass |
| Current Location | Invoked with approval; remained on “Finding you…” indefinitely; manual Mission selection recovered the UI | Fail; EP-17 |
| Distance filters | Any, 5 MI, 10 MI, and 25 MI rendered disabled because Current Location never resolved | Blocked by EP-17 |
| Quick filters | Tonight, This Week, and Free toggled | Pass |
| Filter-sheet open/close | Opened; Close and backdrop dismissal tested | Pass |
| Date filters | Any Date, Tonight, This Week, and custom range | Pass |
| Date picker | Calendar and manual-entry modes; Cancel and Use Dates | Pass |
| Genre filters | Every listed genre and Any genre | Pass |
| Price filters | Any, Free, and Paid | Pass |
| Venue filters | Specific venue and Any Venue | Pass |
| Clear All / Show Results | Both controls tested | Pass |
| Map interaction | Map panning/dragging tested | Pass |
| Empty state | Shown before creation and after cleanup | Pass |
| Gig card | Open, Save, Share, RSVP, and band/venue navigation | Pass with sharing caveat EP-09 |

### Explore and public profiles

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Explore navigation | Opened from primary navigation | Pass |
| Search input | Typed, submitted by button and Enter, then cleared | Pass |
| Result tabs | All, Events, Bands, and Venues | Pass |
| Genre shortcuts | Punk, Hardcore, Garage, Noise, Post-Punk, Shoegaze, Surf, Thrash, Ska, and Emo | Pass |
| Band expansion | See All and See Less | Pass |
| Venue expansion | See All and See Less | Pass |
| Venue detail | Opened venue, map, upcoming, and performances sections | Pass |
| Existing band profile | Opened Circadian Rhythm profile | Pass |
| Band photo viewer | Opened and closed | Pass |
| Band video viewer | Play, pause, secondary clip, and close | Pass with responsive defect EP-08 |
| Instagram link | Invoked; external navigation was not observable inside the test browser | Inconclusive |
| QA band discovery | Found and opened from Explore | Pass |
| Direct QA band URL | Opened advertised band slug | Fail; EP-02 |

### Fan profile and account settings

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Onboarding tutorial | Next, Done, replay, and dismissal | Pass |
| City preference | Every displayed city option selected; restored to San Francisco | Pass |
| Genre preferences | Every displayed genre toggled; restored to none | Pass |
| Upcoming RSVPs | Created, opened, QR viewed/dismissed, and removed | Pass |
| Saved Shows | Saved, opened, and unsaved | Pass |
| Followed Bands | Followed and unfollowed QA band | Pass |
| Empty-state CTAs | Every profile empty-state category opened | Pass |
| Edit Profile fields | Name, location, genres, bio, and switches exercised and restored | Pass |
| Name validation | Invalid state triggered | Pass |
| Avatar | Upload preview and removal | Pass |
| Settings navigation | Back, profile preferences, and replay tutorial | Pass |
| Delete Account | Modal, exact-text validation, disabled state, Cancel, and backdrop | Pass; deletion intentionally not confirmed |
| Sign Out | Signed out; public Gigs home restored and auth gating verified across both open tabs | Pass |
| Signed-out Profile gate | Opened authentication screen | Pass |
| Signed-out Start a Band gate | Opened authentication screen | Pass |
| Authentication navigation | Email, Back, and Keep Browsing | Pass |
| Email validation | Empty and malformed addresses rejected inline | Pass |
| Google OAuth | Opened the Google account chooser with the expected EarPlug/Clerk callback, then cancelled without selecting an account | Pass |
| Valid email-code send | Sent exactly one code request; advanced to the six-digit verification form | Pass |
| Verification form | Empty Verify error, Back, and return to public browsing | Pass with wording caveat EP-18 |
| Resend Code | Rendered and enabled; not invoked because approval was explicitly limited to one email | Intentionally not executed |

### Band creation

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Color swatches | All six swatches | Pass |
| Profile photo | Upload, change, and remove | Pass |
| Band name | Entered and saved | Pass |
| Sound sheet | Open, Close, genre selection, three-genre limit, and custom genre | Pass |
| Home Base sheet | Open, Close, presets, and custom value | Pass |
| Bio | Starter content entered | Pass |
| Links | Inputs typed and cleared | Pass |
| Credits | Entered and saved | Pass |
| Pre-create media/member guards | Both invoked and displayed guard messages | Pass |
| Create Band | Confirmed and public band created | Pass |
| Completion screen | Music Clip and Publish Gig routes tested | Pass |
| Equivalent dashboard routes | Invite members, Keep Editing, Share Profile, Start Another, and dashboard routes | Pass with EP-02 and EP-03 caveats |

### Band dashboard and editor

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Band switcher | Current band, Personal account, and Start Another Band | Pass |
| Dashboard actions | Discover, Edit Profile, Preview Public Profile, Add Media, Publish Gig, and Analytics | Pass |
| Setup Checklist | Every action button | Pass |
| Discovery Readiness | Every action button | Pass |
| Dashboard bottom navigation | Dash, Profile, Gigs, and Insights | Pass |
| Genre editor | All built-in genres, three-genre limit, custom add/remove | Pass |
| Text fields | Name, home base, bio, links, and credits changed and restored | Pass |
| Profile image route | Change Profile Image | Pass |
| Preview / Manage Media | Both routes | Pass |
| Save Changes | Saved unchanged and changed data | Functionally passes; causes EP-03 |
| Member invitation | Create, Copy, Rotate, Revoke, recreate, and final revoke | Pass with EP-03 |
| Band deletion | No UI, repository operation, or app function exists | Missing; EP-14 |

### Band media

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Empty-state add action | Post First Clip | Pass |
| Add actions | +Music and +Photos | Pass |
| File validation | Invalid media type and invalid PNG-as-video cases | Pass |
| Video upload | MP4 uploaded and rendered | Pass |
| Photo upload | PNG uploaded and rendered | Pass |
| Profile image | Uploaded and selected | Pass |
| Ordering controls | Every displayed move/reorder control | Pass |
| Pin control | Invoked on already-pinned clip | Limitation; EP-16 |
| Band-photo modal | Close, backdrop, Use Initials, and both photo choices | Pass |
| Public viewers | Video and photo opened/closed | Pass with EP-08 |
| Delete confirmations | Close, Keep, backdrop, and Delete | Pass |
| Cleanup | Photo, profile photo, and video deleted | Pass |

### Gig authoring

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Gig name | Entered and saved | Pass |
| Date sheet | Close and every displayed day option | Pass |
| Doors time | Presets exercised | Pass |
| Start time | Clock and keyboard modes, Cancel, OK, and 9:30 input | Pass |
| Venue sheet | Close/backdrop, existing venue, and New Venue | New Venue unavailable; EP-12 |
| Lineup | Search, close, add/remove existing band, and text performer | Pass |
| Performer invitation | Create, pending performer, Copy, and remove | Copy fails; EP-07 |
| Cover | Close/backdrop, Free, $5, $8, $10, $12, $15, and custom $7 | Pass |
| Access | Close/backdrop/Done, in-app RSVP, external ticket mode | URL validation fails; EP-06 |
| RSVP caps | No cap, 50, 100, 150, and custom 75 | Pass |
| Poster colors | Every displayed swatch | Pass |
| Flyer art | Add, Change, and Remove custom flyer | Pass |
| Text overlay | On/off | Pass |
| Audience | 18+, 21+, and All Ages | All Ages saves incorrectly; EP-05 |
| Additional information | Entered and rendered | Pass |
| Preview | Opened and reviewed | Pass |
| Save Draft | Saved | Pass |
| Publish Gig / Publish Updates | Confirmed and completed | Pass |

### Published-gig and fan lifecycle

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Post-publish actions | Share Link, Door QR, Keep Editing, Make Another, and Back to Gigs | Door QR unavailable; EP-13. Share caveat EP-09 |
| Fan list card | Open, Save/Unsave, Share, RSVP/Going/Remove | Pass with EP-09 |
| Fan detail | Back, Save, Share, band, venue, map, Directions, and RSVP | Pass; Directions launch was externally inconclusive |
| Fan QR | Open and dismiss | Pass |
| Fan follow | Follow and unfollow band | Pass |
| Published menu | Dismiss, Edit, Preview, Duplicate, Unpublish, Cancel, and Delete | Pass |
| Unpublish confirmation | Keep, backdrop, and Confirm | Pass |
| Republish | Performed after unpublishing | Pass |
| Cancel confirmation | Keep and Confirm | Pass |
| Cancelled public page | Cancelled badge and disabled RSVP | Pass |
| Cancelled menu | Edit, Preview, Duplicate, and Delete | Pass |
| Duplicate | Published and draft duplicates | Pass |
| Deep link after unpublish/delete | Friendly unavailable state | Pass |
| Advertised slug | Opened creator-advertised slug | Fail; EP-01 |
| Invalid gig ID | Opened and retried | Fail; EP-01 |
| Final cleanup | Nine incidental empty drafts, two duplicates, and published QA gig deleted | Pass |

### Error, accessibility, and responsive states

| Feature or control | Coverage | Result |
| --- | --- | --- |
| Invalid member invitation | Friendly unavailable, Try Again, and Close | Pass |
| Invalid performer invitation | Friendly unavailable, Try Again, and Close | Pass |
| Invalid gig URL | Try Again tested | Raw exception; EP-01 |
| Responsive widths | 320x568, 360x720, 480x720, 768x720, and desktop | Mostly pass; EP-08 |
| Keyboard navigation | Tab focus exercised | Pass |
| Flutter semantics | Semantic tree enabled and inspected | Pass |
| Browser console | No warning/error messages observed during tested flows | Pass |

## Defects and incomplete features

### EP-01 — Advertised public gig slugs and invalid gig URLs expose a backend exception

**Severity: High**

The publication screen advertised
`earplug.dev/g/codex-qa-gig-aug-29-2026`, but opening it displayed a raw backend
exception and request ID. An arbitrary invalid path such as
`/g/not-a-real-id` produced the same result. The fan-detail Share action instead
generated an internal-ID URL, which rendered correctly. Unpublished or deleted
valid internal-ID URLs also showed the correct friendly unavailable state.

Expected: the advertised slug resolves to the published gig, and unknown URLs
render a friendly not-found/unavailable page without implementation details.

### EP-02 — Advertised band profile URL does not open the band

**Severity: High**

Opening `https://earplug.dev/codex-qa-tape-aug-28-2026` left that address in the
browser while rendering the Gigs home map. The same band opened correctly from
Explore, where the app retained `/` as the URL.

Expected: the advertised/direct profile URL opens the public band profile and
supports refresh and sharing.

### EP-03 — Saving an unchanged band silently creates a member invitation

**Severity: High / security-sensitive**

Pressing **Save Changes** on an unchanged band profile created a seven-day member
invitation even though **Create Invitation** had not been pressed.

Expected: saving profile content never creates an authorization-bearing invite.

### EP-04 — Abandoning a new-gig editor persists an empty draft

**Severity: Medium–High**

Opening the new-gig editor and navigating back created an `UNTITLED GIG` draft.
Route coverage produced seven such drafts, all of which required manual deletion.

Expected: an untouched editor is discarded, or the user is asked whether to
save once meaningful data exists.

### EP-05 — All Ages is persisted and displayed as 18+

**Severity: Medium**

Selecting **All Ages** repeatedly resulted in **18+** after save/render. **21+**
persisted correctly.

Expected: the selected audience restriction remains unchanged.

### EP-06 — External ticket URL accepts malformed input

**Severity: Medium**

The external-ticket field accepted `not-a-url` and considered the gig ready to
publish.

Expected: require a supported `https://` URL and show field-level validation.

### EP-07 — Performer invitation Copy action has no effect

**Severity: Medium**

The pending performer's **Copy invite link** action was invoked twice. It wrote
nothing to the clipboard and showed no success or failure feedback.

Expected: copy the invitation URL and acknowledge success, or report why the
clipboard operation failed.

### EP-08 — Video playback control is unreachable in a common desktop viewport

**Severity: Medium**

At approximately 879x766, a square clip viewer placed the Play control below the
viewport (around y=983), and the overlay could not scroll. At 879x1200, the
control was reachable and playback worked.

Expected: media and playback controls fit the viewport or the viewer scrolls.

### EP-09 — Sharing behavior is inconsistent

**Severity: Medium–Low**

Post-publication **Share Link** and the list-card Share action reported
`Link copied`, but the clipboard remained empty. Sharing from the fan detail
page copied the complete internal-ID URL correctly.

Expected: all Share actions use the same verified copy/share implementation and
only announce success after completion.

### EP-10 — Published-gig preview is labeled as a private draft

**Severity: Low**

Previewing a live listing from the published manager displayed
`FAN PREVIEW PRIVATE DRAFT`.

Expected: preview labeling reflects the gig's live state.

### EP-11 — RSVP count wording appears inconsistent

**Severity: Low / ambiguous**

The fan profile header displayed `0 RSVP records` while a newly created upcoming
RSVP was visibly listed. If the number intentionally counts only historical
records, the label needs clarification.

### EP-12 — Adding a new venue is not implemented

**Status: Feature not ready**

**+ NEW VENUE** reports: “Adding venues isn’t ready yet. Pick from the list for
now.”

### EP-13 — Door QR is not implemented

**Status: Feature not ready**

The post-publication **Door QR** action reports: “Door QR isn’t ready yet. RSVPs
still count live.” Fan RSVP QR display does work.

### EP-14 — Bands cannot be deleted

**Status: Missing feature**

No band deletion action exists in the production UI. A source search also found
no `deleteBand`, `removeBand`, or `archiveBand` operation in the application or
tests; only band-media deletion functions exist.

### EP-15 — External Instagram and Directions launch could not be verified

**Status: Inconclusive**

Both controls were invoked, but the in-app browser showed no new tab or visible
navigation. These may intentionally hand off to an external app.

### EP-16 — Pinned media has no explicit unpin affordance

**Severity: Low / product limitation**

An already pinned clip continued to show an enabled `PINNED ★` control. Clicking
it was idempotent; no unpin state or explanation was offered.

### EP-17 — Current Location can remain stuck indefinitely

**Severity: Medium–High**

After explicit location approval, selecting **Current location** changed the
control to `Finding you…`, but the in-app browser displayed no permission prompt
and the UI did not resolve to success, denial, unavailable, or retry—even after
well beyond 15 seconds. Mission and Oakland remained selectable, and choosing
Mission recovered the sheet and restored manual browsing.

The location service applies a 15-second limit only to
`getCurrentPosition`; the preceding permission-check/request calls have no
timeout. If the platform permission request never resolves, `locating` remains
true forever and **Any**, **5 MI**, **10 MI**, and **25 MI** remain disabled.

Expected: the permission request resolves through a surfaced browser prompt or
times out into the existing recoverable failure UI. The whole request—not only
position lookup—needs a bounded timeout.

### EP-18 — Empty verification code is reported as wrong or expired

**Severity: Low**

On the six-digit email-code form, **Verify** is enabled with an empty field.
Pressing it reports `That code is wrong or expired.` rather than asking for a
six-digit code.

Expected: require six digits client-side, disable **Verify** until the input is
complete, or show an accurate field-level validation message.

## Cleanup verification

- Gig manager showed no saved drafts, published gigs, or cancelled gigs.
- Fan profile showed no upcoming QA RSVP or saved QA show.
- The QA band was unfollowed by the test fan.
- Band media showed zero items and the profile used initials.
- The member invitation was revoked.
- The public QA band remains only because EP-14 prevents deletion.

## Coverage boundaries

The browser pass exercised every control rendered in the ordinary reachable
states described above. The following conditional or destructive states were
not forced merely to expose additional controls:

- The signed-out authentication screen, Email route, inline validation, Back,
  Keep Browsing, Profile gate, and Start a Band gate were tested. Google OAuth
  reached the account chooser and was cancelled without selecting an identity.
  Exactly one email code was requested; **Resend Code** was not invoked because
  the user's confirmation explicitly limited the test to one email.
- Valid band-member acceptance and performer-claim success require a second
  eligible identity. Invalid/revoked invitation screens, Retry, and Close were
  tested; creating a membership for the existing owner was not treated as a
  valid substitute.
- Network-failure-only Retry controls in Explore, Analytics, and media upload
  were not forced by disrupting production traffic. Normal, empty, validation,
  and unavailable states were tested.
- Analytics populated with real historical shows and privacy-threshold fan
  counts could not be produced without fabricating several additional users.
- Final account deletion was not performed. Its modal, exact `DELETE` input
  requirement, disabled/enabled validation behavior, Cancel, and backdrop were
  tested.
- Precise location was attempted with approval, but EP-17 prevented the
  permission-denied/unavailable recovery states and enabled distance controls
  from becoming reachable.

## Final account state

EarPlug remains signed out in both browser tabs. The final provider checks did
not select a Google identity, verify an email code, create a new session, or
resend the verification email.
