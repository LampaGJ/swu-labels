import { execFileSync } from 'node:child_process'
// @manipulation Pipeline entry point for the premier-labels manipulation node (see
// transform.ts header). Reads a pinned snapshot, parses at the boundary (schema.ts),
// transforms (transform.ts), renders (render.ts), and writes a replay record so the
// run is reproducible: {inputHash, codeCommit, outputHash}.
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Packer } from 'docx'
import { DEFAULT_CONFIG } from './config.ts'
import { buildSheetPlan, canonicalJSONStringify } from './plan.ts'
import { buildDocument, loadRarityAssets } from './render.ts'
import { CardArraySchema, FormatsManifestSchema } from './schema.ts'
import type { Card } from './schema.ts'
import type { LabelSlot } from './transform.ts'
import {
	PREMIER_FILE_SET_PRECEDENCE,
	ROTATION_FILE_SET_PRECEDENCE,
	assertPremierSetCoverage,
	dedupeCards,
	groupAlphabetically,
	groupByAspectOnly,
	groupByAspectThenSet,
	groupBySetWithDividers,
	toCardSlots,
} from './transform.ts'

const LAYOUT_VERSION = 'v3-named-styles-title-subtitle-stats'

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')

function sha256File(path: string): string {
	return createHash('sha256').update(readFileSync(path)).digest('hex')
}

/**
 * @displayName Rarity Icon Set
 * @strategicPurpose The Avery labels are print output, most often to a monochrome
 *   printer — the shipped `assets/rarities/*.svg` icons carry rarity-specific hues
 *   (olive/gray/gold/blue) chosen for on-screen legibility that convert to
 *   low-contrast, sometimes near-invisible grays at the ~0.14in print size (the
 *   uncommon icon's #d6d6d6 inner glyph is the worst case). `assets/rarities-bw/`
 *   is the same five icons with only the inner-glyph fill recolored solid black —
 *   geometry, silhouette shape (circle/diamond/starburst/spiky-starburst/square),
 *   and the letter glyph are unchanged, so rarity stays distinguishable by shape
 *   even with color read out entirely.
 * @tacticalObjective Selects which `assets/rarities` variant directory `main()` loads.
 */
export type AssetsMode = 'color' | 'bw'

const ASSETS_DIR_NAME: Record<AssetsMode, string> = {
	color: 'rarities',
	bw: 'rarities-bw',
}

const ASSETS_FILENAME_SUFFIX: Record<AssetsMode, string> = {
	color: '',
	bw: '-bw',
}

/**
 * @displayName Parse Assets CLI Arg
 * @strategicPurpose `npm run generate -- --assets bw` must select the
 *   print-optimized monochrome rarity icon set instead of the color one, without a
 *   code change.
 * @tacticalObjective Reads `--assets <color|bw>` from argv; defaults to `'color'`
 *   (unchanged behavior) when absent. Throws on an unrecognized value.
 */
export function parseAssetsArg(argv: readonly string[]): AssetsMode {
	const flagIndex = argv.indexOf('--assets')
	if (flagIndex === -1 || !argv[flagIndex + 1]) {
		return 'color'
	}
	const value = argv[flagIndex + 1] as string
	if (value !== 'color' && value !== 'bw') {
		throw new Error(`parseAssetsArg: unrecognized --assets value "${value}" (expected color or bw)`)
	}
	return value
}

/**
 * @displayName Parse Snapshot CLI Arg
 * @strategicPurpose `npm run generate -- --snapshot v<TAG>` must be able to target
 *   any ingested snapshot, not just the pinned migration-proof one, without a code
 *   change — the snapshot directory name is data, not a constant.
 * @tacticalObjective Reads `--snapshot <value>` from argv; defaults to 'v2026-08-23'
 *   (the pinned migration-proof snapshot) when absent.
 */
export function parseSnapshotArg(argv: readonly string[]): string {
	const flagIndex = argv.indexOf('--snapshot')
	if (flagIndex !== -1 && argv[flagIndex + 1]) {
		return argv[flagIndex + 1] as string
	}
	return 'v2026-08-23'
}

