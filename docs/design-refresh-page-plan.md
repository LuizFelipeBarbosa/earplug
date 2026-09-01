# EarPlug Design Refresh — Page-by-Page Plan

Status: planning only. This document does not authorize implementation or
backend changes.

This plan consolidates the redesign packet in `screens.md`, `components.md`,
and its `README.md`, reconciled with the current Flutter application and frozen
Convex contract. Each user-facing page has its own section so work can be
implemented and reviewed independently.

## Scope and guardrails

- Treat the refresh as presentation-only: no new Convex functions, schema
  fields, indexes, Clerk behavior, or payload shapes.
- Preserve every existing action, role restriction, loading state, error state,
  empty state, cancellation state, and recovery path.
- Render only data already available to the page. Omit unavailable metadata
  rather than inventing it or adding a backend call.
- Keep the five-fan analytics privacy floor server-side and never expose
  individual fan drill-downs.
- Retain dynamic text scaling, semantic labels, keyboard/focus behavior, and
  minimum 48 logical-pixel interactive targets even where the mockups are more
  compact.
- Use one dominant volt treatment per page. Status colors must also have text or
  icon labels so color is never the only signal.
- Preserve the current phone-width web presentation. Wider tablet/desktop
  layouts are outside this refresh.

## Cross-page foundation

These are shared prerequisites rather than standalone pages.

- [ ] Align the semantic theme tokens with the redesign palette while retaining
  the existing token API and accessible contrast.
- [ ] Introduce or consolidate shared `SectionBar`, `DateBlock`, three-state
  `EpChip`, `StatusPill`, `StatTile`, `VoltStrip`, `SwitchRow`, `LedgerRow`,
  `GhostDraftRow`, `StickyActionBar`, `ActionSheet`, `ScannerFrame`, and
  `DangerZone` widgets.
- [ ] Rebuild `FanEventCard` once and reuse it across Home, Explore, Profile,
  Venue, and Band pages. Support a compact date-led row and a featured poster
  variant without duplicating interaction logic.
- [ ] Keep save, share, RSVP, external ticket, age, price, going count,
  discovery boost, distance, and caller-supplied trailing actions intact.
- [ ] Add shared widget tests for text scaling, 48px targets, semantics, long
  titles, missing artwork, and each CTA/status variant.

---

## Page 1 — App shell

**Source:** `lib/widgets/tab_bars.dart`

**Goal:** Apply the new navigation treatment without changing routes or
audience-specific access.

### Planned changes

- [ ] Restyle the fan tabs as GIGS / EXPLORE / PROFILE / BANDS and the managing
  tabs as DASH / PROFILE / GIGS / INSIGHTS.
- [ ] Use the redesigned translucent background, top hairline, selected brand
  indicator, and compact tracked labels.
- [ ] Retain safe-area padding and the existing behavior for zero, one, or
  multiple band memberships.
- [ ] Keep the GIGS managing tab admin-only and preserve all current navigation
  semantics and focus handling.

### Page acceptance

- Four tabs fit at supported text scales without clipped labels or targets
  smaller than 48px.
- Selected state is exposed through semantics and not indicated by color alone.

---

## Page 2 — Home

**Source:** `lib/screens/home.dart`

**Goal:** Make the feed poster-first and date-scannable while keeping the same
discovery results and filters.

### Planned changes

- [ ] Recompose the header around the EarPlug wordmark, LIST/MAP control,
  location picker, and existing filter shortcuts.
- [ ] Style TONIGHT / THIS WEEK / FREE as conviction chips and retain access to
  the full discovery filter sheet.
- [ ] In list mode, promote the first filtered feed item to the featured poster
  treatment and remove it from the compact rows below to avoid duplication.
- [ ] Derive any presenter label from already-loaded creator/lineup data; omit
  it when the source is unavailable.
- [ ] Group the remaining loaded feed into Tonight, This Week, and Later using
  existing client-side date classification.
- [ ] Preserve Map mode, map markers, filter recovery, discovery boost labels,
  location behavior, feed bounds, and all loading/error/empty states.
- [ ] Preserve the current Map default unless product explicitly approves a
  change to List default.

### Page acceptance

- The featured item and compact rows come from exactly the same filtered feed.
- Switching List/Map or changing any filter cannot change or duplicate the
  underlying result set.

---

## Page 3 — Gig detail

**Source:** `lib/screens/gig_detail.dart`

**Goal:** Present the gig as a poster with one accurate primary action.

### Planned changes

- [ ] Recompose the existing flyer/generated press as the hero with title and
  optional presenter metadata derived from existing gig/band data.
- [ ] Consolidate date, doors, venue, neighborhood, price, age, and going count
  into a single scannable facts area.
