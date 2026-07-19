# Handoff: hygge.rb — conference landing page

## Overview
A single-page marketing/landing site for **hygge.rb**, a tiny, free, one-day Ruby
conference in Aarhus, Denmark (Saturday 28 November 2026). The page announces the
event, explains what it is, collects RSVPs via a form, promotes an open Call for
Proposals (CFP), shows the schedule, venue, sponsors, and an FAQ. The visual
direction is deliberately minimal and content-forward (inspired by
helsinkiruby.fi/tinyruby): a single warm off-white column with one ruby-red accent.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype
showing the intended look, copy, and behavior. They are **not** production code to
ship as-is. The task is to **recreate this design in the target codebase's existing
environment** (React/Next, Vue/Nuxt, Rails + ERB/ViewComponent, Astro, etc.) using
its established components, tokens, and conventions. If no environment exists yet,
pick the most appropriate stack for a small marketing site (a static generator or
Rails is a natural fit given the Ruby theme) and implement it there.

Everything here is hand-authored HTML/CSS/vanilla-JS in one file (`index.html`) plus
one web component (`image-slot.js`) used only for the venue photo placeholder.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, copy, and interactions are all
intended as shown. Recreate the UI faithfully using the codebase's libraries and
patterns. Exact hex values, font families, and the spacing rhythm are documented in
**Design Tokens** below.

## Screens / Views
Single scrolling page. A sticky top header sits above a centered column (max-width
**720px** for content, **940px** for the header bar). Sections are separated by a
1px rule and ~64px vertical padding. Order top → bottom:

### 1. Header (sticky)
- **Purpose:** brand + in-page nav.
- **Layout:** flex row, space-between, 14px vertical padding, max-width 940px centered,
  1px bottom border, translucent paper background with `backdrop-filter: blur(6px)`,
  `position: sticky; top: 0; z-index: 40`.
- **Components:**
  - **Brand** (left): a coffee-cup SVG glyph (24×22, nudged `translateY(-2px)` to
    optically center on the text) + wordmark "hygge**.rb**" in Space Grotesk 600, 17px,
    letter-spacing −0.02em. The ".rb" is ruby red (`--ruby`); the rest is ink.
  - **Nav** (right): 5 links — About, RSVP, CFP, Schedule, Venue — Space Grotesk 500,
    14.5px, color `--ink-soft`, hover `--ruby`. Hidden below 680px (no hamburger in the
    prototype; add one in production if needed).