/**
 * @displayName Parse Sets CLI Arg
 * @strategicPurpose A user may want a sheet scoped to a specific handful of sets
 *   (e.g. only the three rotated-out sets, or only two adjacent current sets)
 *   rather than every set the chosen `--groups` mode's pool covers, without a
 *   code change or a one-off script per combination.
 * @tacticalObjective Reads `--sets <CODE,CODE,...>` from argv as a comma-separated
 *   list of set codes (order irrelevant — the grouping functions impose their own
 *   precedence order); returns `null` when absent, meaning "every set the pool
 *   covers" (unchanged behavior). Does not validate codes here — `main()` checks
 *   each requested code actually has a file in the targeted pool, since only it
 *   knows which pool (premier-legal-today vs full-rotation) is in play.
 */
export function parseSetsArg(argv: readonly string[]): string[] | null {
	const flagIndex = argv.indexOf('--sets')
	if (flagIndex === -1 || !argv[flagIndex + 1]) {
		return null
	}
	return (argv[flagIndex + 1] as string).split(',').map((s) => s.trim())
}

/**
 * @displayName Parse Emit-Plan CLI Arg
 * @strategicPurpose The Swift port's fidelity gate needs this generator's own
 *   answer to "what goes in every cell", captured before docx serialization.
 *   Emitting it is opt-in so no existing invocation changes behavior or output:
 *   without the flag, every byte this generator writes is what it always wrote.
 * @tacticalObjective True when `--emit-plan` appears in argv. A run with the
 *   flag writes an additional `<basename>.plan.json` beside the DOCX.
 */
export function parseEmitPlanArg(argv: readonly string[]): boolean {
	return argv.includes('--emit-plan')
}

/**
 * @displayName Parse Plan-Only CLI Arg
 * @strategicPurpose The Swift port's fidelity gate needs only the plan, but a
 *   plain `--emit-plan` run also rewrites every DOCX and replay record. Those are
 *   tracked files, so running the gate left the working tree dirty with artifacts
 *   whose content had not actually changed — noise that trains a reader to ignore
 *   `git status`. With this flag the gate is side-effect-free on tracked files.
 * @tacticalObjective True when `--plan-only` appears in argv. Meaningful only
 *   alongside `--emit-plan`; it suppresses the DOCX and replay writes, leaving
 *   every other behavior untouched.
 */
export function parsePlanOnlyArg(argv: readonly string[]): boolean {
	return argv.includes('--plan-only')
}

/**
 * @displayName Label Sheet Group Mode
 * @strategicPurpose Five distinct organizational layouts a user may want printed
 *   ('aspect-set' is the original v2/v3 combined layout, kept as the default so
 *   existing tooling/filenames are unaffected): by premier-legal set, by aspect
 *   color only, pure alphabetical with no section breaks, by premier-legal set
 *   then aspect (with divider labels), and by full-rotation-history aspect then
 *   set — the same aspect-then-set shape as the default, but scoped to the
 *   full-rotation-history pool (SOR/SHD/TWI included) instead of premier-legal-today.
 * @tacticalObjective Selects which `transform.ts` grouping function `main()` calls
 *   and which output-filename suffix is used.
 */
export type GroupMode = 'aspect-set' | 'set' | 'aspect' | 'alphabetical' | 'rotation-aspect-set'

const GROUP_MODES: readonly GroupMode[] = [
	'aspect-set',
	'set',
	'aspect',
	'alphabetical',
	'rotation-aspect-set',
]

const FILENAME_SUFFIX: Record<GroupMode, string> = {
	'aspect-set': '',
	set: '-by-set',
	aspect: '-by-aspect',
	alphabetical: '-alphabetical',
	'rotation-aspect-set': '-rotation-by-aspect-by-set',
}

/** Group modes that read the full-rotation-history pool (SOR/SHD/TWI included) instead of the premier-legal-today pool. */
const ROTATION_POOL_MODES: readonly GroupMode[] = ['set', 'rotation-aspect-set']

/**
 * @displayName Parse Groups CLI Arg
 * @strategicPurpose `npm run generate -- --groups set,aspect` must select which of
 *   the five (or all five, including the legacy combined layout) sheet layouts to
 *   emit in one run, without a code change.
 * @tacticalObjective Reads `--groups <value>` from argv as a comma-separated list of
 *   {@link GroupMode}, or the literal `all` for all five; defaults to `['aspect-set']`
 *   (unchanged behavior) when absent. Throws on an unrecognized mode name.
 */
export function parseGroupsArg(argv: readonly string[]): GroupMode[] {
	const flagIndex = argv.indexOf('--groups')
	if (flagIndex === -1 || !argv[flagIndex + 1]) {
		return ['aspect-set']
	}
	const value = argv[flagIndex + 1] as string
	if (value === 'all') {
		return [...GROUP_MODES]
	}
	const requested = value.split(',').map((s) => s.trim())
	for (const mode of requested) {
		if (!(GROUP_MODES as readonly string[]).includes(mode)) {
			throw new Error(
				`parseGroupsArg: unrecognized --groups mode "${mode}" (expected one of ${GROUP_MODES.join(', ')}, or "all")`,
			)
		}
	}
	return requested as GroupMode[]
}