- [ ] Render the lineup as person-like band rows with avatar, name, genres, and
  the existing follow action where a performer resolves to an EarPlug band.
- [ ] Keep text-only and invited performers readable without offering invalid
  profile/follow actions.
- [ ] Retain About copy, venue map/directions, vague attendance treatment,
  save/share, direct-link loading, and cancelled-gig messaging.
- [ ] Use a sticky CTA whose copy distinguishes external ticket purchase from
  free or pay-at-door RSVP. Do not imply EarPlug charges the displayed cover.

### Page acceptance

- Cancelled gigs cannot expose an active RSVP/ticket CTA.
- Every performer kind and ticketing mode has a valid, tested presentation.

---

## Page 4 — Fan analytics

**Source:** `lib/screens/analytics.dart`

**Goal:** Turn the existing recap into an answer board without changing its
data or privacy model.

### Planned changes

- [ ] Keep the band switcher and add the concise aggregate-only privacy caption.
- [ ] Lead with existing show, measured RSVP, and average-per-show totals using
  `StatTile` components.
- [ ] Compute the best-show takeaway locally from the existing `BandRecap` and
  present it as the page's volt treatment.
- [ ] Recompose turnout as a readable column chart using existing values; no
  charting backend or new payload is required.
- [ ] Preserve every current section: turnout, new vs returning, commit timing,
  rooms, weekdays, and repeat fans.
- [ ] Render suppressed partitions as explicit dashed `SUPPRESSED` states with
  the existing reason instead of blank or misleading zero values.
- [ ] Preserve truncated-window and measured-vs-reported footnotes.

### Page acceptance

- The same `BandRecap` object can drive both current and redesigned tests.
- No UI path reveals individual fans or reconstructs suppressed partitions.

---

## Page 5 — Explore

**Source:** `lib/screens/explore.dart`

**Goal:** Give search and browse results a single hierarchy across events,
bands, and venues.

### Planned changes

- [ ] Restyle the existing search field and keep submit, clear, draft-query, and
  retry behavior.
- [ ] Present EVENTS / BANDS / VENUES as scope chips while retaining the current
  combined/ALL behavior as the default or equivalent unscoped state.
- [ ] Add visible genre shortcuts using existing genre/search/filter state; the
  dashed add chip opens the existing discovery filter sheet.
- [ ] Render event results with compact `DateBlock` cards.
- [ ] Render band results as avatar rows with genres, follower count when
  already loaded, and the existing follow action.
- [ ] Preserve venue results, band pagination, browse rails, empty states,
  directory failures, and lazy construction of off-screen results.
- [ ] Keep the existing search scope: event matching is bounded to loaded feed
  data. Do not describe it as exhaustive global search without a future backend
  project.

### Page acceptance

- Changing scope does not rerun or widen backend queries.
- All current result types and retry/pagination paths remain reachable.

---

## Page 6 — Fan profile

**Source:** `lib/screens/my_gigs.dart`

**Goal:** Put the next show first while preserving the full private fan record.

### Planned changes

- [ ] Promote the nearest upcoming in-app RSVP to a `VoltStrip` with date,
  title, venue/doors, and the existing QR pass action.
- [ ] Avoid showing a QR action for external-ticket gigs; retain their correct
  ticket behavior in the remaining list.
- [ ] Recompose identity as avatar, name, fan-since date, past-RSVP count, bio,
  and edit entry.
- [ ] Render upcoming RSVPs and saved shows with compact date-led cards.
- [ ] Render followed bands as avatar rows and private event history as
  `LedgerRow` items.
- [ ] Keep followed-band upcoming shows, fan onboarding/tutorial, band entry,
  Create Band, Settings, and every existing empty/recovery action even where
  the mockup does not show them.
- [ ] Continue describing history as RSVP history, not verified attendance.

### Page acceptance

- Every current profile section remains reachable.
- The next-show strip disappears cleanly when there is no eligible upcoming
  RSVP and does not leave a duplicate row.

---

## Page 7 — Venue detail

**Source:** `lib/screens/venue_detail.dart`

**Goal:** Give venues the same press/date/ledger grammar as gigs and bands.

### Planned changes

- [ ] Recompose venue name, address, area, distance, and existing map data into
  the press-style hero/facts area.
- [ ] Render upcoming events as compact `DateBlock` rows using the shared gig
  component.
- [ ] Preserve the performing-band section, navigation to band pages, 200-row
  truncation notice, map behavior, and all loading/missing/error states.
- [ ] Do not add a past-events ledger or door-policy field: neither is present
  in the current venue payload. These require a separately approved backend
  project.

### Page acceptance

