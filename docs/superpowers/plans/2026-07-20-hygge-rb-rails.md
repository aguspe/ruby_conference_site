# hygge.rb Rails Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static `index.html` with a Rails 8 app that renders the hygge.rb landing page at high fidelity, accepts real RSVPs into Postgres with a server-enforced 40-seat cap and confirmation email, and serves from `hyggerb.dk` on Render.

**Architecture:** One Rails app, one public page assembled from ERB section partials, structured page content in `config/event.yml`. Plain CSS through Propshaft in three files (tokens, base, components) ported near-verbatim from the design handoff. The RSVP form is a Turbo-frame POST to a real controller backed by an `Rsvp` model. Deployment is a Render web service plus managed Postgres.

**Tech Stack:** Ruby 3.3+, Rails 8, Postgres, Propshaft, Turbo, Minitest, Capybara + headless Chrome, Resend SMTP via ActionMailer, Render.

**Spec:** `docs/superpowers/specs/2026-07-20-hygge-rb-rails-design.md`

## Global Constraints

- **No CSS framework.** No Tailwind, no Bootstrap, no CSS build step. Plain CSS served by Propshaft.
- **No ViewComponent.** Sections are ERB partials in `app/views/pages/`.
- **Fonts are self-hosted** in `app/assets/fonts` as woff2. Never link to `fonts.googleapis.com` or `fonts.gstatic.com` — GDPR.
- **Design tokens are exact.** `--paper #f7f1e7`, `--card #fffdf8`, `--ink #201b16`, `--ink-soft #4a4036`, `--muted #837563`, `--rule #e2d6c2`, `--rule-2 #d3c4ab`, `--ruby #bb1f2c`, `--ruby-deep #7d1219`, `--ruby-tint #f6e4dd`, `--maxw 720px`. Never invent a colour; if a value is needed that is not a token, stop and ask.
- **Copy is verbatim** from `docs/design-handoff/index.html`. Do not rewrite, shorten, or "improve" marketing copy, including the Danish words (hygge, Tak, dørstop) and the `·` separators.
- **Seat capacity is 40**, defined once as `Rsvp::CAPACITY`.
- **TDD.** Every task with logic writes the failing test first and runs it to watch it fail before implementing.
- **Commit at the end of every task.** Never bundle two tasks into one commit.
- **No scroll animations, parallax, or entrance effects.** The only motion is the 150ms hover transitions already in the handoff CSS.

---

### Task 1: Vendor the design handoff into the repo

The handoff currently lives in `~/Downloads`, outside the repo. Every later task reads from it, so it has to be in-tree and committed first.

**Files:**
- Create: `docs/design-handoff/index.html` (copied)
- Create: `docs/design-handoff/README.md` (copied)
- Create: `app/assets/images/venue-dentsu-aarhus.png` (copied — this is a real asset, not reference)

- [ ] **Step 1: Copy the handoff in**

```bash
cd /Users/augustingottlieb/ruby_dk_conference
mkdir -p docs/design-handoff app/assets/images
cp ~/Downloads/design_handoff_hygge_rb/index.html docs/design-handoff/index.html
cp ~/Downloads/design_handoff_hygge_rb/README.md docs/design-handoff/README.md
cp ~/Downloads/design_handoff_hygge_rb/assets/venue-dentsu-aarhus.png app/assets/images/venue-dentsu-aarhus.png
```

`image-slot.js` is deliberately NOT copied. The handoff README says not to port it.

- [ ] **Step 2: Verify the files arrived**

Run: `ls -l docs/design-handoff/ app/assets/images/`
Expected: `index.html` (~24KB), `README.md` (~11KB), `venue-dentsu-aarhus.png` (non-zero).

- [ ] **Step 3: Commit**

```bash
git add docs/design-handoff app/assets/images
git commit -m "Vendor design handoff reference and venue photo"
```

---

### Task 2: Rails app skeleton with Postgres

The repo currently holds only `index.html`, `render.yaml`, and `docs/`. Rails needs to be generated into it without destroying those.

**Files:**
- Create: the full Rails 8 skeleton at the repo root
- Modify: `.gitignore` (Rails generates it; ensure `/config/master.key` is ignored)

**Interfaces:**
- Produces: a bootable Rails app, `bin/rails`, `config/database.yml` pointing at Postgres, a passing `bin/rails test` run.

- [ ] **Step 1: Generate Rails into the existing directory**

`rails new .` refuses to clobber a non-empty directory unless forced, and it must not overwrite the handoff docs. Generate into a temp dir and move the skeleton in.

```bash
cd /Users/augustingottlieb/ruby_dk_conference
gem install rails --no-document
rails new /tmp/hyggerb_skeleton --database=postgresql --skip-jbuilder --skip-action-mailbox --skip-action-text --skip-active-storage --skip-kamal --skip-solid
rsync -av --exclude='.git' /tmp/hyggerb_skeleton/ ./
rm -rf /tmp/hyggerb_skeleton
```

Note: `--skip-solid` skips Solid Cache/Queue/Cable, which expect extra databases. Async ActiveJob is fine for two emails a day. Propshaft is the Rails 8 default asset pipeline — do not add Sprockets.

- [ ] **Step 2: Create the local databases and boot**

```bash
bin/rails db:create
bin/rails runner 'puts Rails.version'
```

Expected: prints `8.x.x` with no error. If `db:create` fails, Postgres is not running locally — start it (`brew services start postgresql@16`) and retry.

- [ ] **Step 3: Run the empty test suite**

Run: `bin/rails test`
Expected: `0 runs, 0 assertions, 0 failures, 0 errors`.

- [ ] **Step 4: Confirm master.key is ignored**

Run: `git check-ignore -v config/master.key`
Expected: a line naming `.gitignore`. If it prints nothing, add `/config/master.key` to `.gitignore` — committing it leaks production credentials.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Generate Rails 8 skeleton with Postgres"
```

---

### Task 3: Self-hosted fonts and design tokens

**Files:**
- Create: `app/assets/fonts/` (woff2 files)
- Create: `app/assets/stylesheets/tokens.css`
- Create: `app/assets/stylesheets/base.css`
- Modify: `app/views/layouts/application.html.erb`
- Delete: `app/assets/stylesheets/application.css` (replaced by explicit includes)

**Interfaces:**
- Produces: CSS custom properties on `:root` and the `.sans` / `.mono` helper classes, consumed by every later view task. Font families are referenced as `"Space Grotesk"`, `"Newsreader"`, `"JetBrains Mono"`.

- [ ] **Step 1: Download the woff2 files**

Fetch the three families with a modern-browser User-Agent so Google returns woff2 rather than ttf, then pull the font binaries out of the returned CSS.

```bash
cd /Users/augustingottlieb/ruby_dk_conference
mkdir -p app/assets/fonts tmp/fontfetch
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
URL='https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;1,6..72,400&family=JetBrains+Mono:wght@400;500&display=swap'
curl -sH "User-Agent: $UA" "$URL" -o tmp/fontfetch/google.css
grep -oE 'https://fonts.gstatic.com/[^)]+\.woff2' tmp/fontfetch/google.css | sort -u > tmp/fontfetch/urls.txt
wc -l tmp/fontfetch/urls.txt
```

The URL list will contain many per-subset files. Only latin and latin-ext are needed — the copy uses Danish characters (å, ø, æ) which live in latin-ext.

- [ ] **Step 2: Download only latin + latin-ext and name them predictably**

Google's CSS groups each `@font-face` under a `/* latin */` or `/* latin-ext */` comment. Rather than parsing that, download every URL and keep the ones the CSS marks latin/latin-ext:

```bash
cd /Users/augustingottlieb/ruby_dk_conference
ruby -e '
css = File.read("tmp/fontfetch/google.css")
blocks = css.split(/(?=\/\* )/)
blocks.each do |b|
  next unless b =~ /\/\* (latin|latin-ext) \*\//
  subset = $1
  family = b[/font-family: .(.+?)./, 1] or next
  weight = b[/font-weight: (\d+)/, 1]
  style  = b[/font-style: (\w+)/, 1]
  url    = b[/(https:\/\/fonts\.gstatic\.com\/\S+?\.woff2)/, 1] or next
  name = [family.downcase.gsub(" ", "-"), weight, style, subset].join("-") + ".woff2"
  system("curl", "-sL", url, "-o", "app/assets/fonts/#{name}")
  puts name