/**
 * @displayName Build Groups For Mode
 * @strategicPurpose Central dispatch from a {@link GroupMode} to the `transform.ts`
 *   grouping function that implements it, so `main()`'s per-mode loop stays a
 *   one-line call regardless of how many layouts exist.
 * @tacticalObjective Exhaustively switch-typed over `GroupMode` — a new mode value
 *   is a compile error here, not a silent fallthrough.
 */
function buildGroupsForMode(mode: GroupMode, kept: readonly Card[]): Map<string, LabelSlot[]> {
	switch (mode) {
		case 'aspect-set': {
			const groups = groupByAspectThenSet(kept, DEFAULT_CONFIG)
			return new Map([...groups].map(([key, cards]) => [key, toCardSlots(cards)] as const))
		}
		case 'aspect': {
			const groups = groupByAspectOnly(kept)
			return new Map([...groups].map(([key, cards]) => [key, toCardSlots(cards)] as const))
		}
		case 'set':
			// The only mode whose sections carry divider slots (set code / full
			// name / per-aspect "x/y cards" breakdown) ahead of each aspect's cards,
			// and the only mode fed the full-rotation-history pool/precedence — the
			// caller passes `kept` built from ROTATION_FILE_SET_PRECEDENCE.
			return groupBySetWithDividers(kept, DEFAULT_CONFIG, ROTATION_FILE_SET_PRECEDENCE)
		case 'alphabetical': {
			const groups = groupAlphabetically(kept)
			return new Map([...groups].map(([key, cards]) => [key, toCardSlots(cards)] as const))
		}
		case 'rotation-aspect-set': {
			// Same aspect-then-set shape as 'aspect-set', but the caller passes
			// `kept` built from ROTATION_FILE_SET_PRECEDENCE, so sets flow
			// SOR, SHD, TWI, JTL, ... within each aspect instead of stopping at
			// the six currently-legal sets.
			const groups = groupByAspectThenSet(kept, DEFAULT_CONFIG, ROTATION_FILE_SET_PRECEDENCE)
			return new Map([...groups].map(([key, cards]) => [key, toCardSlots(cards)] as const))
		}
	}
}

/**
 * @displayName Card Pool
 * @strategicPurpose Two of the four label layouts now read from genuinely different
 *   card pools: the three premier-legal-today layouts (aspect-set, aspect,
 *   alphabetical) read the same six-set pool as before (unchanged, byte-identical);
 *   the 'set' (full-rotation-history) layout reads a nine-set pool including the
 *   rotated-out SOR/SHD/TWI sets. Bundling one pool's parse/dedupe outputs into a
 *   typed shape keeps `main()`'s per-mode loop from re-deriving them inline twice.
 * @tacticalObjective Consumed by {@link loadCardPool} and `main()`.
 */
type CardPool = {
	kept: Card[]
	parsedCount: number
	droppedCount: number
	inputHashes: Record<string, string>
	setsToLoad: readonly string[]
}

/**
 * @displayName Load Card Pool
 * @strategicPurpose Parses, concatenates (in `setPrecedence` order), and dedupes
 *   exactly the per-set files present on disk for a given precedence list — the one
 *   piece of loading logic both the premier-legal-today pool and the full-rotation
 *   pool share, so `main()` calls it twice with two different precedence lists
 *   instead of duplicating the parse/dedupe/hash steps.
 * @tacticalObjective Reads `dataDir/per-set/<CODE>.json` for every `setPrecedence`
 *   code present in `dataDir/per-set/`, parses each at the boundary with
 *   {@link CardArraySchema}, concatenates in precedence order, and dedupes via
 *   {@link dedupeCards}. Throws on a kept+dropped accounting mismatch (a bug guard,
 *   not a data-quality check).
 */
