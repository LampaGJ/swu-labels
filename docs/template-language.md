---
type: spec
status: active
related: [configuration.md]
---

**What this answers:** what `{variable}` names a `config.template` line can reference, how a line's literal text and joiners collapse when some variables render nothing, and what happens when a template names a variable that doesn't exist.

**TL;DR:** `config.template` is an ordered array of `{ style, text }` lines. `text` mixes literal characters with `{variable}` references. Unknown variables throw at parse time, naming themselves. Empty variables (and the literal text around them) collapse away automatically, so one template correctly handles a Unit, a Base, an Event, a Credit Token, and a Pilot without any per-card-type branching.

## Variable catalog

Each entry names its docx character style (`—` = no character style; the paragraph style still applies) and what it does when its value is absent.

- **`{Title}`** — the card's title. Style: none (bold comes from the paragraph style). Empty behavior: never empty in practice (every card has a title); carries the per-card auto-shrink size (`computeTitleFontHalfPoints`).
- **`{Subtitle}`** — the card's subtitle. Style: none (italics comes from the paragraph style). Empty behavior: empty when the card has no subtitle (`null` or `''`) — this is how the whole Subtitle line vanishes for a subtitle-less card. Carries the per-card auto-shrink size (`computeSubtitleFontHalfPoints`).
- **`{unique_indicator}`** — `config.uniqueMarker` (default `'◊ '`) when `card.unique` is true, else empty. Style: `uniqueMarker`. Shrinks to the same size as `{Title}` when both appear on the same line.
- **`{SET}`** — `expansion_code` (e.g. `JTL`). Style: `setName`. Empty behavior: never empty (every card has an expansion code).
- **`{rarity_symbol}`** — the rarity SVG, embedded as an image run with the same baseline shift (`config.iconBaselineShiftHalfPoints`) and `rarityIcon` character style the v2/v3 stat line always used. Never empty — an image run always counts as rendered content.
- **`{cost_value}` / `{power_value}` / `{hp_value}`** — the numeric stat value, exactly as `buildStatLineSegments` computes it today: a plain number (`'3'`), a plain-upgrade `+N` (`'+2'`), or a pilot dual-stat `unit/upgrade+` (`'4/3+'`). Styles: `costValue` / `powerValue` / `hpValue`. Empty behavior: empty when the card has neither a unit value nor an upgrade value for that field (a Base has no cost/power; an Event has no power/HP; a Credit Token has none of the three).
- **`{cost_label}` / `{power_label}` / `{hp_label}`** — the word `cost` / `power` / `HP`. Styles: `costLabel` / `powerLabel` / `hpLabel`. Empty behavior: rendered **only** when the paired value (`{cost_value}` etc.) is non-empty — a label never appears next to a blank value.
- **`{rarity_name}`** — the rarity name (`'Common'`, `'Rare'`, …). Style: `rarityName`. Never empty.
- **`{type}`** — `type_name` (e.g. `'Unit'`, `'Base'`, `'Credit Token'`). Style: `typeName`. Never empty.
- **`{aspect}`** — the card's first aspect, or `'Neutral'` when it has none. Style: `aspectName`. Never empty.

Referencing any name outside this list throws immediately, naming the bad variable — e.g. `{Titel}` (typo) throws `unknown template variable "{Titel}"` before a single label is built. Templates are validated once at parse time, not silently rendered blank per card.

## Joiners and collapsing

A line's `text` uses two special literal substrings as structural joiners, matched with fixed precedence:

1. The **first** ` - ` (space-dash-space) in the text splits the line into up to two **dash sides**. A line with no ` - ` has exactly one side.
2. Each dash side is then split on every `|` into **segments**.

Each segment is rendered independently, then the pieces are rejoined:

- **Per-segment rendering**: walk the segment's tokens (literal text and `{variable}` references) in order. A variable that resolves empty contributes nothing. A literal token between/around variables is kept only when the variable(s) immediately touching it on both sides (whichever exist) all rendered — otherwise it's dropped, so a missing value never leaves a stray space behind. If **no** variable in the segment rendered non-empty content (an image run counts as content), the whole segment collapses to nothing.
- **Sibling join**: surviving (non-empty) segments within one dash side are joined with the canonical `' | '` — whatever spacing surrounded the `|` in the source template is discarded and replaced with this one canonical separator.
- **Dash join**: the two dash sides are joined with `' - '` only when **both** sides are non-empty. If only one side survived, the line is just that side (no dash). If neither survived, the whole line is empty.
- **Line omission**: a line whose every segment collapsed empty produces **no paragraph at all** — not an empty paragraph. This is the mechanism behind the Subtitle line disappearing for a card with no subtitle.

### A narrow, documented exception for byte-identical output

Two variables carry their adjacent separator space as part of their own canonical text, rather than relying on the template's literal space, so that the generated DOCX exactly reproduces the legacy single-run construction it replaces:

- `{unique_indicator}` resolves to the full `config.uniqueMarker` string (default `'◊ '`, trailing space included). The literal space that follows it in `'{unique_indicator} {Title}'` is therefore redundant when the marker rendered, and is dropped rather than re-emitted as a second run.
- `{cost_label}` / `{power_label}` / `{hp_label}` resolve to a leading-space-prefixed word (`' cost'`, not `'cost'`). The literal space that precedes each of them in the default stats line is dropped for the same reason.

This only matters for the exact run-count/byte layout of the generated `document.xml` (the migration-proof gate checks a SHA-256 of that file) — visually, and for any custom template you write, the rendered text reads exactly as you'd expect from the collapsing rules above.

## Worked examples (the default template)

Default `config.template`:

1. `{ style: 'cardTitle', text: '{unique_indicator} {Title}' }`
2. `{ style: 'cardSubtitle', text: '{Subtitle}' }`
3. `{ style: 'cardStats', text: '{rarity_symbol} {SET} - {cost_value} {cost_label} | {power_value} {power_label} | {hp_value} {hp_label}' }`

Stats line, per card type:

- **Unit** (cost 3, power 2, HP 4, set JTL): `[icon] JTL - 3 cost | 2 power | 4 HP`
- **Base** (only HP 30, set SEC): `[icon] SEC - 30 HP` — the cost and power segments collapsed empty and dropped out of the `|`-join; the dash side that would have held them is entirely gone, so there's exactly one ` - `.
- **Event** (only cost 5, set LOF): `[icon] LOF - 5 cost`
- **Credit Token** (no cost/power/HP at all, set ASH): `[icon] ASH` — the entire right-hand dash side collapsed empty, so even the `' - '` joiner is dropped.
- **Pilot unit** (cost 2, power `4/3+`, HP `6/4+`, set JTL): `[icon] JTL - 2 cost | 4/3+ power | 6/4+ HP`

Title line: `'◊ Vanjon'` for a unique card, `'Vanjon'` (no leading space) for a non-unique one — the literal space between `{unique_indicator}` and `{Title}` is dropped when the marker is absent.

## Reordering and restyling lines

Reorder the label's lines by reordering `config.template` — array order is render order, no other config controls it (this replaces the removed `statsLinePosition` knob; see docs/configuration.md). Each line's `style` field is the docx paragraph style id its paragraph carries (`cardTitle`, `cardSubtitle`, `cardStats` by default) — change what each style looks like from Word's style pane without touching this repo, or point two template lines at the same style id to make them look identical.

## Unknown-variable failure behavior

`parseTemplateLine` validates every `{name}` token against the variable catalog at parse time (once per generate run, before any card is processed) and throws `Error: parseTemplateLine: unknown template variable "{name}"` on the first unrecognized one. A template is never partially valid — a typo anywhere in `config.template` fails the whole run before a single label renders blank.
