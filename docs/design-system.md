# EarPlug interface

The theme in `lib/theme.dart` owns typography, colors and control dimensions.
Use Archivo for headings and inputs; reserve Archivo Black for branding,
artist identity and actual posters. Blue identifies primary actions. Yellow
highlights pair `highlight` with `onHighlight` in both themes. Media overlays
retain light text on a dark scrim.

## Form layout and actions

Use the existing components in `lib/widgets/form_bits.dart`.

- One form column: 640 pixels of content, with 16-pixel side padding. The
  desktop navigation breakpoint remains 960 pixels; public pages retain
  their wider workspace.
- Input text is 16-pixel Archivo. Fields have 56-pixel minimum height,
  16-pixel insets and 12-pixel corners. Interactive targets are at least
  48 pixels. Use 20 pixels between fields and 32 between sections.
- Sentence case for functional headings, field labels and actions. Keep
  names, acronyms, branding and preview typography intact.
- Border the input itself. Use whitespace and headings to group fields;
  avoid decorative required-state cards and permanent completion lists.
- `EpFormLayout` measures its scrollable and footer. Put `StickyActionBar`
  in `footer`; never position a form action above a guessed navigation offset.
  `constrainWidth: false` supports embedded actions on public detail pages.
- The root `Scaffold` owns mobile navigation through `bottomNavigationBar`.
  Navigation yields its space to the keyboard. Desktop forms have a separate
  `FocusTraversalGroup`, so Tab follows the form before returning to navigation.
- Present one primary action. Back, Preview and Save draft are secondary.
  Place destructive actions in `DangerZone` outside the normal save area.
  Short forms name their action: Accept offer, Withdraw application,
  Cancel booking, Resolve dispute, Remove location.

`EpFieldRow` is reserved for closely related inputs. It stacks on narrow
screens and with enlarged text. `EpPageHeading` moves actions below long
headings when needed. Existing public-page overlays may still use
`actionBarClearance`; new form footers must participate in layout.

## Steps, sections and selections

`EpFormSteps` names all steps and permits returning to earlier ones. Continue
validates the current step; it never publishes or submits. `EpFormStep` keeps
inactive content mounted and removes it from focus and accessibility traversal.
One editor owns the controllers, selections, uploads and draft identity for
all steps. Gig editor generations reset navigation when starting another gig.

| Creator | Steps |
| --- | --- |
| Gig | Basics → Lineup → Admission → Poster and review |
| Opportunity / private request | Event → Artist slots → Details → Access → Review |
| Organizer application | Organization and venue → Contact and verification → Review |
| Host application | Your details → Verification and review |

Existing records open in `EpDisclosure` sections, with the essential section
open initially. A closed section shows its current value summary. Its content
remains mounted; collapsing it does not clear controllers, selections or upload
state. Use the same sections for optional biography, artwork, links, credits,
logistics and messages. Artwork is never a creation prerequisite.

`EpSelectionField<T>` presents a labelled selected-value summary and opens a
searchable picker. Single selections use radio semantics. Multiple selections
use checkbox semantics and a temporary selection: Done commits, closing cancels,
and Clear affects only the pending picker selection. Limits disable additional
choices without preventing removal. Band genres retain the three-genre limit
and custom-genre entry; opportunity genres retain their existing limit.

Use `VenueLocationEditor(compactMap: true)` for address editing. Address
suggestions update the location summary; Adjust map opens the manual pin editor.
Cancel leaves the original pin untouched and Done applies it. Creating a missing
private location opens a nested editor and returns the selection without
unmounting or clearing the request draft. Keep explicit city
entry and existing address disclosure rules. Explain privacy beside the relevant
location control, once.

## Validation and persistence

Wrap text entry in `EpForm`. `EpLabeledField` retains the visible label and
appropriate input/autofill semantics. Validation starts on Continue or Save,
then updates as the user corrects a field. `EpFormState.validate()` opens the
first invalid disclosure, scrolls to its field and requests focus. Non-text
requirements and server failures use `InlineFormFeedback` with a useful action
or route back to the affected section.

