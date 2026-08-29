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
import { buildDocument, loadRarityAssets } from './render.ts'
import { CardArraySchema, FormatsManifestSchema } from './schema.ts'
import type { Card } from './schema.ts'
import type { LabelSlot } from './transform.ts'
import {
	PREMIER_FILE_SET_PRECEDENCE,
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
const ASSETS_DIR = join(REPO_ROOT, 'assets', 'rarities')

function sha256File(path: string): string {
	return createHash('sha256').update(readFileSync(path)).digest('hex')
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
 * @displayName Label Sheet Group Mode
 * @strategicPurpose Three distinct organizational layouts a user may want printed
 *   ('aspect-set' is the original v2/v3 combined layout, kept as the default so
 *   existing tooling/filenames are unaffected): by premier-legal set, by aspect
 *   color only, and pure alphabetical with no section breaks.
 * @tacticalObjective Selects which `transform.ts` grouping function `main()` calls
 *   and which output-filename suffix is used.
 */
export type GroupMode = 'aspect-set' | 'set' | 'aspect' | 'alphabetical'

const GROUP_MODES: readonly GroupMode[] = ['aspect-set', 'set', 'aspect', 'alphabetical']

const FILENAME_SUFFIX: Record<GroupMode, string> = {
	'aspect-set': '',
	set: '-by-set',
	aspect: '-by-aspect',
	alphabetical: '-alphabetical',
}

/**
 * @displayName Parse Groups CLI Arg
 * @strategicPurpose `npm run generate -- --groups set,aspect` must select which of
 *   the three (or all four, including the legacy combined layout) sheet layouts to
 *   emit in one run, without a code change.
 * @tacticalObjective Reads `--groups <value>` from argv as a comma-separated list of
 *   {@link GroupMode}, or the literal `all` for all four; defaults to `['aspect-set']`
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
			// name / per-aspect "x/y cards" breakdown) ahead of each aspect's cards.
			return groupBySetWithDividers(kept, DEFAULT_CONFIG)
		case 'alphabetical': {
			const groups = groupAlphabetically(kept)
			return new Map([...groups].map(([key, cards]) => [key, toCardSlots(cards)] as const))
		}
	}
}

async function main(): Promise<void> {
	const snapshotTag = parseSnapshotArg(process.argv.slice(2))
	const groupModes = parseGroupsArg(process.argv.slice(2))
	const DATA_DIR = join(REPO_ROOT, 'data', 'snapshots', snapshotTag)

	if (!existsSync(DATA_DIR)) {
		throw new Error(`index: snapshot directory not found: ${DATA_DIR}`)
	}

	const formatsRaw = JSON.parse(readFileSync(join(DATA_DIR, 'formats.json'), 'utf8'))
	const formats = FormatsManifestSchema.parse(formatsRaw)
	const premierSets = formats.formats.premier.sets

	// The ingest emits a per-set file for EVERY expansion the upstream API returns
	// (SOR, SHD, TWI, C24, TS26, ...), not just the six PREMIER_FILE_SET_PRECEDENCE
	// codes the original pinned snapshot happened to cover. Selection is
	// formats.premier.sets ∩ files present: a file for a non-premier-legal code
	// (e.g. SOR) is simply skipped, never asserted against. assertPremierSetCoverage
	// keeps its original exact-six-file contract (migrated test unchanged) — we
	// satisfy that contract by narrowing "available" to PREMIER_FILE_SET_PRECEDENCE
	// codes actually present on disk before calling it, so extra non-premier files
	// never reach the assertion.
	const perSetDir = join(DATA_DIR, 'per-set')
	const allAvailableSetCodes = new Set(
		readdirSync(perSetDir)
			.filter((f) => f.endsWith('.json'))
			.map((f) => f.slice(0, -'.json'.length)),
	)

	const setsToLoad = PREMIER_FILE_SET_PRECEDENCE.filter((set) => allAvailableSetCodes.has(set))

	assertPremierSetCoverage(premierSets, setsToLoad)

	const inputRelPaths = [
		'formats.json',
		'meta.json',
		...setsToLoad.map((set) => join('per-set', `${set}.json`)),
	]
	const inputHashes: Record<string, string> = {}
	for (const rel of inputRelPaths) {
		inputHashes[rel] = sha256File(join(DATA_DIR, rel))
	}

	let parsedCount = 0
	const cardsInPrecedenceOrder: Card[] = []
	for (const set of setsToLoad) {
		const raw = JSON.parse(readFileSync(join(DATA_DIR, 'per-set', `${set}.json`), 'utf8'))
		const parsed = CardArraySchema.parse(raw)
		parsedCount += parsed.length
		cardsInPrecedenceOrder.push(...parsed)
	}

	const { kept, droppedCount } = dedupeCards(cardsInPrecedenceOrder)
	if (kept.length !== parsedCount - droppedCount) {
		throw new Error('index: dedupe accounting mismatch (kept + dropped != parsed)')
	}
	if (kept.length < 1200 || kept.length > 1450) {
		throw new Error(
			`index: deduped total ${kept.length} is outside the expected 1200-1450 magnitude — stopping instead of shipping.`,
		)
	}

	let codeCommit = 'unknown'
	try {
		codeCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO_ROOT }).toString().trim()
	} catch {
		// Repo may have zero commits at generate-time (fresh git init); non-fatal.
	}

	const assets = await loadRarityAssets(ASSETS_DIR)

	for (const mode of groupModes) {
		const groups = buildGroupsForMode(mode, kept)

		let totalLabels = 0
		for (const slots of groups.values()) {
			totalLabels += slots.filter((s) => s.kind === 'card').length
		}
		if (totalLabels !== kept.length) {
			throw new Error(
				`index: mode '${mode}': total labels across groups (${totalLabels}) does not equal deduped total (${kept.length})`,
			)
		}

		const suffix = FILENAME_SUFFIX[mode]
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
			inputs: inputHashes,
			codeCommit,
			documentXmlSha256,
			totals: { parsed: parsedCount, deduped: kept.length, dropped: droppedCount },
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
