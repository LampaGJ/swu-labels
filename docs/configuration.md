---
type: spec
status: active
related: [template-language.md]
---

**What this answers:** every knob on `LabelLayoutConfig` (`src/config.ts`), its default, and what it controls.

**TL;DR:** One typed config object (`DEFAULT_CONFIG`) drives every layout decision — alignment, icon position, indent, set ordering, font sizes/auto-shrink, unique-card marker, and (since the template-driven rewrite) the label's line content and order. Nothing else in `src/` hardcodes a layout choice.

## Knobs

- **`template`** — `Array<{ style: string; text: string }>`. The label's lines, in render order. Each line's `text` is the small template language documented in full in docs/template-language.md (variable catalog, joiner/collapsing rules, worked examples). Default:
  1. `{ style: 'cardTitle', text: '{unique_indicator} {Title}' }`
  2. `{ style: 'cardSubtitle', text: '{Subtitle}' }`
  3. `{ style: 'cardStats', text: '{rarity_symbol} {SET} - {cost_value} {cost_label} | {power_value} {power_label} | {hp_value} {hp_label}' }`

  Reordering the array reorders the label's lines. This is the **only** thing that controls line order — it replaces the earlier `statsLinePosition: 'below' | 'above'` knob, which is removed (see "Removed: statsLinePosition" below).

- **`align`** — `'center'` (default) or `'left'`. Paragraph alignment for every label line.

- **`iconBaselineShiftHalfPoints`** — OOXML run vertical position (`w:position`, half-points, negative = lowered) applied to the rarity icon's run so it optically sits on the stat line's text baseline instead of riding high above it. Default `-2` (1pt lowered). `-4` was tried and found too low; `0` was tried and found too high.

- **`hangingIndent`** — `boolean`, default `false`. When `true` **and** `align: 'left'`, wrapped stat-line/title text indents under the title start rather than under the icon/cost. Ignored entirely in centered mode (there's no "start" for wrapped text to hang from).

- **`hangingIndentTwips`** — hanging-indent depth in twips, used only when `hangingIndent` is `true`. Default `360`.

- **`setOrder`** — `'release'` (default) or `'alphabetical'`. `'release'` orders sets within an aspect group as `JTL, LOF, SEC, LAW, ASH, IBH` (chronological release order). `'alphabetical'` fold-sorts set codes deterministically (never `.localeCompare()` — the reproducible-data doctrine bans locale-aware comparison because its result depends on host ICU data).

- **`statLineFontHalfPoints`** — stats-line font size, half-points. Default `12` (6pt).

- **`titleFontHalfPoints`** — title font size before auto-shrink, half-points. Default `14` (7pt), bold via the `cardTitle` paragraph style.

- **`titleShrinkFontHalfPoints`** — title font size once shrunk. Default `12` (6pt).

- **`titleShrinkThreshold`** — title character-length threshold above which the shrink size applies. Default `30`.

- **`subtitleFontHalfPoints`** — subtitle font size before auto-shrink, half-points. Default `12` (6pt), italic via the `cardSubtitle` paragraph style.

- **`subtitleShrinkFontHalfPoints`** — subtitle font size once shrunk. Default `11`.

- **`subtitleShrinkThreshold`** — subtitle character-length threshold above which the shrink size applies. Default `34`.

- **`uniqueMarker`** — text `{unique_indicator}` resolves to on a card where `unique` is true. Default `'◊ '` (diamond + regular space — the SWU convention for marking a unique card's name). Set to `''` to disable the marker without removing the mechanism.

## Removed: `statsLinePosition`

The earlier config carried `statsLinePosition: 'below' | 'above'`, toggling whether the stats line rendered last (`'below'`, the default) or first (`'above'`, reproducing an older layout). That knob is **removed**. Line order is now entirely a property of `template`'s array order — reproduce the old `'above'` behavior by moving the `cardStats` template entry to the front of the array instead. This collapses two competing sources of truth for line order (the enum *and* whatever call order the renderer happened to use) into one: the array you can see and edit directly.

## Named Word styles

`src/render.ts` registers real DOCX paragraph and character styles (not just inline run formatting), so labels can be restyled from Word's style pane without touching this repo. The default template's three lines carry paragraph styles `cardTitle` / `cardSubtitle` / `cardStats` (display names "Card Title" / "Card Subtitle" / "Card Stats"). Character styles, one per variable that needs independent styling: `setName`, `statSeparator`, `costValue`/`costLabel`, `powerValue`/`powerLabel`, `hpValue`/`hpLabel`, `rarityIcon`, `uniqueMarker`, `rarityName`, `typeName`, `aspectName`.