- Venue detail uses only the existing `VenueDetail` payload.
- Truncated and empty calendars remain explicit and accurate.

---

## Page 8 — Band profile

**Source:** `lib/screens/band_profile.dart`

**Goal:** Make the public band page feel like a press page while retaining all
media and profile depth.

### Planned changes

- [ ] Build the hero from existing band color, initials/photo, area, genres,
  biography, and follower count.
- [ ] Promote Follow to the single full-width primary CTA and retain the
  following state.
- [ ] Restyle existing Bandcamp, Instagram, and YouTube links as outline pills
  without fabricating missing URLs.
- [ ] Recompose the pinned clip into the compact sound-sample treatment while
  preserving playback, processing, and unavailable-media states.
- [ ] Render upcoming gigs as date-led rows, photos as a press-tinted strip with
  overflow count, and past gigs as ledger rows.
- [ ] Preserve clips, credits, member names, public-preview controls, admin edit
  entry, history retry, and all managed/public access differences.

### Page acceptance

- Missing links, photos, clips, upcoming gigs, or history collapse without
  leaving empty chrome.
- Managed preview remains visibly distinct and returnable to the dashboard.

---

## Page 9 — Band dashboard

**Source:** `lib/screens/band_dash.dart`

**Goal:** Turn the management landing page into a clear show-night command
surface.

### Planned changes

- [ ] Retain the band/role switcher, public discovery exit, and role-aware
  controls in the header.
- [ ] Promote the next upcoming gig to a `VoltStrip` with live RSVP count and a
  direct Door Mode action when the project is eligible.
- [ ] Present followers, next-gig RSVPs, and clip count as three `StatTile`
  components.
- [ ] Recompose Publish Gig, Add Media, Analytics, and Edit Profile as a 2×2
  command grid; retain admin restrictions.
- [ ] Keep Preview Public Profile as a quiet link.
- [ ] Preserve the real six-item discovery readiness model and the separate
  seven-item setup model. Do not replace them with the mockup's inaccurate
  five-segment summary.
- [ ] A consolidated card may summarize both models, but every task, completion
  state, and deep link must remain visible or expandable.

### Page acceptance

- Admins and members see only the actions their current roles allow.
- Readiness and setup counts exactly match their existing data sources.

---

## Page 10 — Gig manager

**Source:** `lib/screens/gig_manager.dart`

**Goal:** Put daily gig actions on the card and move lifecycle/destructive
actions into a deliberate sheet.

### Planned changes

- [ ] Keep the Gigs header and make New Gig the single primary header action.
- [ ] Render published/upcoming projects as date-led cards with title, venue,
  status, and going count only when the corresponding public gig is already
  available to the client.
- [ ] Expose Door, Preview, and Edit on eligible card faces with existing route
  and role checks.
- [ ] Replace the popup menu with an `ActionSheet` containing Duplicate,
  Unpublish, Cancel, and Delete; keep confirmation and consequence copy.
- [ ] Render drafts as `GhostDraftRow` items with their actual missing/incomplete
  state when that can be derived locally.
- [ ] Preserve published, draft, cancelled, and past groupings; all seven
  existing actions must remain reachable.
- [ ] Preserve refresh, loading, empty, unpublished-changes, and lifecycle error
  behavior.

### Page acceptance

- No lifecycle action can be invoked for an ineligible project state.
- Delete remains the only red action and Cancel/Unpublish keep confirmation.

---

## Page 11 — Door Mode

**Source:** `lib/screens/door_mode.dart`

**Goal:** Separate monitoring from scanning so show-night operation is
glanceable and camera-focused.

### Planned changes

- [ ] Split the existing modal into Viewer and Scanner states while retaining
  the same project and authorization context.
- [ ] Viewer shows gig identity, checked-in/total count, progress, Open Scanner,
  and Enter Ticket Code actions.
- [ ] Scanner dedicates the main viewport to `MobileScanner`, adds the volt
  bracket frame, and retains the current camera-unavailable guidance.
- [ ] Keep automatic detection, scan locking, roster refresh, and manual code
  fallback on the same check-in mutation.
- [ ] Render checked-in, already-checked-in, wrong-gig, and invalid outcomes
  with both text/icon and their designated status color.
- [ ] A recent-check-ins ledger may contain only successes from the current
  open session. The current roster payload has totals only, so do not imply
  persistent history, guest-list sources, or cross-device synchronization.
- [ ] Surface the existing roster truncation state if it occurs.

### Page acceptance

- Closing Scanner stops camera use and returns to Viewer without losing the
  current session's count/result state.
- Manual entry remains fully usable when camera permission is denied.

---

## Page 12 — Edit fan profile