function loadCardPool(dataDir: string, setPrecedence: readonly string[]): CardPool {
	const perSetDir = join(dataDir, 'per-set')
	const allAvailableSetCodes = new Set(
		readdirSync(perSetDir)
			.filter((f) => f.endsWith('.json'))
			.map((f) => f.slice(0, -'.json'.length)),
	)
	const setsToLoad = setPrecedence.filter((set) => allAvailableSetCodes.has(set))

	const inputHashes: Record<string, string> = {}
	for (const set of setsToLoad) {
		const rel = join('per-set', `${set}.json`)
		inputHashes[rel] = sha256File(join(dataDir, rel))
	}

	let parsedCount = 0
	const cardsInPrecedenceOrder: Card[] = []
	for (const set of setsToLoad) {
		const raw = JSON.parse(readFileSync(join(dataDir, 'per-set', `${set}.json`), 'utf8'))
		const parsed = CardArraySchema.parse(raw)
		parsedCount += parsed.length
		cardsInPrecedenceOrder.push(...parsed)
	}

	const { kept, droppedCount } = dedupeCards(cardsInPrecedenceOrder)
	if (kept.length !== parsedCount - droppedCount) {
		throw new Error('loadCardPool: dedupe accounting mismatch (kept + dropped != parsed)')
	}

	return { kept, parsedCount, droppedCount, inputHashes, setsToLoad }
}

/**
 * @displayName Replay Totals
 * @strategicPurpose A `--plan-only` run writes no replay record, but the parsed
 *   and deduped counts are the fast sanity check an operator reads to confirm the
 *   run covered what they expected. Printing them keeps that signal.
 * @tacticalObjective `{parsed, deduped, dropped}` for one mode's card pool.
 */
function replayTotals(
	pool: { parsedCount: number; droppedCount: number },
	modeCards: readonly Card[],
): { parsed: number; deduped: number; dropped: number } {
	return { parsed: pool.parsedCount, deduped: modeCards.length, dropped: pool.droppedCount }
}

