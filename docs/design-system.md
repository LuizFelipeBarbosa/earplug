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