Keep repository calls, permission checks, amounts and server validation in the
existing editor. A step transition or picker opening cannot trigger the final
action. Save draft stays separate from publish/open/submit. New opportunities
can save a draft from any step, using the existing draft requirements.

Show Saved only after persistence succeeds. Existing autosave queues and retry
barriers remain in place. Host and organizer Close actions flush pending edits;
failed saves keep the application open. Opportunity Close offers Keep editing
or Discard changes when edits are unsaved. Profile dirty-exit recovery and gig
draft recovery retain their existing behavior. A browser refresh is not a
substitute for explicitly saving an editor that does not autosave.

## Route coverage checklist

`test/design_audit_test.dart` derives its route matrix from `Screen.values`:
51 routes × four configurations (390×844 dark/light, 1280×900 light,
360×800 dark with 1.5× text). It scrolls the routes, expands disclosure sections,
checks keyboard-open inputs and measured action bounds, and exercises the
intermediate gig and opportunity creation steps. The route identity and
backend contract are unchanged.

Checked entries identify coverage in the route matrix. Conditional workflow
behavior is additionally covered by the focused suites listed below.

| Checked | Route | Form/control treatment |
| --- | --- | --- |
| [x] | `home` | Discovery location, filters and search controls |
| [x] | `gig` | RSVP, ticket entry and purchase sheet |
| [x] | `band` | Follow, media and review controls |
| [x] | `bandPreview` | Existing public preview |
| [x] | `bandJoin` | Invitation acceptance and recovery |
| [x] | `gigInvite` | Lineup invitation acceptance |
| [x] | `venue` | Detail controls; existing page structure |
| [x] | `explore` | Labelled search, clear and compact filters |
| [x] | `myGigs` | Following search and profile actions |
| [x] | `auth` | Compact email/code input and Change email |
| [x] | `bandCreate` | Required identity; optional biography, images, links, credits |
| [x] | `bandDash` | Existing dashboard actions |
| [x] | `bandEdit` | Profile, Images, Links and credits, Members |
| [x] | `bandMedia` | Upload, ordering, feature and remove controls |
| [x] | `editProfile` | Profile, Music taste, Preferences; compact photo control |
| [x] | `settings` | Preference and account controls |
| [x] | `gigMgr` | Compact browse filters and focused action sheets |
| [x] | `gigCreate` | Four-step creation; sections for existing gigs |
| [x] | `analytics` | Existing dashboard controls |
| [x] | `orgApply` | Three-step application; documents and draft retry |
| [x] | `orgApplicationStatus` | Needs-information and withdrawal actions |
| [x] | `orgJoin` | Team invitation acceptance |
| [x] | `orgDash` | Existing dashboard actions |
| [x] | `orgVenues` | Venue management actions |
| [x] | `orgVenueEdit` | Identity, Address and access, Operational details |
| [x] | `orgTeam` | Focused invitation section and role descriptions |
| [x] | `orgSettings` | Public profile, Photos, Private details, Payments |
| [x] | `orgFinance` | Export-period choices |
| [x] | `orgTransactions` | Search/filter/export controls |
| [x] | `adminQueue` | Existing queue and filters |
| [x] | `adminApplication` | Start review; focused decision panel |
| [x] | `orgOpportunities` | Draft/publication management actions |
| [x] | `opportunityEdit` | Five-step creation; sections, locks and consent for editing |
| [x] | `opportunityApplicants` | Offer, decline and application controls |
| [x] | `opportunityDetail` | Compact band/slot summaries; optional application notes |
| [x] | `bookingDetail` | Named booking actions and measured footer |
| [x] | `reviewCompose` | Rating and text first; optional category tags |
| [x] | `bandPayouts` | Payment connection and export-period choices |
| [x] | `checkoutReturn` | Existing payment-return handling |
| [x] | `checkoutCancel` | Existing cancellation/retry handling |
| [x] | `stripeReturn` | Existing payment-connection return |
| [x] | `myTickets` | Existing ticket wallet |
| [x] | `ticket` | Existing QR and ticket actions |
| [x] | `ticketCheckoutReturn` | Existing ticket-return handling |
| [x] | `ticketCheckoutCancel` | Existing hold/retry handling |
| [x] | `hostApply` | Two steps; submit above navigation and keyboard |
| [x] | `privateLocations` | Location list and add action |
| [x] | `privateLocationEdit` | Address summary, explicit city and optional operations |
| [x] | `adminSafety` | Context, resolution note and Resolve report |
| [x] | `adminDisputes` | Context, refund amount and Resolve dispute |
| [x] | `adminBookings` | Existing administrative booking controls |