async function main(): Promise<void> {
	const snapshotTag = parseSnapshotArg(process.argv.slice(2))
	const groupModes = parseGroupsArg(process.argv.slice(2))
	const assetsMode = parseAssetsArg(process.argv.slice(2))
	const setsFilter = parseSetsArg(process.argv.slice(2))
	const emitPlan = parseEmitPlanArg(process.argv.slice(2))
	const planOnly = parsePlanOnlyArg(process.argv.slice(2))
	const DATA_DIR = join(REPO_ROOT, 'data', 'snapshots', snapshotTag)
	const ASSETS_DIR = join(REPO_ROOT, 'assets', ASSETS_DIR_NAME[assetsMode])

	if (!existsSync(DATA_DIR)) {
		throw new Error(`index: snapshot directory not found: ${DATA_DIR}`)
	}

	const formatsRaw = JSON.parse(readFileSync(join(DATA_DIR, 'formats.json'), 'utf8'))
	const formats = FormatsManifestSchema.parse(formatsRaw)
	const premierSets = formats.formats.premier.sets

	const sharedInputHashes: Record<string, string> = {
		'formats.json': sha256File(join(DATA_DIR, 'formats.json')),
		'meta.json': sha256File(join(DATA_DIR, 'meta.json')),
	}

	// The premier-legal-today pool: unchanged from before this session's 'set'-mode
	// work — same six files, same assertPremierSetCoverage gate, same 1200-1450
	// magnitude guard — so the three non-'set' layouts stay byte-identical.
	const basePool = loadCardPool(DATA_DIR, PREMIER_FILE_SET_PRECEDENCE)
	assertPremierSetCoverage(premierSets, basePool.setsToLoad)
	if (basePool.kept.length < 1200 || basePool.kept.length > 1450) {
		throw new Error(
			`index: premier-legal-today deduped total ${basePool.kept.length} is outside the expected 1200-1450 magnitude — stopping instead of shipping.`,
		)
	}

	// The full-rotation-history pool only matters — and is only computed — when a
	// ROTATION_POOL_MODES layout was actually requested; loading it eagerly for
	// every invocation would mean every other mode pays a needless second
	// parse/dedupe pass.
	let rotationPool: CardPool | undefined
	if (groupModes.some((mode) => ROTATION_POOL_MODES.includes(mode))) {
		rotationPool = loadCardPool(DATA_DIR, ROTATION_FILE_SET_PRECEDENCE)
		const missingRotationSets = ['SOR', 'SHD', 'TWI'].filter(
			(code) => !rotationPool?.setsToLoad.includes(code),
		)
		if (missingRotationSets.length > 0) {
			throw new Error(
				`index: a full-rotation-history layout needs [${missingRotationSets.join(', ')}] but they have no per-set file under ${DATA_DIR}/per-set — run \`npm run ingest\` (it fetches every set the API returns) and target that snapshot with --snapshot.`,
			)
		}
		if (rotationPool.kept.length < 1800 || rotationPool.kept.length > 2800) {
			throw new Error(
				`index: full-rotation deduped total ${rotationPool.kept.length} is outside the expected 1800-2800 magnitude — stopping instead of shipping.`,
			)
		}
	}

	let codeCommit = 'unknown'
	try {
		codeCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO_ROOT }).toString().trim()
	} catch {
		// Repo may have zero commits at generate-time (fresh git init); non-fatal.
	}

	const assets = await loadRarityAssets(ASSETS_DIR)

	for (const mode of groupModes) {
		const pool = ROTATION_POOL_MODES.includes(mode) ? (rotationPool as CardPool) : basePool

		let modeCards: Card[] = pool.kept
		if (setsFilter) {
			const unavailable = setsFilter.filter((code) => !pool.setsToLoad.includes(code))
			if (unavailable.length > 0) {
				throw new Error(
					`index: mode '${mode}': --sets code(s) [${unavailable.join(', ')}] not in this mode's pool (available: ${pool.setsToLoad.join(', ')})`,
				)
			}
			modeCards = pool.kept.filter((c) => setsFilter.includes(c.expansion_code))
		}

		const groups = buildGroupsForMode(mode, modeCards)

		let totalLabels = 0
		for (const slots of groups.values()) {
			totalLabels += slots.filter((s) => s.kind === 'card').length
		}
		if (totalLabels !== modeCards.length) {
			throw new Error(
				`index: mode '${mode}': total labels across groups (${totalLabels}) does not equal deduped total (${modeCards.length})`,
			)
		}

		const setsFilterSuffix = setsFilter ? `-${setsFilter.join('-')}` : ''
		const suffix = FILENAME_SUFFIX[mode] + setsFilterSuffix + ASSETS_FILENAME_SUFFIX[assetsMode]
		const OUT_DOCX = join(
			REPO_ROOT,
			'reports',
			`premier-labels-avery5167-${snapshotTag}${suffix}.docx`,
		)
		const OUT_REPLAY = join(
			REPO_ROOT,
			'reports',
			`premier-labels-avery5167-${snapshotTag}${suffix}.replay.json`,
		)

		if (emitPlan) {
			const OUT_PLAN = join(
				REPO_ROOT,
				'reports',
				`premier-labels-avery5167-${snapshotTag}${suffix}.plan.json`,
			)
			mkdirSync(dirname(OUT_PLAN), { recursive: true })
			writeFileSync(OUT_PLAN, canonicalJSONStringify(buildSheetPlan(groups, DEFAULT_CONFIG)))
			console.log(`Wrote ${OUT_PLAN}`)
		}

		if (planOnly) {
			console.log(JSON.stringify(replayTotals(pool, modeCards)))
			continue
		}

		const doc = buildDocument(groups, assets, DEFAULT_CONFIG)
		const buffer = await Packer.toBuffer(doc)

		mkdirSync(dirname(OUT_DOCX), { recursive: true })
		writeFileSync(OUT_DOCX, buffer)

		const documentXmlBuffer = execFileSync('unzip', ['-p', OUT_DOCX, 'word/document.xml'], {
			maxBuffer: 1024 * 1024 * 256,
		})
		const documentXmlSha256 = createHash('sha256').update(documentXmlBuffer).digest('hex')

		const groupCounts: Record<string, number> = {}
		for (const [key, slots] of groups) {
			groupCounts[key] = slots.filter((s) => s.kind === 'card').length
		}

		const replay = {
			snapshot: snapshotTag,
			groupMode: mode,
			assetsMode,
			setsFilter,
			inputs: { ...sharedInputHashes, ...pool.inputHashes },
			codeCommit,
			documentXmlSha256,
			totals: { parsed: pool.parsedCount, deduped: modeCards.length, dropped: pool.droppedCount },
			groups: groupCounts,
			layout: LAYOUT_VERSION,
			config: DEFAULT_CONFIG,
			generator: 'src/index.ts',
		}
		writeFileSync(OUT_REPLAY, `${JSON.stringify(replay, null, 2)}\n`)

		console.log(`Wrote ${OUT_DOCX}`)
		console.log(`Wrote ${OUT_REPLAY}`)
		console.log(JSON.stringify(replay.totals))
		console.log(JSON.stringify(replay.groups))
	}
}

main().catch((err) => {
	console.error(err)
	process.exitCode = 1
})
