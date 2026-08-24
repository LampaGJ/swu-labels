---
type: runbook
status: active
related: [configuration.md, template-language.md]
---

**What this answers:** the end-to-end sequence to get from the live Star Wars Unlimited card database to a printed sheet of Avery 5167 Premier labels — every command, in order, and why each pinning/canonicalization decision is made where it is.

**TL;DR:** `npm run pull-formats` (optional, refreshes the vendored `formats.json`) → `npm run ingest` (writes a pinned, data-tagged snapshot) → `npm run generate` (reads a snapshot, writes a DOCX + replay record) → check the replay record's `documentXmlSha256` if you touched generator code → print one test sheet at 100% scale before a full run.

## 1. Ingest: fetch and pin a snapshot

```
npm run ingest
```

`src/ingest.ts` fetches every card from `https://admin.starwarsunlimited.com/api/card-list` (a paginated Strapi endpoint, 3 pages concurrent with retry) and parses every page at the boundary with `src/api-schema.ts` (Zod, closed on the fields this pipeline consumes).

**Canonicalization rule: `variantOf`-only, not `reprintOf`.** A card row is kept when `variantOf` is `null`, regardless of `reprintOf`. This excludes only foil/alternate-art *variants* of a printing. It deliberately does **not** exclude reprints: when a Standard/Shadows/Twilight-era card is reprinted into a later set to survive Premier-format rotation, that reprint row has `reprintOf` pointing at the original and `variantOf` null — and it is the correct printing to ship on *that set's* labels, not a duplicate to drop at ingest time. (Verified empirically against the live API, 2026-08-24, cards "Repair" id 85/19846 and "Wampa" id 255/27844.) The alternative, narrower rule some sources suggest — "canonical means both `variantOf` and `reprintOf` are null" — identifies one card's single master identity across its whole print history, a database-identity concern; it is the wrong rule for "which printing represents set X on a label sheet." Every genuine cross-set duplicate (a card's original set printing vs. its later reprint) is still collapsed to exactly one label — see step 3, `dedupeCards`.

**Determinism**: the snapshot tag is the `YYYY-MM-DD` of the maximum `updatedAt` across all ingested cards — derived from the data itself, never from wall-clock time at ingest time (`Date.now()`/`new Date(` are banned in `src/`, enforced by a write-time hook). Override with `--tag v<TAG>`. Per-set files are sorted stably (card number, then title, then subtitle, all by codepoint — never `.localeCompare()`), so identical upstream data produces a byte-identical snapshot on every run.

**Output**: `data/snapshots/v<TAG>/` — `formats.json` (copied in from the vendored root copy), `meta.json`, and `per-set/<CODE>.json` for every expansion the API returned.

**Progress**: ingest runs past 30 seconds (thousands of pages). `src/progress.ts` writes `reports/.progress/ingest.json` (latest snapshot) + `.jsonl` (history) so the run is pollable without blocking on terminal output.

## 2. formats.json vendoring

```
npm run pull-formats
```

`formats.json` — which set codes are legal in Premier today — is canonically maintained upstream (in the internal `slicer2/slicer-dev` project, `formats.json` at its root). A copy is vendored into this repo's root so the repo works standalone without that project present. `npm run pull-formats` re-pulls the canonical copy; run it before an ingest if Premier's legal-set list may have changed (a new set added, an old one rotated out). Edit the canonical file upstream, never this repo's vendored copy directly.

## 3. Generate: snapshot → DOCX + replay record

```
npm run generate                          # default snapshot: v2026-08-23
npm run generate -- --snapshot v<TAG>     # target a specific snapshot
```

`src/index.ts`:

1. Reads `formats.json` + every per-set file for a snapshot, parsing each at the boundary with `src/schema.ts` (Zod, closed on `rarity`/`aspects` enums — an unknown value throws rather than being coerced or defaulted away).
2. Selects which per-set files to load as `formats.premier.sets ∩ files present`: `PREMIER_FILE_SET_PRECEDENCE` (`JTL, LOF, SEC, LAW, ASH, IBH`) filtered to codes actually on disk. A fresh ingest writes a file for every expansion the API returns (including non-Premier sets like `SOR`, `SHD`, `TWI`) — those extras are simply not selected, never asserted against. `assertPremierSetCoverage` still checks every Premier-legal set lacking a per-set file is a known promo/dedupe code (`JTLP`, `LOFP`, `SECP`, `LAWP`, `ASHP`, `G25`, `P25`, `P26`).
3. Dedupes across sets (`dedupeCards`, keyed on `title|subtitle|type_name`, keep-first in `PREMIER_FILE_SET_PRECEDENCE` order) — this is where a card's original-set printing and its later reprint collapse to the single label the ingest step deliberately did not collapse.
4. Groups by aspect (`ASPECT_GROUP_ORDER`: Vigilance, Command, Aggression, Cunning, Villainy, Heroism, Neutral — one fresh Avery 5167 sheet per group), then by set within each aspect group (`config.setOrder`), then alphabetically by title.
5. Renders the DOCX (`src/render.ts`), using `config.template` to build each label's lines — see docs/template-language.md for the template language and docs/configuration.md for every other layout knob.
6. Writes `reports/premier-labels-avery5167-v<TAG>.docx` and a matching `.replay.json`.

## 4. The replay record: reproducibility proof

Every generate run writes `reports/premier-labels-avery5167-v<TAG>.replay.json`:

- **`inputs`** — SHA-256 of every input file read (`formats.json`, `meta.json`, each `per-set/*.json` actually loaded).
- **`codeCommit`** — the git commit `src/index.ts` ran at.
- **`documentXmlSha256`** — SHA-256 of the DOCX's inner `word/document.xml`, the single most sensitive artifact: any run-count, style-id, or text change anywhere in the generator changes this hash.
- **`totals`** / **`groups`** — card counts, for a fast sanity check without opening the DOCX.
- **`config`** — the full `LabelLayoutConfig` used, snapshotted verbatim (including `template`) — so the replay record alone tells you exactly what layout produced this file.

This is the `{inputHash, codeCommit, outputHash}` replay contract from the reproducible-data-manipulation doctrine: given the same pinned snapshot and the same commit, `npm run generate` reproduces a byte-identical `document.xml` every time. There is no automated CI gate for this in this repo — after any generator-code change, regenerate against the pinned `v2026-08-23` and `v2026-08-14` snapshots and confirm `documentXmlSha256` is unchanged (or, if the change was intentional, that the new hash is the one you expect and record it).

## 5. Print

```
npm run open   # opens the newest reports/*.docx
```

- Avery 5167: 0.5in x 1.75in labels, 80 per sheet (4 columns x 20 rows), on US Letter.
- Print at **100% scale**. Never "fit to page" or "shrink to fit" — either misaligns every label on the sheet.
- **Print one test sheet on plain paper first.** Hold it up to a blank Avery 5167 sheet against a light source and confirm alignment before loading actual labels.
- The document has one section per non-empty aspect group; each section starts a fresh sheet.