## Sheet and conditional-state checklist

| Checked | Surface | Regression suites |
| --- | --- | --- |
| [x] | Searchable radio/checkbox pickers, cancel, clear, limits | `form_redesign_test`, `band_create_test`, `band_edit_test` |
| [x] | Gig date/time, overnight start, venue, price, ticket access, audience | `gig_create_test` |
| [x] | Poster uploads, presets, overlay, preview, failed upload | `gig_create_test`, media suites |
| [x] | Profile photos, separate band images, media order and featured items | `fan_profile_ui_test`, `band_create_test`, `band_edit_test`, `band_media_test` |
| [x] | Address suggestions, unavailable search, manual map, city and disclosure | `venue_location_editor_test`, `private_locations_test`, `org_editing_test` |
| [x] | Verification documents, agreements, save/retry, needs information | `host_apply_test`, `org_apply_test`, `admin_review_test` |
| [x] | Organization/band invitation roles, generate/reuse/revoke, expiry | `org_manage_test`, `band_edit_test`, invitation suites |
| [x] | Slots, fees, required flags, visibility, invitations, venue approval | `opportunity_edit_test`, `opportunity_manage_test` |
| [x] | Application, offer, cancellation, withdrawal and agreement dialogs | `band_gigs_page_test`, `opportunity_manage_test`, `booking_detail_test` |
| [x] | Review rating/text/tags | `reviews_ui_test` |
| [x] | Disputes, refunds, safety and administrative decisions | `dispute_sheet_test`, `admin_disputes_test`, `admin_safety_test`, `admin_review_test` |
| [x] | Discovery filters and following search | `explore_search_test`, `home_discovery_test`, `fan_accessibility_test` |
| [x] | Ticket quantity → hold → fee review → checkout | `ticket_purchase_sheet_test`, ticket suites |
| [x] | Door scanning and adjacent manual ticket entry | `door_mode_test` |
| [x] | Financial export periods | `band_payouts_test`, `org_finance_test` |
| [x] | Authentication, code recovery and interrupted actions | `auth_test` |

Fixtures cover conditional states without creating production bookings,
payments, invitations or administrative decisions. Hosted Clerk and Stripe
screens are outside this redesign. Browser review supplements widget checks
for rendered layout, focus order and accessible controls.

## Integration and verification

Implement and review on `feat/form-redesign`: shared foundation, core flows,
then remaining surfaces and coverage. There is no Convex schema migration or
new server payload. Existing permission checks and monetary calculations stay
in their current repositories and controllers.

```sh
flutter analyze
flutter test
npm test
EP_DESIGN_CAPTURE=/tmp/earplug-form-redesign flutter test test/design_audit_test.dart
```

`EP_DESIGN_VIEW` can restrict captures to one of the four configuration names.
Captures use bundled fonts and deterministic fixtures with image/map fallbacks.
Use the in-app Browser for web interaction checks.

Push the feature branch and review its Netlify deploy preview using the paired
development Clerk and Convex configuration. Verify the DEV ribbon and affected
flows there. Merge to `main` only through the normal release workflow; Netlify
performs the production contract check and deployment described in
`docs/environments.md`. Feature branch builds must never deploy production.
