# hygge.rb — Rails site, RSVP, and domain

Date: 2026-07-20

## Goal

Replace the current static `index.html` with a Rails 8 application that renders the
hygge.rb landing page at high fidelity to the design handoff, accepts real RSVPs into
Postgres with a server-enforced 40-seat cap, sends confirmation email, and serves from
the custom domain `hyggerb.dk` on Render.

The design handoff lives at `~/Downloads/design_handoff_hygge_rb` (`index.html` is the
primary reference; `README.md` documents tokens and section-by-section intent).

## Non-goals

- Multi-page site. This is one scrolling page; extra pages come later if ever.
- Porting `image-slot.js`. The handoff explicitly says not to.
- A CFP submission tool. The CFP buttons stay as configurable external URLs.
- Scroll animations, parallax, entrance effects. The design is deliberately calm.

## Stack

- Rails 8, Ruby 3.3+
- Postgres (Render managed)
- Propshaft + plain CSS. No Tailwind, no CSS build step.
- ERB partials. No ViewComponent.
- Turbo (default Rails 8) for the RSVP form swap. No Stimulus controllers needed.
- Minitest + Capybara

Rationale: the handoff is finished, hand-authored CSS built on custom properties.
Re-expressing it as Tailwind utilities is a rewrite with drift risk and no gain for a
single page. Plain CSS ports it nearly verbatim.

## Repo shape

```
app/
  controllers/
    pages_controller.rb          # GET /
    rsvps_controller.rb          # POST /rsvps
    admin/rsvps_controller.rb    # GET /admin/rsvps, /admin/rsvps.csv
  models/rsvp.rb
  mailers/rsvp_mailer.rb
  views/
    pages/home.html.erb
    pages/_header.html.erb  _hero.html.erb   _about.html.erb  _rsvp.html.erb
    pages/_cfp.html.erb     _schedule.html.erb _venue.html.erb _sponsors.html.erb
    pages/_faq.html.erb     _footer.html.erb
    rsvps/_form.html.erb    _confirmation.html.erb  _full.html.erb
    shared/_coffee_cup.html.erb
  assets/
    stylesheets/tokens.css  base.css  components.css
    fonts/                  # self-hosted woff2
    images/venue-dentsu-aarhus.png
config/event.yml             # schedule rows, CFP timeline, FAQ, facts, sponsor list
db/migrate/..._create_rsvps.rb
test/
render.yaml
```

Structured page content (schedule rows, CFP timeline entries, FAQ Q&A, the three facts
cells, sponsor cards) lives in `config/event.yml` and is rendered by loops, so editing a
schedule time is a one-line data change rather than a markup edit.

The existing root `index.html` is deleted — the Rails app supersedes it.

## Design system

### Tokens (`tokens.css`)

Copied verbatim from the handoff as CSS custom properties on `:root`:

| Token | Value | Use |
|---|---|---|
| `--paper` | `#f7f1e7` | page background |
| `--card` | `#fffdf8` | cards, input resting surface |
| `--ink` | `#201b16` | primary text |
| `--ink-soft` | `#4a4036` | body, secondary text |
| `--muted` | `#837563` | labels, meta, mono captions |
| `--rule` | `#e2d6c2` | hairline dividers |
| `--rule-2` | `#d3c4ab` | card and input borders |
| `--ruby` | `#bb1f2c` | brand accent |
| `--ruby-deep` | `#7d1219` | hover, glyph strokes |
| `--ruby-tint` | `#f6e4dd` | light tint |

Selection is ruby background on white text. Text on ruby is `#ffffff`.

Geometry: content column max-width 720px, header bar 940px, 24px horizontal padding,
64px section vertical padding, 1px rules throughout, radii 7px (buttons/inputs), 4px
(pill), 8-12px (cards), 10px (venue photo). No shadows at rest.

### Typography

Three families, **self-hosted** in `app/assets/fonts` as woff2 with `font-display: swap`:

- Space Grotesk 400/500/600/700 — headings, wordmark, UI, buttons, labels
- Newsreader 400/500 + italic — body prose, hero description, schedule events
- JetBrains Mono 400/500 — eyebrows, kicker, dates, table times, meta

Self-hosted rather than the Google Fonts CDN because the CDN transmits EU visitor IP
addresses to Google, which has been ruled a GDPR violation in German and Austrian courts.
The event is Danish and the audience is European. Same faces, identical rendering, one
fewer third-party dependency.

Scale: body Newsreader 19px/1.6; lead 21px; hero description 22px; H1 `clamp(46px, 9vw,
88px)` weight 700 tracking -0.04em line-height 0.98; section H2 Space Grotesk 600 30px
tracking -0.02em; eyebrow mono 12.5px tracking 0.08em lowercase ruby.

### Components (`components.css`)

Buttons (primary/ghost, 1px hover lift, 150ms, arrow nudges 3px), facts strip, RSVP card,
form inputs, CFP criteria list, CFP timeline, schedule table, venue photo + meta list,
sponsor cards, FAQ `<details>` accordion.

The coffee-cup glyph is an inline SVG partial (`viewBox 0 0 36 32`, ruby cup, deep-ruby
strokes, three steam wisps, highlight), used in header and footer.

### Behavior

- Smooth scroll via CSS `scroll-behavior`.
- Sticky header, translucent paper background, `backdrop-filter: blur(6px)`, z-index 40.
- FAQ uses native `<details>`/`<summary>`; the "+" rotates 45deg to an "×" via
  `details[open] .faq-q .plus`. Zero JavaScript.
- Responsive: facts strip collapses to one column below 560px; top nav hides below 680px;
  timeline columns tighten below 480px.

**Mobile nav.** The prototype simply hides the nav below 680px with no replacement. Ship
that behavior as-is. The page is a single scroll with a visible section order and every
nav target is reachable by scrolling; a hamburger for five anchor links on one page is not
worth the JavaScript. Revisit only if analytics show mobile users failing to reach RSVP.

## RSVP

### Model

```ruby
# rsvps
name        :string  null: false
email       :string  null: false
dietary     :text
waitlisted  :boolean null: false, default: false
created_at, updated_at
# index on lower(email), unique
```

Validations: `name` present; `email` present and matching `URI::MailTo::EMAIL_REGEXP`;
`email` unique case-insensitively. Duplicate email returns the existing reservation's
confirmation rather than an error — someone re-submitting has not done anything wrong.

### Seat cap

`Rsvp::CAPACITY = 40`. Creation runs inside a transaction that locks and counts
non-waitlisted rows; at or above capacity the record is created with `waitlisted: true`
and the form area renders the "we're full — you're on the waitlist" state instead of the
standard confirmation. Waitlisting rather than rejecting preserves the list when
attendees drop out.

### Flow

`POST /rsvps`, Turbo-driven. The RSVP card contains a turbo-frame:

- **Valid, seats left** → frame swaps to `_confirmation`: "Tak! Your seat is reserved.
  See you on the 28th. ☕"
- **Valid, at capacity** → frame swaps to `_full` (waitlist wording)
- **Invalid** → frame re-renders `_form` with inline errors beneath the offending fields,
  focus moved to the first invalid input

### Spam protection

Three layers, no third-party script:

1. **Honeypot** — a hidden `company` field, off-screen and `aria-hidden`, `tabindex="-1"`,
   `autocomplete="off"`. If filled, the request returns the normal confirmation and
   persists nothing.
2. **Timing check** — a signed timestamp rendered into the form; submissions faster than
   3 seconds are treated as bot traffic and handled like the honeypot.
3. **Rate limit** — Rails 8 `rate_limit to: 5, within: 1.minute` on `create`, keyed by IP.

Cloudflare Turnstile was considered and rejected: it adds a third-party script and a
visible challenge to a page whose whole design premise is calm and unobtrusive, for a
~40-person free event that is not a high-value spam target.

### Email

ActionMailer over Resend SMTP.

