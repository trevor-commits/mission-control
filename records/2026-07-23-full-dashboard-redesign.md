# Full dashboard redesign (index.html)

Date: 2026-07-23
Actor: Hermes (desktop), session 20260723_185924_09ac6d
Request: Trevor — "Can you also redesign the main full dashboard?" (follow-up to
the menu-bar panel redesign, fd6710a).

## Approach

CSS-layer redesign + two additive JS enhancements. All renderer copy,
structure, tab names, feed handling, and guard logic are byte-identical, so
every test-enforced contract (render-smoke copy assertions, browser overflow /
contrast / strip-buttons / copy-targets, er134 token greps) holds unchanged.

## What changed (`dashboard/index.html`)

### Tokens
- Light: softer borders (#dfe3ea/#c3c9d4), surface-2 #f0f2f6, fg #16181d,
  accent-bg #eceffd, radii 10/14px, softer modern shadows, new
  `--mc-brand-grad` (matches the menu-bar panel mark), SF Pro Text in the font
  stack. `--mc-bg:        #f4f5f7` kept byte-identical (er134 grep).
- Dark: surfaces aligned to the menu-bar panel palette (#0f1114 / #171a1f /
  #1e2128), matching brand gradient.
- `--mc-red` deepened #c43c45 → #bd353f (contrast headroom: worst measured
  ratio 4.59 → 5.00; all 36 token×surface ratios ≥ 4.5 in both themes,
  pre-verified with the browser test's own luminance math).
- `dashboard/panel.html` light red aligned to the same #bd353f (one shared red
  across popover + dashboard).

### Header
- Global strip gains a brand block (gradient MC mark + "Mission Control"),
  hidden under 640px so mobile strip height is unchanged; segmented strip
  pills; nav becomes segmented pill tabs (accent-tinted active) with hidden
  scrollbar; sticky offsets verified against the 47.5px strip height.

### Home
- New status hero (additive, above the existing "Needs you" h1): one-line
  answer ("All clear" / "N things need you" / "N red jobs need repair"), feed
  freshness subline, tone pill, and a 3-tile stat strip (Needs you / Jobs
  healthy / Feed age) — mirrors the menu-bar panel's header so both surfaces
  speak the same language. Pure read over existing guards; no feed changes.
- "Show more details" is now a full-width dashed affordance button.
- Glance option buttons stack full-width (was wrapping row of small buttons).

### Components
- Tables get the framed-card treatment (surface, border, radius, inner gutter,
  uppercase micro header labels, row hover), shared with mc-panel-table.
- Banners gain a 3px tone bar on the leading edge.
- Cards/rows/svc cards: softer borders, 14px radius, lift-on-hover shadows.
- Copy buttons: hover tint, same 32/44px target floors.
- Usage decision cards / KPI / chips / badges: weight + letter-spacing polish.
- Activity heatmap: proper light-theme green scale (was dark-on-white before,
  effectively invisible in light mode); dark theme keeps the old scale.
- Map side panel: uppercase section labels, styled scrollbars; legend lines
  rounded; ::selection tint; prefers-reduced-motion preserved.

## Contracts preserved (test-verified)
- All render-smoke copy assertions (8 tabs + negative brief-validity cases).
- `MC.feedErrors` loader tags, `data/brief.error.js`, DESKTOP_GLANCE_CTA copy.
- Strip segments remain native `<button>` (keyboard operable); `.mc-copy`
  32px desktop / 44px mobile targets; no document overflow at 390px or 1440px
  on any tab; active nav tab always inside the viewport.
- Renderer JS logic untouched except two additive blocks (renderStrip brand
  prepend, renderHome hero + homeHeroState helper).

## Evidence
- `scripts/er134-usability.test.sh`: 60/60 PASS.
- `scripts/dashboard.test.sh`: 67/67 PASS.
- `scripts/attention-lane.test.sh`: 5/5 PASS.
- `scripts/dashboard-render-smoke.js`: all 8 tabs + negative cases PASS.
- `scripts/dashboard-browser.test.js`: 253 assertions PASS (both themes,
  desktop+mobile, installed+demo states).
- Contrast pre-check: 36/36 ratios ≥ 4.5 (worst 5.00), same luminance math as
  the browser suite.
- render_check.py (cloak) over live `~/.mission-control/data` feeds, home tab,
  1440 + 390, light+dark: PASS, zero console errors.
- Adversarial self-audit: nav sticky offset recomputed against real strip
  height; mobile brand hidden to keep strip single-line; scope cuts
  (attention-table-to-cards, collapsible depth) deliberately deferred.

## Known limits
- Vision-model screenshot review was unavailable (aux vision endpoint timing
  out all day); visual sign-off rests on DOM assertions, browser-suite
  geometry checks, and the attached render_check screenshots.
