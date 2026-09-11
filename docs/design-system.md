# EarPlug interface

The shared theme in `lib/theme.dart` defines the appearance of every page.
Use semantic text roles and colors from the active theme for UI. Archivo Black
is reserved for branding, posters, and artist identity; functional headings use
Archivo. Body copy uses regular weight so it does not compete with headings.

## Layout

- Below 960 logical pixels, navigation stays at the bottom and the app fills
  the available width up to 600 pixels.
- At 960 pixels and above, the app uses a 1,120-pixel workspace with persistent
  side navigation. Fixed form actions meet the bottom of the content panel.
- Use `EpPageHeading` when a title has an action or description. Actions move
  below long titles on compact layouts and at larger text scales.
- `StickyActionBar` stacks its buttons on narrow screens with enlarged text.
  Use `actionBarClearance(context)` for the corresponding scroll padding.
- Cards use a 16-pixel default radius; controls use 12 pixels. Icon controls
  retain 48-pixel tap targets around a 40-pixel visible surface.

## Color and media

Blue identifies primary actions and selected navigation. Yellow highlights use
`highlight` and `onHighlight`, which preserve the same yellow and dark-ink
pairing in both themes. Use `volt` for readable accent text on page surfaces.

Photo and video overlays keep light text on dark scrims in either theme.
Media fallback artwork also stays dark. It must not inherit light-mode text
colors when the artwork behind it remains dark.

Segmented controls, dialogs, sheets, progress indicators, and snackbars have
shared theme defaults. Prefer these defaults over page-specific styling.

## Popup sheets

Use `EpSheetShell` and `EpFormSheet` for popup surfaces. Sheet titles use the
`epSheetTitle` role (20px semibold Archivo). Pass titles and action-sheet
labels already in sentence case; the widgets render them verbatim. Form bodies
scroll above the keyboard and clear the bottom safe area while the close
control remains at the top. Keep page typography and creation flows
independent of popup styling.

Discovery filters show genres directly as chips, including the existing
"Any genre · I'm open" reset. Do not add a nested genre picker or a venue
selector to these filters: the discovery venue list is not a complete directory.
Keep the results action in the footer and Clear all in the header so both
remain reachable while scrolling without taking height from the options. Date,
genre, distance and price filters retain their existing live application
behavior.

## Input forms

Use `EpLabeledField` for labelled text entry. The label stays above the text
box, with an 8-pixel gap, and remains associated with the editable field for
screen readers. Required labels are explicit. Input text uses the `epInput`
role: 16-pixel Archivo at regular weight. Brand/display fonts belong in previews,
not editable values.

The input itself is the only bordered surface. Do not put a field, genre picker,
or group of preferences inside another card. `FormSection` groups controls with
a heading, description, and whitespace. Cards remain appropriate for actual
content previews and selectable items.

- Leave `EpLayout.fieldGap` (20 pixels) between fields and control groups.
- Use `SectionBar.form` or `FormSection` for 32-pixel section spacing.
- Use `EpFieldRow` for related inputs. It stacks them below 480 pixels or with
  enlarged text instead of squeezing labels and validation messages. Its input
  subtree stays mounted across width changes, as does the shell's content panel,
  so resizing preserves unsaved edits and focus.
- Let `inputDecorationTheme` supply the 56-pixel minimum height, 16-pixel inset,
  12-pixel corners, and focus, disabled, and error borders. Sheets use the same
  input treatment as pages.
- Keep helper text below the field and use `errorText` for field validation.
  Use the appropriate keyboard and autofill hints. Single-line fields default
  to Next; search, verification, and terminal actions can override it.

The existing form suites exercise save/retry behavior, dirty drafts, required
fields, address suggestions, invitations, ticket amounts, authentication, and
keyboard access. `form_bits_test.dart` also verifies that visible labels remain
accessible and Next moves focus without losing entered values.

## Page coverage

`test/design_audit_test.dart` renders and scrolls every `Screen` value with
demo data in four configurations: 390×844 dark, 390×844 light, 1280×900 light,
and 360×800 dark with 1.5× text. The enum-driven matrix automatically includes
new routes, although routes requiring parameters must receive a fixture.

| Area | Pages |
| --- | --- |
| Discovery and fan account | Home, Explore, gig detail, band profile, venue detail, Profile, Edit Profile, Settings |
| Sign-in and invitations | Auth, band invitation, lineup invitation, organization invitation |
| Band workspace | Dashboard, Edit Band, public profile preview, Create Band, Band Media, Gigs, gig editor, Analytics, Payouts |
| Organizer workspace | Application, application status, Dashboard, Venues, venue editor, Team, Settings, Opportunities, opportunity editor, applicants |
| Booking and returns | Opportunity detail, booking detail, review composer, checkout return, checkout cancellation, Stripe return |
| Ticketing | Ticket wallet, ticket with QR code, ticket checkout return, ticket checkout cancellation |
| Administration | Application queue and application review |

The matrix includes unavailable invitation links, a submitted organizer
application, confirmed booking and ticket checkouts, a valid ticket, an active
ticket hold, and an invalid Stripe return. The focused
test suites cover additional loading, error, permission, and success states,
as well as Door Mode, photo/video viewers, and modal sheets.

Run the layout matrix:

```sh
flutter test test/design_audit_test.dart
```

Export screenshots of page tops and scroll ends for visual inspection:

```sh
EP_DESIGN_CAPTURE=/tmp/earplug-design flutter test test/design_audit_test.dart
```

Optionally set `EP_DESIGN_VIEW` to `mobile-dark`, `mobile-light`, `desktop`, or
`large-text`. Captures use bundled fonts and deterministic demo fixtures;
network artwork and map tiles use fallbacks. Use the demo web build to review
browser rendering, live map tiles, keyboard interaction, and theme changes.

These checks validate the client interface. They do not submit live payments,
send invitations, or deploy the production site.