### 2. Hero
- **Purpose:** announce the event, drive to RSVP / CFP.
- **Layout:** left-aligned, 72px top / 60px bottom padding, inside the 720px column.
- **Components:**
  - **Kicker** (mono 13px, `--muted`): a red "Free" pill (`--ruby` bg, white, uppercase
    11px, radius 4px) + "Sat 28 Nov 2026" · "Aarhus, Denmark".
  - **H1:** "hygge**.rb**" — Space Grotesk 700, `clamp(46px, 9vw, 88px)`, line-height
    0.98, letter-spacing −0.04em. ".rb" is `.interp` (muted) with the "rb" bold in ruby.
    (Earlier versions used a `#{:rb}` interpolation motif — intentionally removed to avoid
    being too close to the tiny ruby brand. Keep it plain "hygge.rb".)
  - **Description:** Newsreader serif 22px, `--ink-soft`, max 30em: "A **tiny, free,
    one-day** Ruby gathering in Aarhus, Denmark. A few rooms, several talks, a long
    lunch, and a relaxed DJ set. **Everyone should get to hygge**, so come hygge with us."
  - **Facts strip:** a bordered card (`--card` bg, radius 8px) split into 3 equal cells
    (stack to 1 column below 560px), each with a mono uppercase label + Space Grotesk
    500 value:
    - When — Sat 28 Nov 2026 / 10:00 – 19:00
    - Where — Åboulevarden 18, 2. / Aarhus C
    - Cost — Free · RSVP / ~40 seats
  - **Button row:** primary "RSVP — it's free →" (→ #rsvp) + ghost "Submit a talk" (→ #cfp).

### 3. About (`#about`)
- Eyebrow `# about`, H2 "What this is".
- Lead paragraph (21px `--ink-soft`) + 2 body paragraphs. Key facts embedded in copy:
  gathers on the **second floor** of an office by the river in Aarhus; **a few rooms,
  several talks** from ten to six then a DJ closes at seven; **free to attend, capped
  at ~40 people**, all levels welcome. Tagline: *"Everyone should be able to hygge."*

### 4. RSVP (`#rsvp`)
- Eyebrow `# rsvp`, H2 "Save your seat".
- **RSVP card** (`--card` bg, 1px `--rule-2`, radius 12px, 32px padding):
  - "Free" in Space Grotesk 700, 44px.
  - Sub note: what's included + "Space is capped at 40, so please only reserve if you
    plan to come."
  - **Form** (real submission, not a newsletter/notify): stacked full-width inputs —
    **Name** (required), **Email** (required, `type=email`), **Dietary needs or allergies**
    (optional) — then a primary submit button "Reserve my seat →".
  - On valid submit: JS hides the form and reveals the confirmation line "Tak! Your seat
    is reserved. See you on the 28th. ☕". In production, POST to a real RSVP endpoint /
    store the reservation; enforce the 40-seat cap server-side.
  - Foot note (mono 12px): "free · one confirmation email · release your seat if plans change".

### 5. CFP (`#cfp`)
- Eyebrow `# cfp · open now`, H2 "**Tell us your story**".
- Intro: looking for **several talks**, open call; **all talks are given in English.**
- **Criteria list** (4 items, numbered i–iv in mono ruby): A specific story · Ruby,
  somewhere in it (non-technical welcome) · A point of view · About 45 minutes.
- Button row: primary "Submit a proposal →" + ghost "Read the guidelines" (both `href="#"`
  placeholders — wire to the real CFP tool/URL).
- **Timeline** (mono, 2-col rows, key rows have ruby dates):
  - Wed 5 Aug — CFP opens.
  - Weeks 1–2 — first wave of submissions.
  - Mid Aug — quieter stretch, promoting.
  - Early Sep — "two weeks left" reminders.
  - **Sat 5 Sep — CFP closes.**
  - Sep — selection & acceptances.
  - **Sat 26 Sep — public lineup announcement.**

### 6. Schedule (`#schedule`)
- Eyebrow `# schedule · one day`, H2 "A Saturday, unhurried". Note that times are
  indicative.
- **Table** (`.sched`): mono ruby time column (78px) + event column (Newsreader) with an
  italic muted sub-line. Rows 10:00 doors → 10:30 opening → 10:45 morning talks (45 min
  each) → 12:30 long lunch → 13:30 lightning talks → 14:00 afternoon talks → 16:00 coffee
  → 16:30 closing talks → 17:45 closing remarks & dørstop drinks → **18:00 DJ set** (row
  gets `.dj`, ruby-deep 500) → **19:00 last call** ("we close at seven on the dot").

### 7. Venue (`#venue`)
- Eyebrow `# venue · aarhus`, H2 "By the river, second floor".
- **Photo:** a 300px-tall rounded, bordered `<image-slot>` prefilled with the dentsu
  Aarhus building photo (`assets/venue-dentsu-aarhus.png`). In production this is just a
  normal responsive `<img>` — the `image-slot` web component is a prototype convenience
  for drag-and-drop replacement; do not port it.
- Copy: second floor, **up the stairs**, on Åboulevarden. Meta list: Address
  "Åboulevarden 18, 2. sal · 8000 Aarhus C, Denmark" and "From the station — 8 minutes on
  foot". "Open in Maps →" link (Apple Maps query URL).

### 8. Sponsors (`#sponsors`)
- Eyebrow `# made possible by`, H2 "Our friends". Short line about keeping the list short.
- Cards (flex, wrap, `flex:1 1 200px`): **Host — Merkle**, **Headline — Dentsu**, and a
  centered "Become a sponsor →" CTA card. Sponsor names are text set in Space Grotesk 600
  22px (swap for real logos when available).

### 9. FAQ (`#faq`)
- Eyebrow `# quietly asked`, H2 "Questions". Native `<details>/<summary>` accordions
  (first one `open`). "+" toggle rotates 45° to an "×" when open.
- Questions: Is it really free? (free, RSVP, cap 40) · Will talks be recorded? (yes, on
  YouTube **about two weeks after**; no livestream) · New to Ruby? (**all levels welcome**;
  meet people over lunch/coffee) · Food & allergies? (lunch + coffee included, veg/vegan
  options, allergies asked in RSVP) · Speaker deadline? (**CFP closes 5 Sep 2026**, ~45 min,
  lineup 26 Sep) · Company sponsor? (email sponsor@hygge.rb).

### 10. Footer
- Coffee-cup glyph + "hygge**.rb**" wordmark + one-line description (Sat 28 Nov 2026).
- Two link columns (Event / More). Bottom bar (mono 12px): "© 2026 hygge.rb" and
  "**Made with Ruby on Rails**".

## Interactions & Behavior
- **In-page nav:** anchor links + `html { scroll-behavior: smooth }`.
- **Sticky header** with translucent blur.
- **RSVP form:** `submit` handler calls `preventDefault()`, validates Name (non-empty) and
  Email (`checkValidity()`); focuses the first invalid field; on success hides the form and
  shows the confirmation paragraph. **Replace with a real POST** in production.
- **FAQ:** native `<details>`; the "+" glyph rotates via
  `details[open] .faq-q .plus { transform: rotate(45deg) }`.
- **Buttons:** hover lifts primary by 1px, darkens bg to `--ruby-deep`; ghost buttons turn
  text/border ruby; the "→" arrow nudges 3px on hover (150ms).
- **Responsive:** content column has side padding; facts strip → 1 column < 560px; top nav
  hidden < 680px (add a mobile menu in production); timeline columns tighten < 480px.
- No scroll animations, parallax, or entrance effects — intentionally calm.

## State Management
- Only the RSVP form has state: `submitted` (boolean) toggling form vs. confirmation.
- Production needs: an RSVP persistence endpoint with a **40-seat cap** (return
  "full"/waitlist state), spam protection, and a confirmation email. CFP submit + sponsor
  + guidelines links currently point to `#`.

## Design Tokens
Colors (CSS custom properties as authored):
- `--paper` **#f7f1e7** (page background, warm off-white)
- `--card` **#fffdf8** (cards / inputs' resting surface)
- `--ink` **#201b16** (primary text)
- `--ink-soft` **#4a4036** (body / secondary text)
- `--muted` **#837563** (labels, meta, mono captions)
- `--rule` **#e2d6c2** (hairline dividers)
- `--rule-2` **#d3c4ab** (stronger borders: cards, inputs)
- `--ruby` **#bb1f2c** (brand accent: links, pills, buttons, ".rb")
- `--ruby-deep` **#7d1219** (hover / darker accent, glyph strokes)
- `--ruby-tint` **#f6e4dd** (available tint; light use)
- Selection: ruby bg / white text. Buttons on ruby use **#ffffff**.

Typography (Google Fonts):
- **Space Grotesk** (400/500/600/700) — headings, wordmark, UI, buttons, labels, values.
- **Newsreader** (serif; 400/500 + italic) — body prose, hero description, schedule events.
- **JetBrains Mono** (400/500) — eyebrows, kicker, dates, table times, meta captions.
- Base body: Newsreader 19px / line-height 1.6. Lead 21px. Hero desc 22px.
- H1 `clamp(46px, 9vw, 88px)`, weight 700, tracking −0.04em, line-height 0.98.
- Section H2 (`.sec`) Space Grotesk 600, 30px, tracking −0.02em.
- Eyebrow mono 12.5px, tracking 0.08em, lowercase, ruby.

Spacing / shape:
- Content column max-width **720px**; header bar **940px**; horizontal padding 24px.
- Section vertical padding **64px**; 1px top rule between sections.
- Radii: buttons/inputs **7px**, small pill 4px, cards **8–12px**, venue photo 10px.
- Borders: **1px** throughout (`--rule` default, `--rule-2` for emphasis).
- No shadows at rest; the only motion is 150ms hover transitions and a 1px button lift.
- Icon: coffee-cup mark is inline SVG (viewBox 0 0 36 32) — ruby cup, deep-ruby strokes,
  three steam wisps, a light highlight. Reproduce as an SVG component.

## Assets
- `assets/venue-dentsu-aarhus.png` — photo of the dentsu building on Åboulevarden, Aarhus
  (the venue). User-provided. Use as the venue image.
- No icon library — the only glyph is the hand-built coffee-cup SVG (in the header and
  footer). Fonts load from Google Fonts.

## Files
- `index.html` — the complete design (all sections, styles in a `<style>` block, RSVP JS
  at the bottom). **Primary reference.**
- `image-slot.js` — prototype-only web component powering the venue photo placeholder.
  Do **not** port it; use a normal `<img>` in production.
- `assets/venue-dentsu-aarhus.png` — venue photo referenced by the venue section.
