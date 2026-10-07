# swu-labels — native app

**What this answers:** how the Swift app and CLI relate to the TypeScript generator in the parent directory, how to build and run them, and what proves the two produce the same sheet.

**TL;DR:** `make run` builds and launches `SWULabels.app`. The bundle carries a second binary, `Contents/MacOS/swu-labels`, which is the same functionality on the command line. `make gate` proves this port puts the same content in the same label cell as the TypeScript generator that was validated on printed stock.

## Quick start

- `make run` — build and launch the app.
- `make check` — compile only. The fast gate.
- `make test` — the Swift test suite.
- `make gate` — regenerate the reference sheet plans from the TypeScript generator, then run the full fidelity suite. **This is the one to run after touching layout, template or geometry code.**
- `make dist` — signed, notarized, stapled release zip. Needs a Developer ID and an exact `vX.Y.Z` tag.

Requires macOS 14+ and a Swift 6 toolchain. `make run` signs ad hoc, so it works with no certificates.

## The dual binary

```
SWULabels.app/Contents/
  MacOS/SWULabels        the GUI
  MacOS/swu-labels       the CLI
  Resources/assets       rarity icons
  Resources/data         pinned snapshots
```

The CLI ships **inside** the bundle so one code signature and one notarization ticket cover both binaries; shipped separately it would need its own of each. Both resolve content from `Contents/Resources` first, so a bundle copied to another machine still works. **Install Command Line Tool…** in the app menu shows the one-line `ln -s` that puts it on `PATH` — the app does not write to `/usr/local/bin` itself, because that needs privileges it should not ask for.

CLI subcommands: `generate` (label PDF), `plan` (the fidelity-gate artifact), `ingest`, `art` and `proxy` (card proxies), `alignment-sheet`, `snapshots`, `install-cli`.

## Layering

| Target | Depends on | Contains |
|---|---|---|
| `SWULabelsCore` | Foundation, CryptoKit | model, ingest, transform, template engine, planner |
| `SWULabelsRender` | Core, CoreGraphics/CoreText/PDFKit/ImageIO | SVG icon parsing, typesetting, art cache, PDF output |
| `SWULabelsDocx` | Core | secondary DOCX export (not yet implemented) |
| `SWULabelsUI` | Core, Render, SwiftUI | the entire interface |
| `swu-labels` | Core, Render, Docx | CLI executable, macOS |
| `SWULabelsApp` | UI | GUI shell, macOS |

The seam that matters is **`SheetPlan`**. Core decides *what goes in every cell*; Render decides *how it is drawn*. The app's live label preview draws through `SheetRenderer`, not through SwiftUI `Text` views — a preview that reimplemented the layout would drift from print output, and drift is the failure this design exists to prevent.

## Staying multiplatform

The interface lives in a **library** target, so an iPad or iPhone app is a new ~25-line executable wrapping the same `RootView`, not a fork. `Package.swift` already declares `.iOS(.v17)`.

The whole codebase contains four `#if os(macOS)` blocks, all in `SWULabelsUI`: two in `PrintService` (`NSPrintOperation` versus `UIPrintInteractionController`) and two around the Install Command Line Tool item. `SWULabelsCore`, `SWULabelsRender`, `SWULabelsDocx` and the CLI import no UI framework at all.

Keep it that way: put platform code behind `PrintService`, and keep AppKit and UIKit out of Core and Render.

## What proves this port is correct

Three gates, each of which has been shown to fail on a deliberate defect.

**Gate 1 — content parity.** `npx tsx src/index.ts --groups <mode> --emit-plan` writes a `SheetPlan` from the data `render.ts` holds immediately before it builds DOCX objects. This port emits the same document, and `PlanParityTests` compares them cell for cell across all five layouts and both pinned snapshots. The chain: the reference generator's replay records pin a `documentXmlSha256` for a DOCX validated on real Avery stock, `--emit-plan` observes that generator without altering a byte of its output, and Gate 1 shows this port agrees with it.

**Gate 2 — print geometry.** `GeometryGateTests` renders the PDF, reads it back, and asserts every label lands on an inch grid stated **independently** of the app's own constants. Asserting against the constants the renderer used would pass no matter where the grid sat.

**Gate 4 — proxy card size.** `ProxyGeometryTests` asserts a proxy is exactly 63mm x 88mm against dimensions restated independently, checks the grid never overflows the paper and that cards never overlap, and pins the fact that the commonly quoted "2.5 x 3.5 inches" is a different, larger card.

**Gate 3 — ingest byte-identity.** `SnapshotSerializerTests` re-serializes every committed per-set file and requires byte equality. A live ingest run also reproduced `data/snapshots/v2026-08-14` byte for byte, `meta.json` digests included.

## Two determinism traps this port had to avoid

Both are silent, and both would have produced a plausible sheet with cards in the wrong places.

- **Swift's `String` `<` is not JavaScript's.** Swift compares by Unicode canonical equivalence over grapheme clusters; JavaScript compares UTF-16 code units, and calls "é" and "e\u{301}" different where Swift calls them equal. Every ordering decision goes through `UTF16Order`. `String.count` versus `String.length` is the same trap in the font-shrink thresholds, which is why those measure `utf16.count`.
- **Swift `Dictionary` iteration order is randomized per process.** Anywhere order reaches output, this port uses `OrderedBuckets` or a plain array. The TypeScript generator relies on `Map` insertion order in three places, every one of which is a conversion site.

## Proxy cards

`swu-labels proxy` prints card art at exact card size for playtesting.

```
swu-labels art --snapshot v2026-10-01        # once: index where the art lives
swu-labels proxy --sets LAW --copies 3       # then print
swu-labels proxy --deck mydeck.txt --page a4 # or from a deck list
```

In the app, switch the toolbar from **Labels** to **Proxies**; the card list and
its filters are shared, so whatever the browser is showing is what prints.

**Card size is 63mm x 88mm and is not a setting.** A proxy even a millimetre off
will not sleeve alongside real cards, and a deck holding one odd-sized card is
marked from the back. `ProxyGeometryTests` gates that against dimensions stated
independently of the app's own constants, the same way the Avery grid is gated.

Everything else is adjustable: paper (US Letter or A4), grid, gutter, page
margin, cut guides, and copies per card. A grid larger than the paper holds is
clamped rather than printed clipped, and the interface says when it clamped.

Landscape cards — Leaders and Bases — are rotated into the same portrait slot as
everything else, so the whole page cuts on one uniform grid. Turn the cut card to
read it, exactly as with a real Leader.

### Two things to know before a big run

**Art resolution is two-tier.** The official CDN serves roughly 289 DPI art for
the newest sets (LAW, ASH, P26, TS26) and roughly 121 DPI for everything older,
against a 300 DPI print standard. Older sets will look visibly soft and no
setting here changes that — the limit is the source image. Both the CLI and the
app report the median resolution for the exact cards selected, rather than
quoting one figure for the whole database.

**Art is a separate download.** It lives in `data/snapshots/<tag>/art.json`
(URLs, committed) with the images cached under `data/art-cache/` (gitignored;
a full set is several hundred megabytes). It is deliberately not a field on
`Card`: the per-set snapshot files are byte-exact artifacts whose digests are
recorded in every replay record, so adding a field the label pipeline never
reads would invalidate all of them.

## Before printing on real stock

Run `swu-labels alignment-sheet`, or use **Print Registration Sheet…** in the app. Print it at 100% on plain paper, hold it to a light against a blank sheet, and measure the ruler. Every automated gate here verifies the PDF; none can see what your printer actually puts on paper, and a driver that scales ruins all eighty labels at once.