- **Attendee confirmation** — plain, warm, one paragraph: seat confirmed, date, venue
  address, and how to release the seat if plans change.
- **Organiser notification** — to an address from `ORGANISER_EMAIL`, containing name,
  email, dietary needs, and the current seat count.

Both are `deliver_later` so a mail outage cannot fail an RSVP.

**Dependency:** Resend requires SPF and DKIM records on `hyggerb.dk`, so email cannot be
verified end-to-end until the domain is registered and DNS has propagated. Development
and test use `letter_opener` and Minitest's delivery assertions, which fully cover the
mailer logic. Production mail is switched on by setting the SMTP env vars once DNS
verifies — no code change.

### Admin

`GET /admin/rsvps`, HTTP Basic auth from `ADMIN_USER` / `ADMIN_PASSWORD` env vars, using
`ActiveSupport::SecurityUtils.secure_compare`. Shows a seat counter (`n / 40`, plus
waitlist count) and a table of name, email, dietary needs, timestamp, waitlist flag.
`GET /admin/rsvps.csv` exports the same data.

## Deployment

### Render

`render.yaml` declares a `web` service (`runtime: ruby`) plus a Postgres database.

```
buildCommand:  bundle install && bundle exec rails assets:precompile
startCommand:  bundle exec rails db:migrate && bundle exec puma -C config/puma.rb
```

Env vars: `RAILS_MASTER_KEY`, `DATABASE_URL` (from the DB), `RAILS_ENV=production`,
`ADMIN_USER`, `ADMIN_PASSWORD`, `ORGANISER_EMAIL`, and the Resend SMTP credentials.

`config.force_ssl = true`. Apex is canonical; `www` redirects to it.

**The existing Render service cannot be reused.** Its runtime is `static`, and Render does
not allow changing a service's runtime in place. A new web service is created; the old
static service is deleted only after the new one is confirmed serving correctly.

### Domain

Target: `hyggerb.dk`.

Ordering, with owner marked:

1. **User** — register `hyggerb.dk` through a DK Hostmaster reseller (one.com, Simply.com,
   or DK-Hostmaster directly). Roughly 50-100 DKK/year. `.dk` registration requires
   MitID or, for foreign registrants, a paid identity verification step.
2. **Claude** — create the Render web service and Postgres, deploy, confirm the site
   serves correctly on its `.onrender.com` URL.
3. **User** — add the custom domain in the Render dashboard; Render returns the DNS
   targets.
4. **Claude** — supply the exact records to enter at the registrar: apex ALIAS/A and `www`
   CNAME for Render, plus Resend's SPF, DKIM, and DMARC records.
5. **Claude** — verify certificate issuance and the `www` → apex redirect, enable
   production SMTP, then delete the old static service.

Steps 2 and everything before it are independent of the domain, so the site goes live on
`.onrender.com` regardless of how long `.dk` registration takes. Steps 1 and 3 require
account access Claude does not have.

**If `.dk` registration is blocked** by the MitID requirement, fall back to `hyggerb.com`
via Cloudflare or Porkbun. Decide before the DNS step; the rest of the build is unaffected.

## Testing

Minitest, with Capybara and headless Chrome for system tests.

**Model** — name and email presence, email format, case-insensitive uniqueness, the
capacity boundary (the 40th RSVP is confirmed, the 41st is waitlisted).

**Request** — a valid RSVP persists and enqueues both mails; an invalid RSVP re-renders
with errors and persists nothing; a filled honeypot returns the confirmation and persists
nothing; a sub-3-second submission is discarded; `/admin/rsvps` returns 401 without
credentials and 200 with them; the CSV export returns the right content type.

**System** — fill the form, submit, see the confirmation text without a full page reload.

Static markup is not tested.

## Open items

- `.dk` registration may require identity verification the user cannot complete. Confirm
  before the DNS step.
- CFP submission URL and guidelines URL are placeholders in the handoff. They become
  `config/event.yml` values, defaulting to `#` until real URLs exist.
- Sponsor logos are text-set names for now, per the handoff. Swap for images when
  available.