end
'
ls app/assets/fonts | wc -l
```

Expected: roughly 14-20 files (4 Space Grotesk weights + 3 Newsreader faces + 2 JetBrains Mono weights, each in 2 subsets). Exact count varies with what Google serves; anything in that range is fine.

- [ ] **Step 3: Write the `@font-face` declarations**

Create `app/assets/stylesheets/fonts.css`. Use `font-display: swap` so text renders immediately in the fallback. Propshaft's `font-path` is not available in plain CSS, so reference the digest-free logical path — Propshaft rewrites `url()` references in CSS at precompile.

```css
/* Space Grotesk — headings, wordmark, UI, buttons, labels */
@font-face {
  font-family: "Space Grotesk";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("space-grotesk-400-normal-latin-ext.woff2") format("woff2"),
       url("space-grotesk-400-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "Space Grotesk";
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url("space-grotesk-500-normal-latin-ext.woff2") format("woff2"),
       url("space-grotesk-500-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "Space Grotesk";
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url("space-grotesk-600-normal-latin-ext.woff2") format("woff2"),
       url("space-grotesk-600-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "Space Grotesk";
  font-style: normal;
  font-weight: 700;
  font-display: swap;
  src: url("space-grotesk-700-normal-latin-ext.woff2") format("woff2"),
       url("space-grotesk-700-normal-latin.woff2") format("woff2");
}

/* Newsreader — body prose, hero description, schedule events */
@font-face {
  font-family: "Newsreader";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("newsreader-400-normal-latin-ext.woff2") format("woff2"),
       url("newsreader-400-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "Newsreader";
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url("newsreader-500-normal-latin-ext.woff2") format("woff2"),
       url("newsreader-500-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "Newsreader";
  font-style: italic;
  font-weight: 400;
  font-display: swap;
  src: url("newsreader-400-italic-latin-ext.woff2") format("woff2"),
       url("newsreader-400-italic-latin.woff2") format("woff2");
}

/* JetBrains Mono — eyebrows, kickers, dates, table times, meta */
@font-face {
  font-family: "JetBrains Mono";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("jetbrains-mono-400-normal-latin-ext.woff2") format("woff2"),
       url("jetbrains-mono-400-normal-latin.woff2") format("woff2");
}
@font-face {
  font-family: "JetBrains Mono";
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url("jetbrains-mono-500-normal-latin-ext.woff2") format("woff2"),
       url("jetbrains-mono-500-normal-latin.woff2") format("woff2");
}
```

If Step 2 produced filenames that differ from these, rename the files to match rather than editing this CSS — consistent naming is worth more than matching Google's hashes.

- [ ] **Step 4: Write `tokens.css`**

Copied verbatim from `docs/design-handoff/index.html` lines 28-40.

```css
:root {
  --paper:    #f7f1e7;
  --card:     #fffdf8;
  --ink:      #201b16;
  --ink-soft: #4a4036;
  --muted:    #837563;
  --rule:     #e2d6c2;
  --rule-2:   #d3c4ab;
  --ruby:     #bb1f2c;
  --ruby-deep:#7d1219;
  --ruby-tint:#f6e4dd;
  --maxw: 720px;
}
```

- [ ] **Step 5: Write `base.css`**

Reset, typography, links, layout column, generic section rules, selection. Ported from handoff lines 41-92 and 217.

```css
* { box-sizing: border-box; }

html { scroll-behavior: smooth; }

body {
  margin: 0;
  background: var(--paper);
  color: var(--ink);
  font-family: "Newsreader", Georgia, serif;
  font-size: 19px;
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

.sans { font-family: "Space Grotesk", system-ui, sans-serif; }
.mono { font-family: "JetBrains Mono", ui-monospace, monospace; }

a {
  color: var(--ruby);
  text-underline-offset: 3px;
  text-decoration-thickness: 1px;
}
a:hover { color: var(--ruby-deep); }

.wrap { max-width: var(--maxw); margin: 0 auto; padding: 0 24px; }

section { padding: 64px 0; border-top: 1px solid var(--rule); }
section:first-of-type { border-top: none; }

.eyebrow {
  font-family: "JetBrains Mono", monospace;
  font-size: 12.5px;
  letter-spacing: 0.08em;
  color: var(--ruby);
  text-transform: lowercase;
  margin: 0 0 18px;
}

h2.sec {
  font-family: "Space Grotesk", sans-serif;
  font-weight: 600;
  font-size: 30px;
  letter-spacing: -0.02em;
  line-height: 1.1;
  margin: 0 0 20px;
  color: var(--ink);
}

p { margin: 0 0 18px; }
p:last-child { margin-bottom: 0; }

.lead { font-size: 21px; color: var(--ink-soft); }
strong { font-weight: 600; color: var(--ink); }
em.i { font-style: italic; }

::selection { background: var(--ruby); color: #fff; }

/* Screen-reader-only, used by the honeypot field and skip link */
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  * { transition: none !important; }
}
```

The `prefers-reduced-motion` block and `.visually-hidden` are additions, not in the handoff. The former is an accessibility baseline; the latter is needed by the honeypot in Task 8.

- [ ] **Step 6: Wire the stylesheets into the layout**

Rails 8 generates `app/assets/stylesheets/application.css`. Delete it and link the three files explicitly so load order is visible and guaranteed: tokens, then fonts, then base, then components.

```bash
rm app/assets/stylesheets/application.css
```

In `app/views/layouts/application.html.erb`, replace the existing `stylesheet_link_tag` line with:

```erb
<%= stylesheet_link_tag "tokens", "fonts", "base", "components", data: { turbo_track: "reload" } %>
```

`components.css` does not exist yet — create it empty now so the layout does not raise:

```bash
touch app/assets/stylesheets/components.css
```

- [ ] **Step 7: Boot and verify the tokens load**

```bash
bin/rails server -p 3000 &
sleep 4
curl -s http://localhost:3000/assets/tokens.css | head -3
kill %1
```

Expected: the `:root {` line and `--paper: #f7f1e7;`. A 404 means Propshaft is not seeing the file — check it is under `app/assets/stylesheets/`.

- [ ] **Step 8: Commit**

```bash
git add app/assets app/views/layouts/application.html.erb
git commit -m "Add self-hosted fonts, design tokens, and base stylesheet"
```

---

### Task 4: Component stylesheet

All remaining CSS in one file, ported from the handoff. No logic, no tests — verification is visual, in the next task.

**Files:**
- Modify: `app/assets/stylesheets/components.css`

**Interfaces:**
- Produces: the class names every view partial uses — `.site-inner`, `.brand`, `nav.top`, `.hero`, `.kicker`, `.facts`, `.fact`, `.btn`, `.btn-primary`, `.btn-ghost`, `.btn-row`, `.arr`, `.rsvp-card`, `.rsvp-price`, `.rsvp-sub`, `.rsvp-form`, `.rsvp-note`, `.rsvp-ok`, `.sched`, `.cfp-crit`, `.timeline`, `.venue-photo`, `.venue-meta`, `.spons`, `.spon`, `.faq-item`, `.faq-q`, `.faq-a`, `.plus`, `footer.site`, `.foot-top`, `.foot-brand`, `.foot-links`, `.foot-bottom`.

- [ ] **Step 1: Port the component rules**

Copy handoff lines 57-72 (header), 93-118 (hero + facts), 120-133 (buttons), 135-153 (rsvp), 155-163 (schedule), 165-176 (cfp), 178-184 (venue), 186-192 (sponsors), 194-202 (faq), 204-215 (footer) into `app/assets/stylesheets/components.css`, in that order, keeping the section comments.

Three deliberate changes from the handoff, and only these three:

1. `.rsvp-ok` loses `display: none`. In the handoff, JS toggled it. In Rails, the confirmation is a separate partial that is only rendered when it should be visible, so it must not be hidden by default:

```css
.rsvp-ok {
  font-family: "Space Grotesk", sans-serif;
  font-size: 15.5px;
  color: var(--ruby-deep);
  margin-top: 14px;
  font-weight: 500;
}
```

2. `.venue-photo` gets an `img` rule, since the `image-slot` web component is not ported:

```css
.venue-photo {
  width: 100%;
  height: 300px;
  border-radius: 10px;
  overflow: hidden;
  border: 1px solid var(--rule-2);
  margin-bottom: 24px;
}
.venue-photo img { width: 100%; height: 100%; object-fit: cover; display: block; }
```

3. Two new rules for form validation errors, which the handoff has no design for. They reuse existing tokens only:

```css
.field-error {
  font-family: "JetBrains Mono", monospace;
  font-size: 12px;
  color: var(--ruby-deep);
  margin: -4px 0 2px;
}
.rsvp-form input[aria-invalid="true"] { border-color: var(--ruby); }
```

- [ ] **Step 2: Verify no token was invented**

Every colour in the file must be a `var(--…)`, `#fff`, or the `#d44653` highlight used inside the coffee-cup SVG (which lives in markup, not CSS).

Run: `grep -nE '#[0-9a-fA-F]{3,6}' app/assets/stylesheets/components.css`
Expected: only `#fff` occurrences (in `.btn-primary`, `.btn-primary:hover`). Any other hex is a bug — replace it with the matching token.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/components.css
git commit -m "Port component styles from design handoff"
```

---

### Task 5: Layout, header, footer, and the coffee-cup glyph

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/views/shared/_coffee_cup.html.erb`
- Create: `app/views/pages/_header.html.erb`
- Create: `app/views/pages/_footer.html.erb`
- Create: `app/controllers/pages_controller.rb`
- Create: `app/views/pages/home.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/pages_controller_test.rb`

**Interfaces:**
- Consumes: CSS classes from Task 4.
- Produces: `root "pages#home"`, the `shared/coffee_cup` partial taking a `width:` and `height:` local, and `pages/home.html.erb` as the render point for every section partial in Tasks 6 and 7.

- [ ] **Step 1: Write the failing request test**

`test/controllers/pages_controller_test.rb`:

```ruby
require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_path
    assert_response :success
  end

  test "shows the wordmark in the header" do
    get root_path
    assert_select "header.site .brand", text: /hygge\.rb/
  end

  test "shows the Rails credit in the footer" do
    get root_path
    assert_select "footer.site .foot-bottom", text: /Made with Ruby on Rails/
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: FAIL — `undefined local variable or method 'root_path'`, because no route exists yet.

- [ ] **Step 3: Add the route and controller**

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "pages#home"
end
```

`app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  def home
  end
end
```

- [ ] **Step 4: Write the coffee-cup partial**

`app/views/shared/_coffee_cup.html.erb`. The SVG is copied from handoff lines 225-233. It is decorative, so it is `aria-hidden`. Sizes are passed in because the header uses 24×22 and the footer 30×27.

```erb
<svg class="glyph" width="<%= width %>" height="<%= height %>" viewBox="0 0 36 32" fill="none" aria-hidden="true">
  <path d="M14 4 C13 6 15 7 14 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.55"/>
  <path d="M19 3 C18 5 20 6 19 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.7"/>
  <path d="M24 4 C23 6 25 7 24 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.55"/>
  <path d="M8 12 L28 12 L26 26 Q26 29 23 29 L13 29 Q10 29 10 26 Z" fill="#bb1f2c" stroke="#7d1219" stroke-width="1.2" stroke-linejoin="round"/>
  <ellipse cx="18" cy="12" rx="10" ry="1.6" fill="#7d1219"/>
  <path d="M27 16 Q32 17 32 21 Q32 25 27 24" stroke="#7d1219" stroke-width="1.6" fill="none" stroke-linecap="round"/>
  <path d="M11 14 L12 24" stroke="#d44653" stroke-width="1" stroke-linecap="round" opacity="0.55"/>
</svg>
```

- [ ] **Step 5: Write the header partial**

`app/views/pages/_header.html.erb`, from handoff lines 222-244:

```erb
<header class="site">
  <div class="site-inner">
    <a href="#top" class="brand">
      <%= render "shared/coffee_cup", width: 24, height: 22 %>
      <span>hygge<span class="rb">.rb</span></span>
    </a>
    <nav class="top">
      <a href="#about">About</a>
      <a href="#rsvp">RSVP</a>
      <a href="#cfp">CFP</a>
      <a href="#schedule">Schedule</a>
      <a href="#venue">Venue</a>
    </nav>
  </div>
</header>
```

- [ ] **Step 6: Write the footer partial**

`app/views/pages/_footer.html.erb`, from handoff lines 417-458. The footer glyph in the handoff omits the highlight stroke; using the shared partial adds it back at 30×27, which is an improvement in consistency and invisible at that size.

```erb
<footer class="site">
  <div class="wrap">
    <div class="foot-top">
      <div class="foot-brand">
        <%= render "shared/coffee_cup", width: 30, height: 27 %>
        <div class="name">hygge<span class="rb">.rb</span></div>
        <p>A tiny, free, one-day Ruby gathering in Aarhus, Denmark. Saturday 28 November 2026.</p>
      </div>
      <div class="foot-links">
        <div>
          <h5>Event</h5>
          <ul>
            <li><a href="#about">About</a></li>
            <li><a href="#rsvp">RSVP</a></li>
            <li><a href="#cfp">CFP</a></li>
            <li><a href="#schedule">Schedule</a></li>
          </ul>
        </div>
        <div>
          <h5>More</h5>
          <ul>
            <li><a href="#venue">Venue</a></li>
            <li><a href="<%= EVENT.dig("links", "code_of_conduct") %>">Code of conduct</a></li>
            <li><a href="mailto:<%= EVENT.dig("contact", "hello") %>"><%= EVENT.dig("contact", "hello") %></a></li>
            <li><a href="<%= EVENT.dig("links", "social") %>">@hyggerb</a></li>
          </ul>
        </div>
      </div>
    </div>
    <div class="foot-bottom">
      <span>© 2026 hygge.rb</span>
      <span>Made with Ruby on Rails</span>
    </div>
  </div>
</footer>
```

`EVENT` is defined in Task 6. To keep this task independently green, hardcode those four values now and swap them to `EVENT` lookups in Task 6:

```erb
<li><a href="#">Code of conduct</a></li>
<li><a href="mailto:hello@hyggerb.dk">hello@hyggerb.dk</a></li>
<li><a href="#">@hyggerb</a></li>
```

- [ ] **Step 7: Write the layout and page shell**

`app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>hygge.rb, a tiny free Ruby day in Aarhus, November 2026</title>
    <meta name="description" content="A tiny, free, one-day Ruby gathering in Aarhus, Denmark. Saturday 28 November 2026. RSVP required.">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="theme-color" content="#f7f1e7">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "tokens", "fonts", "base", "components", data: { turbo_track: "reload" } %>
    <%= javascript_importmap_tags %>
  </head>
  <body>
    <%= render "pages/header" %>
    <%= yield %>
    <%= render "pages/footer" %>
  </body>
</html>
```

`app/views/pages/home.html.erb`:

```erb
<main id="top">
</main>
```

- [ ] **Step 8: Run the tests**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: `3 runs, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 9: Commit**

```bash
git add app config test
git commit -m "Add layout, header, footer, and coffee-cup glyph"
```

---

### Task 6: Event content file and the hero, about, sponsors sections

**Files:**
- Create: `config/event.yml`
- Create: `config/initializers/event.rb`
- Create: `app/views/pages/_hero.html.erb`
- Create: `app/views/pages/_about.html.erb`
- Create: `app/views/pages/_sponsors.html.erb`
- Modify: `app/views/pages/home.html.erb`
- Modify: `app/views/pages/_footer.html.erb` (swap hardcoded links for `EVENT`)
- Create: `test/controllers/event_content_test.rb`

**Interfaces:**
- Produces: the `EVENT` constant, a frozen `Hash` with string keys, loaded once at boot. Consumed by Tasks 7, 9, and 10. Keys used: `EVENT["facts"]` (array of `{"label","lines"}`), `EVENT["sponsors"]` (array of `{"tier","name"}`), `EVENT["schedule"]` (array of `{"time","event","sub","dj"}`), `EVENT["cfp_timeline"]` (array of `{"date","text","key"}`), `EVENT["faq"]` (array of `{"q","a"}`), `EVENT["links"]`, `EVENT["contact"]`, `EVENT["capacity"]`.

- [ ] **Step 1: Write the failing test**

`test/controllers/event_content_test.rb`:

```ruby
require "test_helper"

class EventContentTest < ActionDispatch::IntegrationTest
  test "EVENT is loaded and frozen" do
    assert EVENT.frozen?
    assert_equal 40, EVENT["capacity"]
  end

  test "hero shows the three facts" do
    get root_path
    assert_select ".facts .fact", count: 3
    assert_select ".fact dt", text: "When"
    assert_select ".hero .kicker .free", text: "Free"
  end

  test "hero headline is the plain wordmark" do
    get root_path
    assert_select ".hero h1", text: "hygge.rb"
  end

  test "sponsors lists Merkle and Dentsu plus a CTA" do
    get root_path
    assert_select ".spon .name", text: "Merkle"
    assert_select ".spon .name", text: "Dentsu"
    assert_select ".spon.cta a", text: /Become a sponsor/
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/event_content_test.rb`
Expected: FAIL — `NameError: uninitialized constant EVENT`.

- [ ] **Step 3: Write `config/event.yml`**

All copy verbatim from the handoff.

```yaml
capacity: 40

facts:
  - label: "When"
    lines: ["Sat 28 Nov 2026", "10:00 – 19:00"]
  - label: "Where"
    lines: ["Åboulevarden 18, 2.", "Aarhus C"]
  - label: "Cost"
    lines: ["Free · RSVP", "~40 seats"]

sponsors:
  - tier: "Host"
    name: "Merkle"
  - tier: "Headline"
    name: "Dentsu"

schedule:
  - time: "10:00"
    event: "Doors & filter coffee"
    sub: "Åboulevarden 18, 2nd floor"
  - time: "10:30"
    event: "Opening remarks"
  - time: "10:45"
    event: "Three talks · morning block"
    sub: "45 minutes each, with breaks"
  - time: "12:30"
    event: "Long lunch"
    sub: "one hour, unrushed"
  - time: "13:30"
    event: "Lightning talks"
    sub: "5 minutes each, sign up at lunch"
  - time: "14:00"
    event: "Three talks · afternoon"
  - time: "16:00"
    event: "Coffee break"
  - time: "16:30"
    event: "Two talks · closing block"
  - time: "17:45"
    event: "Closing remarks & dørstop drinks"
  - time: "18:00"
    event: "DJ set, dancing, talking, both"
    sub: "main room, lights down, no rush"
    dj: true
  - time: "19:00"
    event: "Last call"
    sub: "we close at seven on the dot"

cfp_criteria:
  - numeral: "i."
    title: "A specific story."
    body: "Not a survey, not a tour. The bug you chased for nine months. The library you wish existed."
  - numeral: "ii."
    title: "Ruby, somewhere in it."
    body: "The talk needn't be <em class=\"i\">about</em> Ruby, but Ruby should be in the room. Non-technical talks welcome too."
  - numeral: "iii."
    title: "A point of view."
    body: "An opinion, an argument, a thing you've changed your mind about. Take a stance."
  - numeral: "iv."
    title: "About 45 minutes."
    body: "Long enough to be honest, questions and a graceful exit included."

cfp_timeline:
  - date: "Wed 5 Aug"
    text: "CFP opens."
    key: true
  - date: "Weeks 1–2"
    text: "First wave of submissions, the eager beavers."
  - date: "Mid Aug"
    text: "A quieter stretch; we're out promoting."
  - date: "Early Sep"
    text: "“Two weeks left” reminders; submissions accelerate."
  - date: "Sat 5 Sep"
    text: "CFP closes. The last week is, predictably, the busiest."
    key: true
  - date: "Sep"
    text: "Selection committee reviews; acceptances confirmed."
  - date: "Sat 26 Sep"
    text: "Public lineup announcement."
    key: true

faq:
  - q: "Is it really free?"
    a: "Yes, free to attend, thanks to our sponsors. You just need to RSVP, because space is capped at around 40. If you register and can't make it, please release your seat so someone else can take it."
  - q: "Will talks be recorded?"
    a: "Yes, every talk is recorded and published for free on YouTube about two weeks after. There's no livestream, though, the room is for the people in the room."
  - q: "I'm new to Ruby. Should I come?"
    a: "All levels are welcome. Talks aim for substance over jargon, and there's plenty of time to meet people over lunch and coffee."
  - q: "What about food and allergies?"
    a: "Lunch and coffee are included. Every meal has a clearly-labelled vegetarian and vegan option, and we ask about allergies in the RSVP form so the kitchen can accommodate them individually."
  - q: "I'd like to speak, what's the deadline?"
    a: "The CFP closes 5 September 2026 at 23:59 CET. Talks are around 45 minutes including questions. We accept several, and the public lineup is announced 26 September. <a href=\"#cfp\">Submit a proposal.</a>"
  - q: "Can my company sponsor?"
    a: "We'd love that, sponsors are what keep the day free. Email <a href=\"mailto:sponsor@hyggerb.dk\">sponsor@hyggerb.dk</a> for the prospectus."

venue:
  address: "Åboulevarden 18, 2. sal · 8000 Aarhus C, Denmark"
  from_station: "8 minutes on foot"
  maps_url: "https://maps.apple.com/?address=Åboulevarden%2018,%208000%20Aarhus,%20Denmark&q=hygge.rb"

contact:
  hello: "hello@hyggerb.dk"
  sponsor: "sponsor@hyggerb.dk"

links:
  cfp_submit: "#"
  cfp_guidelines: "#"
  become_sponsor: "#"
  code_of_conduct: "#"
  social: "#"
```

The FAQ and CFP bodies contain HTML. That is why they are rendered with `raw` in the views — the file is repo-controlled content, never user input, so this is safe. It must never be used for anything a visitor supplies.

- [ ] **Step 4: Write the initializer**

`config/initializers/event.rb`. Rails has no `deep_freeze`, so freeze recursively by hand — a top-level `.freeze` would leave the nested hashes and arrays mutable.

```ruby
# Structured landing-page content. Repo-controlled and trusted: a few values
# contain HTML and are rendered with `raw`. Never put user-supplied data here.
module EventContent
  def self.deep_freeze(obj)
    case obj
    when Hash  then obj.each_value { |v| deep_freeze(v) }.freeze
    when Array then obj.each { |v| deep_freeze(v) }.freeze
    else obj.freeze
    end
  end
end

EVENT = EventContent.deep_freeze(
  YAML.load_file(Rails.root.join("config/event.yml"), aliases: true)
)
```

- [ ] **Step 5: Write the hero partial**

`app/views/pages/_hero.html.erb`, from handoff lines 248-268. Note the `h1` is plain "hygge.rb" — the handoff README states the `#{:rb}` interpolation motif was deliberately removed.

```erb
<section class="hero" id="hero">
  <div class="wrap">
    <div class="kicker">
      <span class="free">Free</span>
      <span>Sat 28 Nov 2026</span>
      <span>·</span>
      <span>Aarhus, Denmark</span>
    </div>
    <h1>hygge<span class="interp">.<b>rb</b></span></h1>
    <p class="desc">A <b>tiny, free, one-day</b> Ruby gathering in Aarhus, Denmark. A few rooms, several talks, a long lunch, and a relaxed DJ set. <b>Everyone should get to hygge</b>, so come hygge with us.</p>
    <div class="facts">
      <% EVENT["facts"].each do |fact| %>
        <div class="fact">
          <dt><%= fact["label"] %></dt>
          <dd><%= safe_join(fact["lines"], tag.br) %></dd>
        </div>
      <% end %>
    </div>
    <div class="btn-row">
      <a href="#rsvp" class="btn btn-primary">RSVP, it's free <span class="arr">→</span></a>
      <a href="#cfp" class="btn btn-ghost">Submit a talk</a>
    </div>
  </div>
</section>
```

The handoff put `style="border-top:none"` inline on the hero. `section:first-of-type` in `base.css` already handles it — do not carry the inline style over.

- [ ] **Step 6: Write the about partial**

`app/views/pages/_about.html.erb`, from handoff lines 271-279:

```erb
<section id="about">
  <div class="wrap">
    <p class="eyebrow"># about</p>
    <h2 class="sec">What this is</h2>
    <p class="lead">For one Saturday in November, the Ruby community gathers on the second floor of an office by the river in Aarhus, for a day shaped less like a conference and more like a long lunch with friends.</p>
    <p>A few rooms, several talks from ten until six, then the lights go low and a DJ closes the day at seven. No rush to the next session, no FOMO, just the kind of conversations that only happen when everyone's in the same building for the day.</p>
    <p>It's <strong>free to attend</strong>, capped at around 40 people, and open to anyone who writes Ruby, or wants to. <em class="i">Everyone should be able to hygge.</em></p>
  </div>
</section>
```

- [ ] **Step 7: Write the sponsors partial**

`app/views/pages/_sponsors.html.erb`, from handoff lines 371-382:

```erb
<section id="sponsors">
  <div class="wrap">
    <p class="eyebrow"># made possible by</p>
    <h2 class="sec">Our friends</h2>
    <p>hygge.rb is free because a few good companies pick up the tab. We keep the list short and the booths nonexistent, just a thank-you and a logo.</p>
    <div class="spons">
      <% EVENT["sponsors"].each do |sponsor| %>
        <div class="spon">
          <div class="tier"><%= sponsor["tier"] %></div>
          <div class="name"><%= sponsor["name"] %></div>
        </div>
      <% end %>
      <div class="spon cta">
        <a href="<%= EVENT.dig("links", "become_sponsor") %>">Become a sponsor →</a>
      </div>
    </div>
  </div>
</section>
```

- [ ] **Step 8: Render them and update the footer**

`app/views/pages/home.html.erb`:

```erb
<main id="top">
  <%= render "pages/hero" %>
  <%= render "pages/about" %>
  <%= render "pages/sponsors" %>
</main>
```

In `app/views/pages/_footer.html.erb`, replace the three hardcoded links from Task 5 with the `EVENT` lookups shown there.

- [ ] **Step 9: Run the tests**

Run: `bin/rails test`
Expected: `7 runs, 0 failures, 0 errors`.

- [ ] **Step 10: Commit**

```bash
git add app config test
git commit -m "Add event content file with hero, about, and sponsors sections"
```

---

### Task 7: CFP, schedule, venue, and FAQ sections

**Files:**
- Create: `app/views/pages/_cfp.html.erb`
- Create: `app/views/pages/_schedule.html.erb`
- Create: `app/views/pages/_venue.html.erb`
- Create: `app/views/pages/_faq.html.erb`
- Modify: `app/views/pages/home.html.erb`
- Create: `test/controllers/sections_test.rb`

**Interfaces:**
- Consumes: `EVENT["cfp_criteria"]`, `EVENT["cfp_timeline"]`, `EVENT["schedule"]`, `EVENT["faq"]`, `EVENT["venue"]`, `EVENT["links"]` from Task 6.

- [ ] **Step 1: Write the failing test**

`test/controllers/sections_test.rb`:

```ruby
require "test_helper"

class SectionsTest < ActionDispatch::IntegrationTest
  setup { get root_path }

  test "cfp lists four criteria and the timeline" do
    assert_select ".cfp-crit li", count: 4
    assert_select ".timeline div", count: EVENT["cfp_timeline"].size
    assert_select ".timeline .key", count: 3
  end

  test "schedule lists every row and marks the DJ set" do
    assert_select ".sched tr", count: EVENT["schedule"].size
    assert_select ".sched tr.dj .ev", text: /DJ set/
    assert_select ".sched tr .t", text: "10:00"
  end

  test "venue shows the photo and the address" do
    assert_select ".venue-photo img[alt=?]", /Åboulevarden/
    assert_select ".venue-meta dd", text: /8000 Aarhus C/
  end

  test "faq renders every question with the first one open" do
    assert_select "details.faq-item", count: EVENT["faq"].size
    assert_select "details.faq-item[open]", count: 1
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/sections_test.rb`
Expected: FAIL — 4 failures, each an expected-element-count mismatch against 0.

- [ ] **Step 3: Write the CFP partial**

`app/views/pages/_cfp.html.erb`, from handoff lines 304-329:

```erb
<section id="cfp">
  <div class="wrap">
    <p class="eyebrow"># cfp · open now</p>
    <h2 class="sec">Tell us your story</h2>
    <p>We're looking for <strong>several talks</strong>, all chosen through an open call. We want talks from people who have built something, broken something, or fixed something, and want to bring the rest of us along for the story. All talks are given in English.</p>
    <ul class="cfp-crit">
      <% EVENT["cfp_criteria"].each do |crit| %>
        <li>
          <span class="n"><%= crit["numeral"] %></span>
          <span><b><%= crit["title"] %></b> <%= raw crit["body"] %></span>
        </li>
      <% end %>
    </ul>
    <div class="btn-row cfp-actions">
      <a href="<%= EVENT.dig("links", "cfp_submit") %>" class="btn btn-primary">Submit a proposal <span class="arr">→</span></a>
      <a href="<%= EVENT.dig("links", "cfp_guidelines") %>" class="btn btn-ghost">Read the guidelines</a>
    </div>
    <div class="timeline">
      <% EVENT["cfp_timeline"].each do |row| %>
        <div class="<%= "key" if row["key"] %>">
          <span class="d"><%= row["date"] %></span>
          <span><%= row["text"] %></span>
        </div>
      <% end %>
    </div>
  </div>
</section>
```

The handoff used `style="margin:26px 0 8px"` on that button row. Replace the inline style with a class — add to `components.css`:

```css
.cfp-actions { margin: 26px 0 8px; }
```

- [ ] **Step 4: Write the schedule partial**

`app/views/pages/_schedule.html.erb`, from handoff lines 332-351. The handoff table has no `<tbody>`; browsers insert one, and `assert_select` works either way. Include it explicitly for valid markup.

```erb
<section id="schedule">
  <div class="wrap">
    <p class="eyebrow"># schedule · one day</p>
    <h2 class="sec">A Saturday, unhurried</h2>
    <p class="sched-note">Times are indicative, the final programme lands in September once the talks are confirmed.</p>
    <table class="sched">
      <tbody>
        <% EVENT["schedule"].each do |slot| %>
          <tr class="<%= "dj" if slot["dj"] %>">
            <td class="t"><%= slot["time"] %></td>
            <td class="ev">
              <%= slot["event"] %>
              <% if slot["sub"] %><span class="s"><%= slot["sub"] %></span><% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</section>
```

Replace the handoff's inline `style="margin-bottom:28px"` with a class in `components.css`:

```css
.sched-note { margin-bottom: 28px; }
```

- [ ] **Step 5: Write the venue partial**

`app/views/pages/_venue.html.erb`, from handoff lines 354-368. The `image-slot` component becomes a plain `img` per the handoff README. It gets a real `alt` because it carries information (what the building looks like), and `loading="lazy"` because it is far below the fold.

```erb
<section id="venue">
  <div class="wrap">
    <p class="eyebrow"># venue · aarhus</p>
    <h2 class="sec">By the river, second floor</h2>
    <div class="venue-photo">
      <%= image_tag "venue-dentsu-aarhus.png",
            alt: "The office building on Åboulevarden in Aarhus that hosts hygge.rb",
            loading: "lazy" %>
    </div>
    <p>We're on the <strong>second floor</strong>, up the stairs, of an office right on Åboulevarden, the café-lined street that runs along the old river in the heart of Aarhus. Everything is a short walk away: the cathedral, ARoS, the Latin Quarter, the harbour. The city is small enough that you won't need more than good shoes.</p>
    <dl class="venue-meta">
      <div>
        <dt>Address</dt>
        <dd><%= EVENT.dig("venue", "address") %></dd>
      </div>
      <div>
        <dt>From the station</dt>
        <dd><%= EVENT.dig("venue", "from_station") %></dd>
      </div>
    </dl>
    <p class="venue-maps">
      <a href="<%= EVENT.dig("venue", "maps_url") %>" target="_blank" rel="noopener">Open in Maps →</a>
    </p>
  </div>
</section>
```

Replace the two handoff inline styles with classes in `components.css`:

```css
.venue-meta { margin-top: 22px; }
.venue-maps { margin-top: 20px; }
```

`.venue-meta` already has a `font-family` rule from Task 4 — add `margin-top` to that existing block rather than declaring the selector twice.

- [ ] **Step 6: Write the FAQ partial**

`app/views/pages/_faq.html.erb`, from handoff lines 385-414. The first item is `open`. Answers contain links, so they use `raw`.

```erb
<section id="faq">
  <div class="wrap">
    <p class="eyebrow"># quietly asked</p>
    <h2 class="sec">Questions</h2>
    <% EVENT["faq"].each_with_index do |item, index| %>
      <details class="faq-item" <%= "open" if index.zero? %>>
        <summary class="faq-q"><%= item["q"] %><span class="plus">+</span></summary>
        <div class="faq-a"><p><%= raw item["a"] %></p></div>
      </details>
    <% end %>
  </div>
</section>
```

- [ ] **Step 7: Render them in order**

`app/views/pages/home.html.erb` — the order matters, it is the handoff's section order:

```erb
<main id="top">
  <%= render "pages/hero" %>
  <%= render "pages/about" %>
  <%= render "pages/cfp" %>
  <%= render "pages/schedule" %>
  <%= render "pages/venue" %>
  <%= render "pages/sponsors" %>
  <%= render "pages/faq" %>
</main>
```

RSVP is missing on purpose — Task 9 inserts it between About and CFP.

- [ ] **Step 8: Run the tests**

Run: `bin/rails test`
Expected: `11 runs, 0 failures, 0 errors`.

- [ ] **Step 9: Look at it**

```bash
bin/rails server -p 3000
```

Open `http://localhost:3000` and compare side by side with `docs/design-handoff/index.html` opened directly in the browser. Check: fonts are Space Grotesk / Newsreader / JetBrains Mono (not fallbacks), the ruby accent is `#bb1f2c`, section rules are 1px, the FAQ "+" rotates to "×" on open. Fix any drift before committing.

- [ ] **Step 10: Commit**

```bash
git add app test
git commit -m "Add CFP, schedule, venue, and FAQ sections"
```

---

### Task 8: Rsvp model with the 40-seat cap

**Files:**
- Create: `app/models/rsvp.rb`
- Create: `db/migrate/<timestamp>_create_rsvps.rb`
- Modify: `db/schema.rb` (generated)
- Create: `test/models/rsvp_test.rb`
- Modify: `test/fixtures/rsvps.yml` (generated — empty it)

**Interfaces:**
- Produces: `Rsvp::CAPACITY` (Integer, 40), `Rsvp.seats_taken` → Integer, `Rsvp.seats_left` → Integer, `Rsvp.full?` → Boolean, `Rsvp.reserve(name:, email:, dietary:)` → `Rsvp` (persisted or with errors). The returned record's `waitlisted?` tells the controller which partial to render. Consumed by Tasks 9, 10, 11.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate model Rsvp name:string email:string dietary:text waitlisted:boolean
```

Edit the generated migration to add the constraints Rails does not infer:

```ruby
class CreateRsvps < ActiveRecord::Migration[8.0]
  def change
    create_table :rsvps do |t|
      t.string  :name,       null: false
      t.string  :email,      null: false
      t.text    :dietary
      t.boolean :waitlisted, null: false, default: false

      t.timestamps
    end

    add_index :rsvps, "lower(email)", unique: true, name: "index_rsvps_on_lower_email"
    add_index :rsvps, :waitlisted
  end
end
```

The functional unique index is the real guard against duplicate reservations. A model-level uniqueness validation alone loses to a race between two simultaneous submissions.

- [ ] **Step 2: Empty the generated fixtures**

Rails generates `test/fixtures/rsvps.yml` with two sample rows. They would count against the seat cap in every test and make the capacity tests lie. Replace the whole file with:

```yaml
# Intentionally empty. Seat-cap tests create their own records so the count is
# always explicit.
```

- [ ] **Step 3: Write the failing model test**

`test/models/rsvp_test.rb`:

```ruby
require "test_helper"

class RsvpTest < ActiveSupport::TestCase
  test "requires a name" do
    rsvp = Rsvp.new(email: "a@example.com")
    assert_not rsvp.valid?
    assert_includes rsvp.errors[:name], "can't be blank"
  end

  test "requires a well-formed email" do
    rsvp = Rsvp.new(name: "Ada", email: "not-an-email")
    assert_not rsvp.valid?
    assert_includes rsvp.errors[:email], "is not a valid email address"
  end

  test "email uniqueness ignores case" do
    Rsvp.create!(name: "Ada", email: "ada@example.com")
    dup = Rsvp.new(name: "Ada Again", email: "ADA@example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already reserved a seat"
  end

  test "normalises email to lowercase and strips whitespace" do
    rsvp = Rsvp.create!(name: "  Ada  ", email: "  ADA@Example.COM ")
    assert_equal "ada@example.com", rsvp.email
    assert_equal "Ada", rsvp.name
  end

  test "seats_left counts down from capacity" do
    assert_equal Rsvp::CAPACITY, Rsvp.seats_left
    Rsvp.reserve(name: "Ada", email: "ada@example.com")
    assert_equal Rsvp::CAPACITY - 1, Rsvp.seats_left
  end

  test "the last seat is confirmed and the next is waitlisted" do
    (Rsvp::CAPACITY - 1).times do |i|
      Rsvp.reserve(name: "Guest #{i}", email: "guest#{i}@example.com")
    end

    last = Rsvp.reserve(name: "Last", email: "last@example.com")
    assert last.persisted?
    assert_not last.waitlisted?
    assert_equal 0, Rsvp.seats_left
    assert Rsvp.full?

    overflow = Rsvp.reserve(name: "Overflow", email: "overflow@example.com")
    assert overflow.persisted?
    assert overflow.waitlisted?
  end

  test "waitlisted records do not consume seats" do
    Rsvp.create!(name: "W", email: "w@example.com", waitlisted: true)
    assert_equal Rsvp::CAPACITY, Rsvp.seats_left
  end

  test "reserve returns an unpersisted record with errors when invalid" do
    rsvp = Rsvp.reserve(name: "", email: "nope")
    assert_not rsvp.persisted?
    assert rsvp.errors.any?
  end
end
```

- [ ] **Step 4: Run it and watch it fail**

Run: `bin/rails db:migrate && bin/rails test test/models/rsvp_test.rb`
Expected: FAIL — `NameError: uninitialized constant Rsvp::CAPACITY` and validation failures.

- [ ] **Step 5: Write the model**

`app/models/rsvp.rb`:

```ruby
class Rsvp < ApplicationRecord
  CAPACITY = EVENT["capacity"]

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :name,  with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :email,
    presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email address" },
    uniqueness: { case_sensitive: false, message: "has already reserved a seat" }

  scope :confirmed,  -> { where(waitlisted: false) }
  scope :waitlisted, -> { where(waitlisted: true) }

  def self.seats_taken = confirmed.count
  def self.seats_left  = [CAPACITY - seats_taken, 0].max
  def self.full?       = seats_left.zero?

  # Creates a reservation, deciding confirmed-vs-waitlisted under a lock so two
  # simultaneous submissions can't both claim the last seat.
  #
  # Returns a persisted Rsvp on success, or an unpersisted one carrying errors.
  def self.reserve(name:, email:, dietary: nil)
    rsvp = new(name: name, email: email, dietary: dietary)
    return rsvp unless rsvp.valid?

    transaction do
      # Serialises concurrent reservations on a single advisory lock. Cheaper
      # than locking the table, and correct for the one row we're about to add.
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      rsvp.waitlisted = full?
      rsvp.save
    end

    rsvp
  rescue ActiveRecord::RecordNotUnique
    # Lost a race against a duplicate email; surface it as a validation error.
    rsvp.errors.add(:email, "has already reserved a seat")
    rsvp
  end

  # Arbitrary constant identifying the reservation lock in Postgres.
  LOCK_KEY = 4_242_026
end
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/models/rsvp_test.rb`
Expected: `8 runs, 0 failures, 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add app/models db test
git commit -m "Add Rsvp model with seat cap and waitlist"
```

---

### Task 9: RSVP section, controller, and spam protection

**Files:**
- Create: `app/controllers/rsvps_controller.rb`
- Create: `app/views/pages/_rsvp.html.erb`
- Create: `app/views/rsvps/_form.html.erb`
- Create: `app/views/rsvps/_confirmation.html.erb`
- Create: `app/views/rsvps/_full.html.erb`
- Create: `app/helpers/rsvps_helper.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/pages/home.html.erb`
- Create: `test/controllers/rsvps_controller_test.rb`

**Interfaces:**
- Consumes: `Rsvp.reserve`, `Rsvp.full?`, `Rsvp.seats_left` from Task 8.
- Produces: `POST /rsvps` as `rsvps_path`; the turbo-frame id `rsvp_form`; `RsvpsHelper#rsvp_form_timestamp` → signed String and `#rsvp_timestamp_fresh?(value)` → Boolean, reused by the controller.

- [ ] **Step 1: Write the failing controller test**

`test/controllers/rsvps_controller_test.rb`:

```ruby
require "test_helper"

class RsvpsControllerTest < ActionDispatch::IntegrationTest
  # A timestamp old enough to pass the minimum-dwell check.
  def valid_timestamp
    ActiveSupport::MessageVerifier
      .new(Rails.application.secret_key_base, digest: "SHA256")
      .generate(10.seconds.ago.to_i)
  end

  def params(overrides = {})
    { rsvp: { name: "Ada", email: "ada@example.com", dietary: "" },
      company: "",
      t: valid_timestamp }.deep_merge(overrides)
  end

  test "a valid rsvp is stored and confirmed" do
    assert_difference "Rsvp.count", 1 do
      post rsvps_path, params: params
    end
    assert_response :success
    assert_match "Tak!", response.body
    assert_not Rsvp.last.waitlisted?
  end

  test "an invalid rsvp re-renders the form with errors and stores nothing" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(rsvp: { email: "nope" })
    end
    assert_response :unprocessable_entity
    assert_match "not a valid email address", response.body
  end

  test "a filled honeypot is silently discarded" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(company: "Spam Co")
    end
    assert_response :success
    assert_match "Tak!", response.body
  end

  test "a submission faster than the dwell threshold is discarded" do
    fresh = ActiveSupport::MessageVerifier
      .new(Rails.application.secret_key_base, digest: "SHA256")
      .generate(Time.current.to_i)

    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: fresh)
    end
    assert_response :success
    assert_match "Tak!", response.body
  end

  test "a tampered timestamp is discarded" do
    assert_no_difference "Rsvp.count" do
      post rsvps_path, params: params(t: "forged")
    end
    assert_response :success
  end

  test "an rsvp past capacity is waitlisted" do
    Rsvp::CAPACITY.times { |i| Rsvp.reserve(name: "G#{i}", email: "g#{i}@example.com") }

    post rsvps_path, params: params
    assert_response :success
    assert Rsvp.last.waitlisted?
    assert_match "waitlist", response.body
  end

  test "the landing page renders the rsvp form" do
    get root_path
    assert_select "form.rsvp-form"
    assert_select "input[name=?]", "rsvp[name]"
    assert_select "input[name=?]", "rsvp[email]"
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/rsvps_controller_test.rb`
Expected: FAIL — `undefined local variable or method 'rsvps_path'`.

- [ ] **Step 3: Add the route**

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "pages#home"
  resources :rsvps, only: [ :create ]
end
```

- [ ] **Step 4: Write the timestamp helper**

`app/helpers/rsvps_helper.rb`. The form embeds a signed creation time; a submission arriving in under three seconds was not typed by a person.

```ruby
module RsvpsHelper
  MIN_DWELL = 3.seconds

  def rsvp_form_timestamp
    rsvp_verifier.generate(Time.current.to_i)
  end

  def rsvp_timestamp_fresh?(value)
    issued_at = rsvp_verifier.verify(value.to_s)
    Time.current.to_i - issued_at >= MIN_DWELL.to_i
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    false
  end

  private

  def rsvp_verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.secret_key_base, digest: "SHA256"
    )
  end
end
```

- [ ] **Step 5: Write the controller**

`app/controllers/rsvps_controller.rb`:

```ruby
class RsvpsController < ApplicationController
  include RsvpsHelper

  rate_limit to: 5, within: 1.minute, only: :create, with: -> { render_confirmation }

  def create
    return render_confirmation if bot?

    @rsvp = Rsvp.reserve(
      name: rsvp_params[:name],
      email: rsvp_params[:email],
      dietary: rsvp_params[:dietary].presence
    )

    if @rsvp.persisted?
      @rsvp.waitlisted? ? render_full : render_confirmation
    else
      render partial: "rsvps/form", locals: { rsvp: @rsvp },
             status: :unprocessable_entity
    end
  end

  private

  def rsvp_params
    params.require(:rsvp).permit(:name, :email, :dietary)
  end

  # Two silent filters: a honeypot field no human sees, and a minimum dwell
  # time. Both return the normal confirmation so a bot learns nothing.
  def bot?
    params[:company].present? || !rsvp_timestamp_fresh?(params[:t])
  end

  def render_confirmation
    render partial: "rsvps/confirmation"
  end

  def render_full
    render partial: "rsvps/full"
  end
end
```

`rate_limit` is built into Rails 8's `ActionController::Base` and stores counters in the Rails cache. In production this needs a cache store that survives across requests — Task 12 sets `config.cache_store = :memory_store`, which is per-process but adequate for a single-instance service.

- [ ] **Step 6: Write the form partial**

`app/views/rsvps/_form.html.erb`. The honeypot is `.visually-hidden` (from Task 3) plus `tabindex="-1"`, `autocomplete="off"`, and `aria-hidden` so neither a keyboard user nor a screen reader ever reaches it.

```erb
<%= form_with model: rsvp, url: rsvps_path, class: "rsvp-form",
              data: { turbo_frame: "rsvp_form" } do |f| %>

  <div class="visually-hidden" aria-hidden="true">
    <label for="company">Company (leave this empty)</label>
    <input type="text" name="company" id="company" tabindex="-1" autocomplete="off">
  </div>
  <input type="hidden" name="t" value="<%= rsvp_form_timestamp %>">

  <% if rsvp.errors[:name].any? %>
    <p class="field-error"><%= rsvp.errors[:name].first %></p>
  <% end %>
  <%= f.text_field :name,
        placeholder: "Your name",
        "aria-label": "Your name",
        "aria-invalid": rsvp.errors[:name].any?.to_s,
        required: true,
        autofocus: rsvp.errors[:name].any? %>

  <% if rsvp.errors[:email].any? %>
    <p class="field-error"><%= rsvp.errors[:email].first %></p>
  <% end %>
  <%= f.email_field :email,
        placeholder: "you@example.com",
        "aria-label": "Email address",
        "aria-invalid": rsvp.errors[:email].any?.to_s,
        required: true,
        autofocus: rsvp.errors[:name].empty? && rsvp.errors[:email].any? %>

  <%= f.text_field :dietary,
        placeholder: "Dietary needs or allergies (optional)",
        "aria-label": "Dietary needs or allergies" %>

  <button type="submit" class="btn btn-primary">Reserve my seat <span class="arr">→</span></button>
<% end %>
```

The submit control is a hand-written `<button>` rather than `f.submit`, so the markup matches the handoff exactly — `f.submit` emits an `<input>`, which cannot contain the `<span class="arr">→</span>` the hover animation targets.

- [ ] **Step 7: Write the confirmation and full partials**

`app/views/rsvps/_confirmation.html.erb` — text verbatim from handoff line 297:

```erb
<p class="rsvp-ok">Tak! Your seat is reserved. See you on the 28th. ☕</p>
```

`app/views/rsvps/_full.html.erb`:

```erb
<p class="rsvp-ok">
  Tak! We're full, so you're on the waitlist. We'll email you the moment a seat opens up.
</p>
```

- [ ] **Step 8: Write the RSVP section partial**

`app/views/pages/_rsvp.html.erb`, from handoff lines 282-301. The turbo-frame wraps only the form so the price, sub-note, and foot-note survive the swap.

```erb
<section id="rsvp">
  <div class="wrap">
    <p class="eyebrow"># rsvp</p>
    <h2 class="sec">Save your seat</h2>
    <div class="rsvp-card">
      <div class="rsvp-price">
        <span class="big">Free</span>
      </div>
      <p class="rsvp-sub">Includes talks, a long lunch, afternoon coffee, and the evening DJ. Just bring yourself. Space is capped at 40, so please only reserve if you plan to come.</p>

      <%= turbo_frame_tag "rsvp_form" do %>
        <% if Rsvp.full? %>
          <p class="rsvp-sub">We're at 40 people. You can still join the waitlist.</p>
        <% end %>
        <%= render "rsvps/form", rsvp: Rsvp.new %>
      <% end %>

      <p class="rsvp-note">free · one confirmation email · release your seat if plans change</p>
    </div>
  </div>
</section>
```

- [ ] **Step 9: Render it in the page**

In `app/views/pages/home.html.erb`, insert `<%= render "pages/rsvp" %>` between the about and cfp renders, matching the handoff order.

- [ ] **Step 10: Run the tests**

Run: `bin/rails test`
Expected: `19 runs, 0 failures, 0 errors`.

- [ ] **Step 11: Commit**

```bash
git add app config test
git commit -m "Add RSVP form, controller, and spam protection"
```

---

### Task 10: Confirmation and notification email

**Files:**
- Create: `app/mailers/rsvp_mailer.rb`
- Create: `app/views/rsvp_mailer/confirmation.text.erb`
- Create: `app/views/rsvp_mailer/notification.text.erb`
- Modify: `app/controllers/rsvps_controller.rb`
- Modify: `config/environments/development.rb`
- Modify: `Gemfile` (add `letter_opener` to the development group)
- Create: `test/mailers/rsvp_mailer_test.rb`
- Modify: `test/controllers/rsvps_controller_test.rb`

**Interfaces:**
- Consumes: `Rsvp` from Task 8, `EVENT["contact"]` and `EVENT["venue"]` from Task 6.
- Produces: `RsvpMailer.confirmation(rsvp)` and `RsvpMailer.notification(rsvp)`, both `Mail::Message`. Called with `deliver_later` from `RsvpsController#create`.

Plain-text only. A one-paragraph confirmation for a 40-person event does not need an HTML email, and text bodies never land in a spam filter for having a mismatched multipart.

- [ ] **Step 1: Write the failing mailer test**

`test/mailers/rsvp_mailer_test.rb`:

```ruby
require "test_helper"

class RsvpMailerTest < ActionMailer::TestCase
  setup do
    @rsvp = Rsvp.create!(name: "Ada", email: "ada@example.com", dietary: "no nuts")
  end

  test "confirmation goes to the attendee with the date and address" do
    mail = RsvpMailer.confirmation(@rsvp)
    assert_equal [ "ada@example.com" ], mail.to
    assert_equal "Your seat at hygge.rb is reserved", mail.subject
    assert_match "Ada", mail.body.to_s
    assert_match "28 November 2026", mail.body.to_s
    assert_match "Åboulevarden", mail.body.to_s
  end

  test "notification goes to the organiser with the details and seat count" do
    mail = RsvpMailer.notification(@rsvp)
    assert_equal [ ENV.fetch("ORGANISER_EMAIL", "hello@hyggerb.dk") ], mail.to
    assert_match "ada@example.com", mail.body.to_s
    assert_match "no nuts", mail.body.to_s
    assert_match "#{Rsvp.seats_taken} of #{Rsvp::CAPACITY}", mail.body.to_s
  end

  test "waitlisted confirmation says waitlist, not reserved" do
    waitlisted = Rsvp.create!(name: "Bo", email: "bo@example.com", waitlisted: true)
    mail = RsvpMailer.confirmation(waitlisted)
    assert_equal "You're on the hygge.rb waitlist", mail.subject
    assert_match "waitlist", mail.body.to_s
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/mailers/rsvp_mailer_test.rb`
Expected: FAIL — `NameError: uninitialized constant RsvpMailer`.

- [ ] **Step 3: Write the mailer**

`app/mailers/rsvp_mailer.rb`:

```ruby
class RsvpMailer < ApplicationMailer
  default from: -> { "hygge.rb <#{EVENT.dig("contact", "hello")}>" }

  def confirmation(rsvp)
    @rsvp = rsvp
    subject = if rsvp.waitlisted?
      "You're on the hygge.rb waitlist"
    else
      "Your seat at hygge.rb is reserved"
    end

    mail to: rsvp.email, subject: subject
  end

  def notification(rsvp)
    @rsvp = rsvp
    @seats_taken = Rsvp.seats_taken

    mail to: ENV.fetch("ORGANISER_EMAIL", EVENT.dig("contact", "hello")),
         subject: "New hygge.rb RSVP: #{rsvp.name}",
         reply_to: rsvp.email
  end
end
```

- [ ] **Step 4: Write the email bodies**

`app/views/rsvp_mailer/confirmation.text.erb`:

```erb
Hi <%= @rsvp.name %>,

<% if @rsvp.waitlisted? -%>
hygge.rb is full, so you're on the waitlist. People's plans change more often
than you'd think, and we'll email you the moment a seat opens up.
<% else -%>
Your seat at hygge.rb is reserved. Tak!
<% end -%>

  Saturday 28 November 2026, 10:00 - 19:00
  <%= EVENT.dig("venue", "address") %>

Talks, a long lunch, afternoon coffee, and an evening DJ set. Free, thanks to
our sponsors. Just bring yourself.

<% unless @rsvp.waitlisted? -%>
We only have <%= Rsvp::CAPACITY %> seats. If your plans change, reply to this
email and we'll pass your seat to someone on the waitlist.
<% end -%>

See you by the river,
hygge.rb
```

`app/views/rsvp_mailer/notification.text.erb`:

```erb
New RSVP.

  Name:     <%= @rsvp.name %>
  Email:    <%= @rsvp.email %>
  Dietary:  <%= @rsvp.dietary.presence || "none given" %>
  Status:   <%= @rsvp.waitlisted? ? "WAITLISTED" : "confirmed" %>

Seats taken: <%= @seats_taken %> of <%= Rsvp::CAPACITY %>.
```

- [ ] **Step 5: Send the mail from the controller**

In `app/controllers/rsvps_controller.rb`, replace the `if @rsvp.persisted?` branch:

```ruby
    if @rsvp.persisted?
      deliver_emails(@rsvp)
      @rsvp.waitlisted? ? render_full : render_confirmation
    else
```

and add the private method:

```ruby
  # deliver_later so a mail outage can never fail a reservation.
  def deliver_emails(rsvp)
    RsvpMailer.confirmation(rsvp).deliver_later
    RsvpMailer.notification(rsvp).deliver_later
  end
```

- [ ] **Step 6: Assert the emails in the controller test**

Add to `test/controllers/rsvps_controller_test.rb`:

```ruby
  test "a valid rsvp enqueues both emails" do
    assert_enqueued_emails 2 do
      post rsvps_path, params: params
    end
  end

  test "a rejected rsvp sends nothing" do
    assert_no_enqueued_emails do
      post rsvps_path, params: params(rsvp: { email: "nope" })
      post rsvps_path, params: params(company: "Spam Co")
    end
  end
```

- [ ] **Step 7: Set up letter_opener for development**

Add to `Gemfile` in the `:development` group:

```ruby
  gem "letter_opener"
```

Run: `bundle install`

In `config/environments/development.rb`:

```ruby
  config.action_mailer.delivery_method = :letter_opener
  config.action_mailer.perform_deliveries = true
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

- [ ] **Step 8: Run the tests**

Run: `bin/rails test`
Expected: `24 runs, 0 failures, 0 errors`.

- [ ] **Step 9: See a real email**

```bash
bin/rails server -p 3000
```

Submit the form at `http://localhost:3000#rsvp`. Two browser tabs should open with the confirmation and notification. Read them — check the Danish characters in the address render correctly and the line wrapping is sane.

- [ ] **Step 10: Commit**

```bash
git add app config test Gemfile Gemfile.lock
git commit -m "Send RSVP confirmation and organiser notification emails"
```

---

### Task 11: Admin list and CSV export

**Files:**
- Create: `app/controllers/admin/rsvps_controller.rb`
- Create: `app/views/admin/rsvps/index.html.erb`
- Create: `app/assets/stylesheets/admin.css`
- Modify: `config/routes.rb`
- Create: `test/controllers/admin/rsvps_controller_test.rb`

**Interfaces:**
- Consumes: `Rsvp` scopes from Task 8.
- Produces: `admin_rsvps_path`, HTTP Basic auth gated on `ADMIN_USER` / `ADMIN_PASSWORD`.

- [ ] **Step 1: Write the failing test**

`test/controllers/admin/rsvps_controller_test.rb`:

```ruby
require "test_helper"

class Admin::RsvpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["ADMIN_USER"] = "organiser"
    ENV["ADMIN_PASSWORD"] = "hygge"
    Rsvp.create!(name: "Ada", email: "ada@example.com", dietary: "no nuts")
  end

  def auth_headers(user = "organiser", password = "hygge")
    { "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  test "requires credentials" do
    get admin_rsvps_path
    assert_response :unauthorized
  end

  test "rejects wrong credentials" do
    get admin_rsvps_path, headers: auth_headers("organiser", "wrong")
    assert_response :unauthorized
  end

  test "lists rsvps with the seat count" do
    get admin_rsvps_path, headers: auth_headers
    assert_response :success
    assert_match "ada@example.com", response.body
    assert_match "no nuts", response.body
    assert_match "1 / #{Rsvp::CAPACITY}", response.body
  end

  test "exports csv" do
    get admin_rsvps_path(format: :csv), headers: auth_headers
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "name,email,dietary,waitlisted,created_at", response.body
    assert_match "Ada,ada@example.com,no nuts,false", response.body
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/admin/rsvps_controller_test.rb`
Expected: FAIL — `undefined local variable or method 'admin_rsvps_path'`.

- [ ] **Step 3: Add the route**

In `config/routes.rb`:

```ruby
  namespace :admin do
    resources :rsvps, only: [ :index ]
  end
```

- [ ] **Step 4: Write the controller**

`app/controllers/admin/rsvps_controller.rb`. Rails' built-in `http_basic_authenticate_with` compares with `==`, which leaks the password's length and matching prefix through timing. This uses `secure_compare` instead.

```ruby
require "csv"

class Admin::RsvpsController < ApplicationController
  before_action :authenticate_organiser

  def index
    @rsvps = Rsvp.order(created_at: :asc)

    respond_to do |format|
      format.html
      format.csv do
        send_data to_csv(@rsvps),
          filename: "hyggerb-rsvps-#{Date.current.iso8601}.csv",
          type: "text/csv"
      end
    end
  end

  private

  def authenticate_organiser
    authenticate_or_request_with_http_basic("hygge.rb admin") do |user, password|
      expected_user     = ENV.fetch("ADMIN_USER", "")
      expected_password = ENV.fetch("ADMIN_PASSWORD", "")

      # Fail closed when unset, so a misconfigured deploy can't be walked into
      # with empty credentials.
      next false if expected_user.empty? || expected_password.empty?

      ActiveSupport::SecurityUtils.secure_compare(user, expected_user) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end

  def to_csv(rsvps)
    CSV.generate(headers: true) do |csv|
      csv << %w[name email dietary waitlisted created_at]
      rsvps.each do |rsvp|
        csv << [ rsvp.name, rsvp.email, rsvp.dietary, rsvp.waitlisted, rsvp.created_at.iso8601 ]
      end
    end
  end
end
```

The `&` rather than `&&` is deliberate: it evaluates both comparisons regardless of the first result, so the response time does not reveal whether the username alone was correct.

- [ ] **Step 5: Write the view**

`app/views/admin/rsvps/index.html.erb`:

```erb
<section>
  <div class="wrap admin-wrap">
    <p class="eyebrow"># rsvps</p>
    <h2 class="sec">
      <%= Rsvp.seats_taken %> / <%= Rsvp::CAPACITY %> seats
    </h2>
    <p class="lead">
      <%= Rsvp.seats_left %> left ·
      <%= pluralize(Rsvp.waitlisted.count, "person") %> on the waitlist
    </p>

    <p><%= link_to "Download CSV", admin_rsvps_path(format: :csv), class: "btn btn-ghost" %></p>

    <table class="admin-table">
      <thead>
        <tr>
          <th>Name</th><th>Email</th><th>Dietary</th><th>Status</th><th>When</th>
        </tr>
      </thead>
      <tbody>
        <% @rsvps.each do |rsvp| %>
          <tr>
            <td><%= rsvp.name %></td>
            <td><%= mail_to rsvp.email %></td>
            <td><%= rsvp.dietary.presence || "—" %></td>
            <td><%= rsvp.waitlisted? ? "waitlist" : "confirmed" %></td>
            <td><%= rsvp.created_at.strftime("%d %b %Y, %H:%M") %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</section>
```

`app/assets/stylesheets/admin.css` — tokens only, no new colours:

```css
.admin-wrap { max-width: 940px; }

.admin-table {
  width: 100%;
  border-collapse: collapse;
  font-family: "Space Grotesk", sans-serif;
  font-size: 15px;
  margin-top: 24px;
}
.admin-table th {
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--muted);
  text-align: left;
  font-weight: 400;
  padding: 0 12px 10px 0;
  border-bottom: 1px solid var(--rule-2);
}
.admin-table td {
  padding: 11px 12px 11px 0;
  border-bottom: 1px solid var(--rule);
  vertical-align: top;
  color: var(--ink);
}
```

Add `"admin"` to the `stylesheet_link_tag` list in the layout.

- [ ] **Step 6: Run the tests**

Run: `bin/rails test`
Expected: `28 runs, 0 failures, 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add app config test
git commit -m "Add admin RSVP list with CSV export"
```

---

### Task 12: System test, favicon, and removal of the static site

**Files:**
- Create: `test/system/rsvp_test.rb`
- Create: `app/assets/images/favicon.svg`
- Modify: `app/views/layouts/application.html.erb`
- Delete: `index.html` (the old static site)

**Interfaces:**
- Consumes: everything built so far. This is the end-to-end gate before deployment.

- [ ] **Step 1: Write the system test**

`test/system/rsvp_test.rb`:

```ruby
require "application_system_test_case"

class RsvpTest < ApplicationSystemTestCase
  test "reserving a seat swaps the form for a confirmation" do
    visit root_path

    fill_in "Your name", with: "Ada Lovelace"
    fill_in "Email address", with: "ada@example.com"
    fill_in "Dietary needs or allergies", with: "no nuts"

    # Wait out the minimum-dwell spam check.
    sleep 3.5

    click_button "Reserve my seat"

    assert_text "Tak! Your seat is reserved."
    assert_no_selector "form.rsvp-form"
    assert_equal 1, Rsvp.count
  end

  test "an invalid email keeps the form and shows the error" do
    visit root_path

    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "not-an-email"
    sleep 3.5
    click_button "Reserve my seat"

    assert_selector "form.rsvp-form"
    assert_equal 0, Rsvp.count
  end
end
```

The browser's own `type=email` validation may block submission before Rails sees it. If the second test fails because the form never submits, change the email field's markup to `type="text"` with `inputmode="email"` — server-side validation is the real gate, and native validation bubbles are not part of the design. Note the change in the commit message if you make it.

- [ ] **Step 2: Run it and watch it fail or pass**

Run: `bin/rails test:system`
Expected: PASS. If Chrome is missing, install it — `brew install --cask google-chrome`. If it fails on the Turbo swap, confirm `turbo_frame_tag "rsvp_form"` in `_rsvp.html.erb` matches `data: { turbo_frame: "rsvp_form" }` in `_form.html.erb`.

- [ ] **Step 3: Add a favicon**

`app/assets/images/favicon.svg` — the coffee cup at 32×32, no highlight stroke (invisible at that size):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 32" fill="none">
  <rect width="36" height="32" fill="#f7f1e7"/>
  <path d="M14 4 C13 6 15 7 14 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.55"/>
  <path d="M19 3 C18 5 20 6 19 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.7"/>
  <path d="M24 4 C23 6 25 7 24 9" stroke="#bb1f2c" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.55"/>
  <path d="M8 12 L28 12 L26 26 Q26 29 23 29 L13 29 Q10 29 10 26 Z" fill="#bb1f2c" stroke="#7d1219" stroke-width="1.2" stroke-linejoin="round"/>
  <ellipse cx="18" cy="12" rx="10" ry="1.6" fill="#7d1219"/>
  <path d="M27 16 Q32 17 32 21 Q32 25 27 24" stroke="#7d1219" stroke-width="1.6" fill="none" stroke-linecap="round"/>
</svg>
```

In the layout `<head>`, add Open Graph tags and the icon:

```erb
    <%= favicon_link_tag "favicon.svg", type: "image/svg+xml" %>
    <meta property="og:title" content="hygge.rb">
    <meta property="og:description" content="A tiny, free, one-day Ruby gathering in Aarhus, Denmark. Saturday 28 November 2026.">
    <meta property="og:type" content="website">
    <meta property="og:image" content="<%= asset_url("venue-dentsu-aarhus.png") %>">
    <meta name="twitter:card" content="summary_large_image">
```

`asset_url` needs a host in production — Task 13 sets `config.action_controller.asset_host`. In development it emits a relative path, which is fine.

- [ ] **Step 4: Delete the old static site**

The Rails app now serves the same page. The static `index.html` at the repo root is dead code, and leaving it invites someone to edit the wrong file.

```bash
git rm index.html
```

The copy in `docs/design-handoff/index.html` stays — that is the reference, and later tasks compare against it.

- [ ] **Step 5: Run the full suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all green, `0 failures, 0 errors` in both.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add system tests and favicon, remove the static site"
```

---

### Task 13: Production configuration and Render deployment

**Files:**
- Modify: `render.yaml` (rewrite — currently declares a static service)
- Modify: `config/environments/production.rb`
- Create: `bin/render-build.sh`
- Modify: `config/puma.rb` (confirm port binding)

**Interfaces:**
- Produces: a running Render web service on a `.onrender.com` URL, which Task 14 attaches the domain to.

- [ ] **Step 1: Configure production**

In `config/environments/production.rb`, confirm or set:

```ruby
  config.force_ssl = true
  config.assume_ssl = true
  config.cache_store = :memory_store
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.smtp_settings = {
    address:              "smtp.resend.com",
    port:                 587,
    user_name:            "resend",
    password:             ENV["RESEND_API_KEY"],
    authentication:       :plain,
    enable_starttls_auto: true
  }
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "hyggerb.dk"), protocol: "https" }
```

`raise_delivery_errors = false` so an SMTP outage cannot turn a successful reservation into a 500. The record is already saved by then.

`cache_store = :memory_store` backs the `rate_limit` in Task 9. It is per-process, so it is only correct on a single instance — which is what this service is. If the service is ever scaled to two instances, move to Redis.

- [ ] **Step 2: Write the build script**

`bin/render-build.sh`:

```bash
#!/usr/bin/env bash
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails db:migrate
```

Migrations run at build rather than start, so a failed migration fails the deploy instead of crash-looping the process.

```bash
chmod +x bin/render-build.sh
```

- [ ] **Step 3: Rewrite `render.yaml`**

The current file declares `runtime: static`. Render cannot change a service's runtime in place, so this defines a new service under a new name.

```yaml
databases:
  - name: hyggerb-db
    databaseName: hyggerb
    plan: basic-256mb
    postgresMajorVersion: "16"

services:
  - type: web
    name: hyggerb
    runtime: ruby
    plan: starter
    region: frankfurt
    buildCommand: "./bin/render-build.sh"
    startCommand: "bundle exec puma -C config/puma.rb"
    healthCheckPath: /up
    envVars:
      - key: DATABASE_URL
        fromDatabase:
          name: hyggerb-db
          property: connectionString
      - key: RAILS_MASTER_KEY
        sync: false
      - key: RAILS_ENV
        value: production
      - key: RAILS_SERVE_STATIC_FILES
        value: "true"
      - key: RAILS_LOG_TO_STDOUT
        value: "true"
      - key: WEB_CONCURRENCY
        value: "2"
      - key: APP_HOST
        value: hyggerb.dk
      - key: ORGANISER_EMAIL
        sync: false
      - key: RESEND_API_KEY
        sync: false
      - key: ADMIN_USER
        sync: false
      - key: ADMIN_PASSWORD
        sync: false
```

`region: frankfurt` is the closest Render region to Denmark. `sync: false` means the value is set in the dashboard, not committed — these are secrets.

`/up` is the health check endpoint Rails 8 generates by default. Confirm it exists: `grep -n "up" config/routes.rb`. If it is missing, add `get "up" => "rails/health#show", as: :rails_health_check`.

- [ ] **Step 4: Verify the production build locally**

```bash
RAILS_ENV=production SECRET_KEY_BASE=$(bin/rails secret) bundle exec rails assets:precompile
```

Expected: completes without error and writes to `public/assets`. If it fails on a missing font file, a filename in `fonts.css` does not match what is on disk — fix the name, do not delete the declaration.

Clean up: `rm -rf public/assets tmp/cache/assets`

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "Configure production environment and Render deployment"
git push origin main
```

- [ ] **Step 6: Create the service on Render**

In the Render dashboard: **New → Blueprint**, point at this repository, and let it read `render.yaml`. It creates both `hyggerb-db` and the `hyggerb` web service.

Then set the four `sync: false` secrets in the service's Environment tab:

- `RAILS_MASTER_KEY` — the contents of the local `config/master.key`
- `ORGANISER_EMAIL` — where RSVP notifications should land
- `ADMIN_USER` and `ADMIN_PASSWORD` — pick a long random password (`bin/rails secret | cut -c1-32`)
- `RESEND_API_KEY` — leave unset for now; Task 14 fills it in

- [ ] **Step 7: Verify the deploy**

Once the deploy is green, open the `.onrender.com` URL and check:

- The page renders with the correct fonts and colours
- Submitting an RSVP shows "Tak! Your seat is reserved."
- `/admin/rsvps` prompts for credentials and then lists that RSVP
- `/up` returns 200

Email will not send yet — `RESEND_API_KEY` is unset, and `raise_delivery_errors = false` means the failure is logged and swallowed rather than breaking the reservation. That is expected at this stage.

- [ ] **Step 8: Delete the old static service**

Only after the new service is confirmed working: in the Render dashboard, delete the old `ruby-dk-conference` static site. Do not delete it before this point — it is the currently-live site.

---

### Task 14: Domain and email verification

This task depends on a domain that must be purchased by the user. It cannot be completed by an agent working alone. Stop and hand back at each **USER** step.

**Files:**
- Modify: `config/event.yml` (real contact addresses and links, once the domain exists)

- [ ] **Step 1: USER — register the domain**

Register `hyggerb.dk` through a DK Hostmaster reseller — one.com, Simply.com, or DK-Hostmaster directly. Roughly 50-100 DKK/year.

`.dk` requires MitID, or a paid identity-verification step for registrants without one. **If that is a blocker, stop here** and switch to `hyggerb.com` via Cloudflare or Porkbun instead. The only code change is the `APP_HOST` env var and the addresses in `config/event.yml` — nothing else in the build depends on the TLD.

- [ ] **Step 2: USER — add the custom domain in Render**

In the `hyggerb` service → Settings → Custom Domains, add both `hyggerb.dk` and `www.hyggerb.dk`. Render displays the DNS targets it expects. Copy them out — the exact values are account-specific.

- [ ] **Step 3: Add the DNS records at the registrar**

Two records for Render, using the targets from Step 2:

| Type | Name | Value |
|---|---|---|
| ALIAS (or ANAME) | `@` | the target Render shows for the apex |
| CNAME | `www` | the target Render shows for `www` |

If the registrar does not support ALIAS/ANAME at the apex — many `.dk` resellers do not — use Render's A record IP instead, which the dashboard provides as the fallback, or move DNS to Cloudflare (free) which supports CNAME flattening.

- [ ] **Step 4: Add the Resend records**

Create a Resend account, add `hyggerb.dk` as a sending domain, and add the three records it generates:

| Type | Name | Purpose |
|---|---|---|
| TXT | `send` (or as Resend specifies) | SPF |
| TXT | `resend._domainkey` | DKIM |
| TXT | `_dmarc` | DMARC — start with `v=DMARC1; p=none; rua=mailto:<your address>` |

`p=none` first. It reports without rejecting, so a misconfiguration does not silently drop mail. Tighten to `p=quarantine` after a couple of weeks of clean reports.

- [ ] **Step 5: Wait for propagation, then verify**

DNS takes anywhere from minutes to a few hours.

```bash
dig +short hyggerb.dk
dig +short www.hyggerb.dk
dig +short TXT resend._domainkey.hyggerb.dk
```

Expected: the first two resolve to Render's targets, the third returns the DKIM key. Then confirm in the Resend dashboard that the domain shows as verified.

- [ ] **Step 6: Turn on production email**

Set `RESEND_API_KEY` in the Render dashboard. Render redeploys automatically.

Submit a real RSVP on `https://hyggerb.dk` and confirm both emails arrive — the attendee confirmation and the organiser notification. Check the confirmation lands in the inbox rather than spam; if it lands in spam, the DKIM record has not propagated yet.

- [ ] **Step 7: Verify HTTPS and the canonical redirect**

```bash
curl -sI https://hyggerb.dk | head -1
curl -sI http://hyggerb.dk | head -2
curl -sI https://www.hyggerb.dk | head -2
```

Expected: `200` on the apex over HTTPS; the plain-HTTP request returns a `301` to HTTPS; `www` returns a `301` to the apex. Render handles both redirects when both domains are registered on the service. Certificates are issued automatically — if HTTPS fails, the DNS records are not yet fully propagated.

- [ ] **Step 8: Update the contact addresses**

Now that the domain exists, the placeholder links in `config/event.yml` can become real. Set `contact.hello` and `contact.sponsor` to working addresses, and fill in `links.cfp_submit`, `links.cfp_guidelines`, `links.become_sponsor`, `links.code_of_conduct`, and `links.social` with real URLs as they become available. Anything still unknown stays `#`.

```bash
git add config/event.yml
git commit -m "Point contact addresses at the live domain"
git push origin main
```

---

## Deferred

Not in this plan, listed so they are not forgotten:

- **Releasing a seat.** The confirmation email says to reply. A one-click release link with a signed token is the obvious follow-up once RSVPs actually start arriving.
- **Promoting from the waitlist.** Currently manual — read the admin list, email the person. Fine at 40 people.
- **A real CFP tool.** The CFP buttons point at `config/event.yml` URLs. Wire them to whatever tool gets chosen.
- **Sponsor logos.** Text names for now, per the handoff.
- **Mobile nav.** Deliberately absent, per the spec. Revisit only if mobile visitors are demonstrably failing to reach the RSVP form.
