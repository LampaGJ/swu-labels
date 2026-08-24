# swu-labels

**What this answers:** how to go from the live Star Wars Unlimited card database to a printable sheet of Avery 5167 Premier-format card labels, and where every piece of this pipeline came from.

**TL;DR:** `npm install`, then `npm run ingest` (pulls the live card list), `npm run generate` (builds the DOCX from the newest ingest), `npm run open` (opens the newest DOCX). Print at 100% scale, no "fit to page." Print one test sheet before committing a full run.

## Quick start

- `npm install` — installs dependencies.
- `npm run pull-formats` — refreshes the vendored `formats.json` from its canonical home (optional; a copy already ships in this repo).
- `npm run ingest` — fetches every card from the official Star Wars Unlimited admin API, filters to canonical printings, and writes a new pinned snapshot under `data/snapshots/v<TAG>/`.
- `npm run generate` — reads a pinned snapshot (default: `v2026-08-23`, the migration-proof snapshot) and writes a DOCX + replay record to `reports/`. Target a different snapshot with `npm run generate -- --snapshot v<TAG>`.
- `npm run open` — opens the newest `reports/*.docx` in the default application (Word, Pages, LibreOffice).
- `npm run test` — runs the full test suite (migrated generator tests + new ingest tests).
- `npm run typecheck` — `tsc --noEmit`.
- `npm run lint` — `biome check src test`.

## Avery 5167 print guidance

- Avery 5167 is 0.5in x 1.75in labels, 80 per sheet (4 columns x 20 rows), on US Letter.
- Print at **100% scale**. Do **not** use "fit to page" or "shrink to fit" — either will misalign every label on the sheet.
- **Print one test sheet on plain paper first**, hold it up to a blank Avery 5167 sheet against a light source, and confirm alignment before loading actual labels.
- The document has one section per aspect group (Vigilance, Command, Aggression, Cunning, Villainy, Heroism, Neutral); each section starts a fresh sheet.

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

`src/index.ts` selects which per-set files to load as `formats.premier.sets ∩ files present`: `PREMIER_FILE_SET_PRECEDENCE` (`JTL, LOF, SEC, LAW, ASH, IBH`) filtered to codes that actually have a file on disk. A fresh `npm run ingest` writes a file for every expansion the API returns (including non-Premier sets like `SOR`, `SHD`, `TWI`) — those extra files are simply not selected, never asserted against. `assertPremierSetCoverage` (in `src/transform.ts`, unchanged from the migrated original) still checks that every Premier-legal set code lacking a per-set file is a known promo/dedupe code (`JTLP`, `LOFP`, `SECP`, `LAWP`, `ASHP`, `G25`, `P25`, `P26`).

## Template-driven label layout

The label's line content and order are controlled by `config.template` — an ordered array of `{ style, text }` lines, each `text` mixing literal characters with `{variable}` references (`{Title}`, `{cost_value}`, `{rarity_symbol}`, …) that collapse away automatically when their value is absent (this is how the Subtitle line vanishes for a subtitle-less card, and how a Base's stats line shows only HP). Full variable catalog, collapsing rules, and worked examples: [docs/template-language.md](docs/template-language.md). Every other `LabelLayoutConfig` knob (alignment, icon position, font sizes/auto-shrink, set ordering, the unique-card marker) is documented in [docs/configuration.md](docs/configuration.md), including the removal of the old `statsLinePosition` knob (superseded by template line order).

For the full ingest → generate → print sequence and the replay-record reproducibility contract, see [docs/pipeline.md](docs/pipeline.md).

## Layout

- Repo layout: `src/` (pipeline code), `test/` (Vitest suites + fixtures), `assets/rarities/` (rarity SVGs), `data/snapshots/v<TAG>/` (pinned per-set JSON + `formats.json` + `meta.json`), `reports/` (generated DOCX + replay JSON land here; `.progress/` is gitignored).
- `docx` is pinned to the exact `9.7.1` patch version (not a caret range): `src/render.ts` reaches into `ImageRun`'s internal `root[0]` to inject a `w:position` baseline shift, verified against that exact version's `node_modules/docx/dist/index.mjs` — a minor/patch bump could silently change that internal shape.