**Source:** `lib/screens/edit_profile.dart`

**Goal:** Apply the shared form grammar without adding unsupported preference
semantics.

### Planned changes

- [ ] Recompose avatar selection/removal with the edit badge and explicit
  accessible labels.
- [ ] Restyle name, bio, home location, and favorite genres using labelled
  fields, section bars, and conviction chips.
- [ ] Restyle the two existing preferences—location personalization and
  followed-band updates—as `SwitchRow` components with current explanatory
  copy.
- [ ] Do not add Going Count Visibility or Gig Reminders switches: neither has
  a stored preference or implemented behavior in the frozen contract.
- [ ] Pin Save Changes in a `StickyActionBar` while preserving validation,
  avatar upload sequencing, error recovery, and unsaved field contents.

### Page acceptance

- Save failure leaves every text, chip, switch, and selected image intact.
- Long names, bio limits, text scaling, and disabled-saving state remain usable.

---

## Page 13 — Edit band profile

**Source:** `lib/screens/band_edit.dart`

**Goal:** Give band administration the same form grammar while preserving
secure membership and archive behavior.

### Planned changes

- [ ] Keep Required Details and Optional Details, restyled with section bars and
  labelled cards.
- [ ] Present genres as removable choice chips with the existing three-genre
  limit and custom Add flow.
- [ ] Preserve home base, bio, Instagram, Bandcamp, YouTube, credits, and the
  Manage Music and Media route.
- [ ] Render accepted member names as read-only chips. Do not add removal
  controls because the current payload has no member IDs/roles and there is no
  removal mutation.
- [ ] Preserve create/copy/rotate/revoke invitation behavior and its loading,
  expiry, and retry states.
- [ ] Move Archive Band into a low `DangerZone` while keeping the current typed
  confirmation and full consequence copy.
- [ ] Do not promise member self-service restore; no restore mutation exists.
- [ ] Keep Preview Public Profile available as a quiet top-level action.

### Page acceptance

- All existing editable fields and invitation actions remain reachable.
- Archive copy matches actual cleanup behavior and never suggests unsupported
  recovery.

---

## Page 14 — Create and edit gig

**Source:** `lib/screens/gig_create.dart`

**Goal:** Make the current resilient draft workflow read like a poster and
checklist rather than a long form.

### Planned changes

- [ ] Retain Close, draft identity, explicit Save Draft, and the existing live
  `gfSaveState`; visually emphasize that autosaved drafts are real.
- [ ] Keep the gig name as the poster-scale hero field.
- [ ] Recompose Date, Times, Venue, Cover, Access, and Audience into a responsive
  2×3 slot grid. Each tile opens its existing picker/sheet.
- [ ] Preserve required-state validation, after-midnight time handling, venue
  creation, cover presets, ticket URL validation, RSVP caps, and age rules.
- [ ] Restyle performers as compact chips/rows while retaining ordering,
  billing role, remove, existing-band selection, invited-performer links, and
  text-only performers.
- [ ] Preserve the flyer studio, uploaded-art path, overlay choice, press
  swatches, OCR suggestions, upload progress, and processing failures.
- [ ] Keep Additional Information and represent the existing age requirement as
  the available publish setting.
- [ ] Do not add Listed in Discovery or Door List Enabled switches. Visibility
  currently follows publish/lifecycle rules, and Door Mode follows in-app RSVP
  ticketing; independent switches would require contract changes.
- [ ] Pin Preview and Publish/Publish Updates in the `StickyActionBar` and retain
  all current eligibility and save-before-publish behavior.

### Page acceptance

- Closing during a dirty or in-flight draft preserves the current save
  guarantees.
- Draft, published, unpublished-changes, cancelled, custom-art, external-ticket,
  and in-app RSVP variants remain testable.

---

## Pages outside this refresh

Leave `auth.dart`, `band_create.dart`, `band_join.dart`, `band_media.dart`,
`gig_invite.dart`, and `settings.dart` structurally unchanged. Shared theme
updates may affect them, so include them in regression and contrast checks.

## Suggested delivery sequence

1. Shared theme/components and both event-card variants.
2. App shell, Home, Gig Detail, and Explore.
3. Fan Profile, Venue Detail, and Band Profile.
4. Analytics, Band Dashboard, and Gig Manager.
5. Door Mode, both profile editors, and Create/Edit Gig.
6. Cross-platform regression, accessibility, and screenshot review.

Each page should land with its focused widget tests and without depending on an
unfinished later page. Final verification should include `flutter analyze`, the
complete Flutter suite, the Convex suite, 1.5× text scaling, keyboard focus,
guest/authenticated/admin/member roles, narrow phones, and the centered web
layout.
