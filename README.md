# swu-labels

**What this answers:** how to go from the live Star Wars Unlimited card database to a printable sheet of Avery 5167 Premier-format card labels, and where every piece of this pipeline came from.

**TL;DR:** `npm install`, then `npm run ingest` (pulls the live card list), `npm run generate` (builds the default DOCX from the newest ingest), `npm run open` (opens the newest DOCX). Print at 100% scale, no "fit to page." Print one test sheet before committing a full run. Want every layout at once? `npm run generate:all`.

## Quick start

- `npm install` — installs dependencies.
- `npm run pull-formats` — refreshes the vendored `formats.json` from its canonical home (optional; a copy already ships in this repo).
- `npm run ingest` — fetches every card from the official Star Wars Unlimited admin API, filters to canonical printings, and writes a new pinned snapshot under `data/snapshots/v<TAG>/`.
- `npm run generate` — reads a pinned snapshot (default: `v2026-08-23`, the migration-proof snapshot) and writes the default aspect-then-set DOCX + replay record to `reports/`. Target a different snapshot with `npm run generate -- --snapshot v<TAG>`. See [Label sheet layouts](#label-sheet-layouts) for the other four layouts and their dedicated npm scripts.
- `npm run generate:by-set` — the "grouped by rotation set" layout (SOR, SHD, TWI, JTL, LOF, SEC, LAW, ASH, IBH — every set that has ever been part of Premier rotation, not just the six currently legal). Reads the `v2026-08-14` snapshot (the only pinned snapshot with per-set files for the three rotated-out sets); the default `v2026-08-23` snapshot doesn't have them and this script targets `v2026-08-14` explicitly so it works out of the box.
- `npm run generate:by-aspect` — one section per aspect color, no set sub-grouping, alphabetical within.
- `npm run generate:alphabetical` — one continuous alphabetical sheet, no section breaks at all.
- `npm run generate:rotation-by-aspect` — full-rotation-history aspect-then-set: same shape as the default layout (one section per aspect, sets flowing continuously within), but scoped to all nine rotation sets instead of the six currently legal. Also reads `v2026-08-14`.
- `npm run generate:all` — all five layouts in one run (`set` and `rotation-by-aspect` correctly reading `v2026-08-14`, the other three reading the default snapshot).
- `npm run generate:bw` — all five layouts rendered with the print-optimized monochrome rarity icons (`assets/rarities-bw/`) instead of the color ones. Append `-bw` to any generate script's output filename to find these.
- `npm run open` — opens the newest `reports/*.docx` in the default application (Word, Pages, LibreOffice).
- `npm run test` — runs the full test suite (migrated generator tests + new ingest tests).
- `npm run typecheck` — `tsc --noEmit`.
- `npm run lint` — `biome check src test`.

## Label sheet layouts

`src/index.ts` can emit five distinct label-sheet organizations from the same deduped card pool, selected with `--groups <mode>` (comma-separated, or `all`):

- **`aspect-set`** (default) — one section per aspect color (Vigilance, Command, Aggression, Cunning, Villainy, Heroism, Neutral), sets flowing continuously within each aspect (no page break on set change), alphabetical within each set. Output: `premier-labels-avery5167-<snapshot>.docx`.
- **`set`** — one section per set, in rotation-release order; drawn from the *full rotation history* pool (see below), not just the six currently-legal sets. Each aspect present within a set is prefaced with a **divider label** — three lines: the set code, its full name, and `(Aspect) x/y cards` (`x` = deduped cards of that aspect in that set, `y` = the set's total deduped card count). Output: `premier-labels-avery5167-<snapshot>-by-set.docx`.
- **`aspect`** — one section per aspect color, same as `aspect-set` but without the set sub-grouping — cards from every set interleave alphabetically within one aspect's section. Output: `…-by-aspect.docx`.
- **`alphabetical`** — one continuous section, no breaks by aspect or set at all. Output: `…-alphabetical.docx`.
- **`rotation-aspect-set`** — the same aspect-then-set shape as the default `aspect-set` layout (one section per aspect, sets flowing continuously within, alphabetical within each set), but also drawn from the *full rotation history* pool: within each aspect section, sets flow `SOR → SHD → TWI → JTL → LOF → SEC → LAW → ASH → IBH`. The aspect-first/set-second counterpart to `set`'s set-first/aspect-second-with-dividers. Output: `…-rotation-by-aspect-by-set.docx`.

**Why `set` and `rotation-aspect-set` need their own snapshot:** the other three layouts answer "what's legal to play *today*" and read the same six-set pool as always (`PREMIER_FILE_SET_PRECEDENCE`: `JTL, LOF, SEC, LAW, ASH, IBH`) — unchanged, byte-identical to before. `set` and `rotation-aspect-set` answer "every set that has ever been part of Premier rotation," which includes the three sets that have since rotated out (`SOR`, `SHD`, `TWI`) — pool precedence `ROTATION_FILE_SET_PRECEDENCE` in `src/transform.ts`. A card originally released pre-rotation and later reprinted to survive rotation (e.g. into `JTL`) lands under its *original* set here, not the reprint's set, because dedupe keeps the earliest printing in precedence order. `main()` throws a clear error (rather than silently shipping an incomplete sheet) if `SOR`/`SHD`/`TWI` per-set files aren't present under the targeted snapshot's `per-set/` directory — run `npm run ingest` and target the resulting snapshot with `--snapshot` if you're not using the pinned `v2026-08-14` one.

Icon set is selected independently with `--assets <color|bw>` (default `color`); see [Rarity icons](#rarity-icons) below.

**Scoping to specific sets:** any layout can be restricted to a subset of its pool's sets with `--sets <CODE,CODE,...>` — e.g. `--groups rotation-aspect-set --snapshot v2026-08-14 --sets SOR,SHD,TWI` for just the three rotated-out sets, or `--sets LAW,ASH` for just the two newest. The output filename gets a `-CODE-CODE-...` segment so it never collides with the unfiltered file. Throws if a requested code isn't in the targeted mode's pool (e.g. asking for `SOR` on a non-rotation mode).

## Avery 5167 print guidance

- Avery 5167 is 0.5in x 1.75in labels, 80 per sheet (4 columns x 20 rows), on US Letter.
- Print at **100% scale**. Do **not** use "fit to page" or "shrink to fit" — either will misalign every label on the sheet.
- **Print one test sheet on plain paper first**, hold it up to a blank Avery 5167 sheet against a light source, and confirm alignment before loading actual labels.
- The default (`aspect-set`), `by-aspect`, and `rotation-by-aspect` documents have one section per aspect group (Vigilance, Command, Aggression, Cunning, Villainy, Heroism, Neutral); the `by-set` document has one section per set instead; `alphabetical` is a single continuous section. Every section starts a fresh sheet — see [Label sheet layouts](#label-sheet-layouts).
- **Printing to a monochrome/B&W printer:** use `--assets bw` (or `npm run generate:bw`) — the default rarity icons carry hues (olive/gray/gold/blue) that convert to low-contrast, sometimes near-invisible grays at print size; see [Rarity icons](#rarity-icons).

## Provenance

This repo was extracted from a working, fully-tested generator and re-pointed at a standalone ingest pipeline. Nothing here is a from-scratch reimplementation of the label logic.

- **Generator code** (`src/schema.ts`, `src/config.ts`, `src/transform.ts`, `src/render.ts`, `src/index.ts`, `test/transform.test.ts`): migrated verbatim (path adjustments only) from `slicer@1cf167b5` (`feature/premier-card-labels`, `scripts/premier-labels/`). Behavior is preserved exactly — see the migration-proof gate below.
- **Rarity SVGs** (`assets/rarities/*.svg`): copied from `slicer/assets/rarities/`.
- **Pinned snapshot** (`data/snapshots/v2026-08-23/`): copied from `slicer/data/premier-snapshot-v2026-08-23/`. This is the snapshot the migration-proof gate checks against.
- **Ingest semantics** (`src/ingest.ts`, `src/api-schema.ts`): new code, written by reading (read-only) `slicer2/slicer-dev/retrieve-cards/src/sync.ts` and `src/schema.ts` for exact field names, pagination/retry behavior, and canonicalization rules — not copied, since this repo is a standalone fetcher rather than a `retrieve-cards`-release consumer.
- **`formats.json`**: canonical home is `slicer2/slicer-dev/formats.json`. Edit it there; re-pull into this repo with `npm run pull-formats`. The vendored copy in this repo's root ships so the repo works without `slicer-dev` present.

### Migration proof

With the migrated `v2026-08-23` pinned snapshot, `npm run generate` produces a `document.xml` (inside the DOCX) whose SHA-256 is `ea06edf6667a192b050d9fb7145b157d07b2a1bbd4f9c635fc7724b1e91fdb7b` — byte-identical to the sheet the original `slicer` generator produced. This is checked by hand after any change to the generator code; there is no automated CI gate for it in this repo.

## Schema/artifact registry

Every exported schema/function/const/type in `src/` carries co-located TSDoc (`@displayName`/`@strategicPurpose`/`@tacticalObjective`), rolled up by `src/registry.ts` into `docs/registry.json` — one entry per producer plus a `dataFlow` section (API → snapshot → DOCX) and a `coverage` block (`annotatedExports`/`totalExports`/`gaps`). Regenerate with `npm run registry`; verify it's not stale with `npm run audit:registry` (also wired as `prebuild`). Read `docs/registry.json` directly for the full end-to-end data-flow map — this section is a pointer, not a copy of its content.

## Ingest

`src/ingest.ts` fetches `https://admin.starwarsunlimited.com/api/card-list` (a paginated Strapi endpoint), 3 pages concurrently with retry (mirrors `retrieve-cards/src/sync.ts`'s fragility handling), and parses every page at the boundary with `src/api-schema.ts` (Zod, closed on the fields this pipeline consumes — an unknown rarity/type/aspect value fails loudly rather than being coerced).

- **Canonicalization**: only cards where both `variantOf` and `reprintOf` are `null` are kept (per `slicer-dev` CLAUDE.md: "the canonical printing has both as NULL").
- **Determinism**: the snapshot tag is derived from the data itself — the `YYYY-MM-DD` of the maximum `updatedAt` across all ingested cards — not from wall-clock time at ingest time. Override with `--tag v<TAG>`. Per-set files are sorted stably (card number, then title, then subtitle — never `localeCompare`) so identical upstream data produces byte-identical output on every run.
- **Progress**: ingest routinely runs past 30 seconds (thousands of pages). `src/progress.ts` writes `reports/.progress/ingest.json` (latest) and `.jsonl` (history) so the run is pollable without blocking.
- **Banned tokens**: `Date.now()`, `new Date(`, `Math.random()`, `.localeCompare()` are banned from `src/` — a write-time hook enforces this. Every timestamp used for tag derivation comes from the API's own `updatedAt` strings, compared and sliced as strings.

## Set selection at generate time

`src/index.ts` loads two independent card pools per run, each its own parse/dedupe pass (`loadCardPool` in `src/index.ts`):

- **Premier-legal-today pool** (feeds `aspect-set`, `aspect`, `alphabetical`): `formats.premier.sets ∩ files present`, `PREMIER_FILE_SET_PRECEDENCE` (`JTL, LOF, SEC, LAW, ASH, IBH`) filtered to codes that actually have a file on disk. `assertPremierSetCoverage` (in `src/transform.ts`, unchanged from the migrated original) checks that every Premier-legal set code lacking a per-set file is a known promo/dedupe code (`JTLP`, `LOFP`, `SECP`, `LAWP`, `ASHP`, `G25`, `P25`, `P26`).
- **Full-rotation-history pool** (feeds `set` only): `ROTATION_FILE_SET_PRECEDENCE` (`SOR, SHD, TWI, JTL, LOF, SEC, LAW, ASH, IBH`) filtered the same way. A fresh `npm run ingest` writes a file for every expansion the API returns (including the rotated-out `SOR`/`SHD`/`TWI`), so a fresh ingest's snapshot has both pools' files; the pinned `v2026-08-23` migration-proof snapshot only ever had the six current-premier files, so `set` targets the pinned `v2026-08-14` snapshot instead (see [Label sheet layouts](#label-sheet-layouts)).

## Template-driven label layout

The label's line content and order are controlled by `config.template` — an ordered array of `{ style, text }` lines, each `text` mixing literal characters with `{variable}` references (`{Title}`, `{cost_value}`, `{rarity_symbol}`, …) that collapse away automatically when their value is absent (this is how the Subtitle line vanishes for a subtitle-less card, and how a Base's stats line shows only HP). Full variable catalog, collapsing rules, and worked examples: [docs/template-language.md](docs/template-language.md). Every other `LabelLayoutConfig` knob (alignment, icon position, font sizes/auto-shrink, set ordering, the unique-card marker) is documented in [docs/configuration.md](docs/configuration.md), including the removal of the old `statsLinePosition` knob (superseded by template line order).

For the full ingest → generate → print sequence and the replay-record reproducibility contract, see [docs/pipeline.md](docs/pipeline.md).

## Rarity icons

Each label carries a rarity symbol (circle=Common, diamond=Uncommon, starburst=Rare, spiky starburst=Legendary, square=Special), matched by an embedded letter glyph (c/u/r/l/s). Two icon sets ship:

- **`assets/rarities/`** (default, `--assets color`) — the original color icons: rarity-specific hues (olive/gray/gold/blue) chosen for on-screen legibility.
- **`assets/rarities-bw/`** (`--assets bw`) — the same five icons, same geometry and silhouette shapes, with only the inner glyph's fill recolored solid black. Optimized for monochrome/B&W printing: the color set's hues (especially Uncommon's `#d6d6d6` light gray) convert to low-contrast, sometimes near-invisible grays at the ~0.14in print size; rarity stays distinguishable by outer silhouette shape plus the glyph even with color read out entirely.

## Layout

- Repo layout: `src/` (pipeline code), `test/` (Vitest suites + fixtures), `assets/rarities/` + `assets/rarities-bw/` (rarity SVGs, color and print-optimized monochrome), `data/snapshots/v<TAG>/` (pinned per-set JSON + `formats.json` + `meta.json`), `reports/` (generated DOCX + replay JSON land here; `.progress/` is gitignored).
- `docx` is pinned to the exact `9.7.1` patch version (not a caret range): `src/render.ts` reaches into `ImageRun`'s internal `root[0]` to inject a `w:position` baseline shift, verified against that exact version's `node_modules/docx/dist/index.mjs` — a minor/patch bump could silently change that internal shape.
