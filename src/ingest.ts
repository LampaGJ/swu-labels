// @manipulation This module is the ingest manipulation node feeding the
// premier-labels pipeline (doctrine: reproducible-data-manipulation.md). In-schema:
// ApiPageResponseSchema (api-schema.ts, one per fetched page). Out-schema: Card[]
// (schema.ts CardSchema shape) bucketed per expansion code and written to
// data/snapshots/v<TAG>/per-set/<CODE>.json. Declared effect: reduces (canonical
// filter drops non-canonical variant/reprint rows) then preserves (map/sort/bucket
// carry every remaining card through unchanged in content).
//
// BANNED in this file (write-time hook enforced, doctrine: reproducible data
// manipulation): Date.now(), new Date(, Math.random(), localeCompare. Every
// timestamp used for TAG derivation is the API's own `updatedAt` ISO-8601 string,
// compared and sliced as a string — never constructed as a Date. Sort ties break
// on raw codepoint comparison (`<`/`>`), never `.localeCompare(...)`.
import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { type ApiCard, ApiPageResponseSchema } from './api-schema.ts'
import { progress } from './progress.ts'
import type { Card } from './schema.ts'

const BASE_URL = 'https://admin.starwarsunlimited.com/api/card-list'
const PAGE_SIZE = 100
const PAGE_CONCURRENCY = 3 // the API is fragile — mirrors retrieve-cards/src/sync.ts
const RETRY_ATTEMPTS = 5
const RETRY_DELAY_MS = 3000

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')

const POPULATE_FIELDS = [
	'expansion',
	'type',
	'rarity',
	'aspects',
	'aspectDuplicates',
	'variantOf',
	'reprintOf',
]

/**
 * @displayName Build Card-List Page URL
 * @strategicPurpose Requests exactly the relation fields this pipeline consumes —
 *   no art fields (artFront/artBack/artThumbnail), since label generation needs no
 *   images. type2, traits, arenas, and keywords are also omitted: unused by the
 *   Premier-label output shape.
 * @tacticalObjective Strapi-style `pagination[page]` / `pagination[pageSize]` /
 *   `populate[N]` query string.
 */
export function buildPageUrl(page: number): string {
	const params = new URLSearchParams()
	params.set('pagination[page]', String(page))
	params.set('pagination[pageSize]', String(PAGE_SIZE))
	POPULATE_FIELDS.forEach((field, i) => params.set(`populate[${i}]`, field))
	return `${BASE_URL}?${params.toString()}`
}

async function sleep(ms: number): Promise<void> {
	await new Promise((resolve) => setTimeout(resolve, ms))
}

/**
 * @displayName Fetch One Page With Retry
 * @strategicPurpose The admin API is fragile (per slicer2 sync.ts and this repo's
 *   own observation); a transient 5xx or network error must retry with backoff
 *   rather than aborting the whole ingest.
 * @tacticalObjective Up to RETRY_ATTEMPTS attempts, RETRY_DELAY_MS * attempt linear
 *   backoff, mirroring retrieve-cards/src/sync.ts's fetchPage exactly. Parses the
 *   response at the boundary with ApiPageResponseSchema before returning.
 */
export async function fetchPage(
	page: number,
	attempt = 1,
): Promise<ReturnType<typeof ApiPageResponseSchema.parse>> {
	try {
		const res = await fetch(buildPageUrl(page))
		if (!res.ok) {
			if (res.status >= 500 && attempt < RETRY_ATTEMPTS) {
				await sleep(RETRY_DELAY_MS * attempt)
				return fetchPage(page, attempt + 1)
			}
			throw new Error(`HTTP ${res.status} fetching page ${page}`)
		}
		const json = await res.json()
		return ApiPageResponseSchema.parse(json)
	} catch (err) {
		if (attempt < RETRY_ATTEMPTS && !(err instanceof Error && err.name === 'ZodError')) {
			await sleep(RETRY_DELAY_MS * attempt)
			return fetchPage(page, attempt + 1)
		}
		throw err
	}
}

async function fetchPool<T>(
	items: readonly T[],
	concurrency: number,
	fn: (item: T) => Promise<void>,
): Promise<void> {
	let i = 0
	const workers = Array.from({ length: concurrency }, async () => {
		while (i < items.length) {
			const idx = i
			i += 1
			await fn(items[idx] as T)
		}
	})
	await Promise.all(workers)
}

/**
 * @displayName Is Canonical Printing
 * @strategicPurpose Excludes only foil/alternate-art VARIANTS (`variantOf` set) —
 *   not `reprintOf`. Empirically verified against the live API (2026-08-24, cards
 *   "Repair" id 85/19846 and "Wampa" id 255/27844): when a Standard/Shadows/Twilight
 *   card is reprinted into a later set to survive Premier rotation, the reprint row
 *   has `reprintOf` pointing at the original and `variantOf` null — it is the
 *   correct printing to ship on THAT set's labels, not a duplicate to drop. Per
 *   slicer-dev CLAUDE.md, "the 'canonical' printing has both as NULL" identifies
 *   one card's single master identity across its whole print history (a DB-identity
 *   concern); it is not the rule for "which printing represents set X on a label
 *   sheet." Every genuine cross-set duplicate (the SOR original vs. its JTL/LOF/...
 *   reprint) is still collapsed to one label by transform.ts's `dedupeCards`, keyed
 *   on title|subtitle|type_name over `PREMIER_FILE_SET_PRECEDENCE` order — that is
 *   the correct place to resolve "which set's printing wins," not this filter.
 * @tacticalObjective True when `variantOf.data` is null, regardless of `reprintOf`.
 */
export function isCanonicalPrinting(apiCard: ApiCard): boolean {
	return apiCard.attributes.variantOf.data === null
}

/**
 * @displayName Map API Card To Snapshot Shape
 * @strategicPurpose Boundary-to-boundary translation: the Strapi relation-wrapped
 *   API shape (api-schema.ts) in, the pinned-snapshot Card shape (schema.ts) out —
 *   exactly the 12 fields the generator (transform.ts/render.ts) reads, dropping
 *   every upstream field the generator does not consume (art URLs, styled HTML,
 *   traits, keywords, arenas, ...).
 * @tacticalObjective `aspects[]` preserves the API's own relation order (already
 *   the ordered-unique set per aspectDuplicates being a same-aspect double-cost
 *   flag, not a distinct value — verified empirically: no pinned-snapshot card has
 *   a repeated aspect entry). Returns the Card plus the raw `updatedAt` string
 *   (consumed by tag derivation, dropped before the file is written).
 */
export function mapApiCardToSnapshotCard(apiCard: ApiCard): { card: Card; updatedAt: string } {
	const a = apiCard.attributes
	const expansionCode = a.expansion.data?.attributes.code
	if (!expansionCode) {
		throw new Error(`mapApiCardToSnapshotCard: card ${apiCard.id} has no expansion relation`)
	}
	const typeName = a.type.data?.attributes.name
	if (!typeName) {
		throw new Error(`mapApiCardToSnapshotCard: card ${apiCard.id} has no type relation`)
	}
	const rarityName = a.rarity.data?.attributes.name
	if (!rarityName) {
		throw new Error(`mapApiCardToSnapshotCard: card ${apiCard.id} has no rarity relation`)
	}
	const aspects = a.aspects.data.map((d) => d.attributes.name)

	const card: Card = {
		title: a.title,
		subtitle: a.subtitle,
		cost: a.cost,
		power: a.power,
		hp: a.hp,
		upgrade_power: a.upgradePower,
		upgrade_hp: a.upgradeHp,
		unique: a.unique,
		type_name: typeName,
		rarity: rarityName,
		expansion_code: expansionCode,
		aspects,
	}
	return { card, updatedAt: a.updatedAt }
}

/**
 * @displayName Derive Snapshot Tag From Data
 * @strategicPurpose Determinism doctrine: the snapshot tag must be a function of
 *   the ingested data, not of wall-clock time at ingest time — two ingests of
 *   identical upstream data on different days must produce the same tag (and
 *   therefore byte-identical output) unless the data itself changed.
 * @tacticalObjective Max of every card's `updatedAt` ISO-8601 string, compared
 *   lexicographically (valid for this fixed-width format — no Date construction
 *   needed), sliced to its `YYYY-MM-DD` prefix. Throws on an empty input rather
 *   than silently deriving `undefined`.
 */
export function deriveTagFromUpdatedAt(updatedAtValues: readonly string[]): string {
	if (updatedAtValues.length === 0) {
		throw new Error('deriveTagFromUpdatedAt: no cards to derive a tag from')
	}
	let max = updatedAtValues[0] as string
	for (const value of updatedAtValues) {
		if (value > max) max = value
	}
	return `v${max.slice(0, 10)}`
}

type SortableCard = Card & { cardNumberSortKey: number }

/**
 * @displayName Sort Cards Stably
 * @strategicPurpose Per-set files must be byte-identical across runs when the
 *   upstream data is unchanged, regardless of the order pages happened to arrive
 *   in under concurrent fetch. Fixed sort key eliminates fetch-order as a source of
 *   nondeterminism.
 * @tacticalObjective Primary key: card number ascending (absent card numbers sort
 *   last via `Number.POSITIVE_INFINITY`). Ties break on raw title, then raw
 *   subtitle, both compared by codepoint (`<`/`>`) — never `.localeCompare()`.
 */
export function sortCardsStably(cards: readonly SortableCard[]): SortableCard[] {
	return [...cards].sort((a, b) => {
		if (a.cardNumberSortKey !== b.cardNumberSortKey) {
			return a.cardNumberSortKey - b.cardNumberSortKey
		}
		if (a.title < b.title) return -1
		if (a.title > b.title) return 1
		const subA = a.subtitle ?? ''
		const subB = b.subtitle ?? ''
		if (subA < subB) return -1
		if (subA > subB) return 1
		return 0
	})
}

/**
 * @displayName Bucket Cards By Expansion
 * @strategicPurpose One output file per expansion code, per the repo layout
 *   (data/snapshots/v<TAG>/per-set/<CODE>.json) — every expansion the API returns,
 *   not only the six the original pinned snapshot happened to cover.
 * @tacticalObjective Map keyed by `expansion_code`, insertion order irrelevant
 *   (caller sorts before bucketing so each bucket is already stably ordered).
 */
export function bucketByExpansion(cards: readonly Card[]): Map<string, Card[]> {
	const buckets = new Map<string, Card[]>()
	for (const card of cards) {
		const bucket = buckets.get(card.expansion_code)
		if (bucket) {
			bucket.push(card)
		} else {
			buckets.set(card.expansion_code, [card])
		}
	}
	return buckets
}

function sha256String(text: string): string {
	return createHash('sha256').update(text).digest('hex')
}

/**
 * @displayName Parse Tag Override CLI Arg
 * @strategicPurpose Lets an operator pin a specific snapshot tag (e.g. to redo a
 *   failed ingest under the same tag, or to label a manual test run distinctly
 *   from the data-derived tag) without editing code.
 * @tacticalObjective Reads `--tag <value>` from argv; returns null when absent so
 *   the caller falls back to data-derived tag.
 */
export function parseTagArg(argv: readonly string[]): string | null {
	const flagIndex = argv.indexOf('--tag')
	if (flagIndex !== -1 && argv[flagIndex + 1]) {
		return argv[flagIndex + 1] as string
	}
	return null
}

async function main(): Promise<void> {
	const tagOverride = parseTagArg(process.argv.slice(2))

	const first = await fetchPage(1)
	const { pageCount, total } = first.meta.pagination
	console.log(`Total: ${total} cards across ${pageCount} pages`)

	const allApiCards: ApiCard[] = [...first.data]
	const p = progress('ingest', { total: pageCount })
	p.tick(1, { fetched: allApiCards.length })

	if (pageCount > 1) {
		const pages = Array.from({ length: pageCount - 1 }, (_, i) => i + 2)
		let pagesDone = 1
		await fetchPool(pages, PAGE_CONCURRENCY, async (page) => {
			const pageResponse = await fetchPage(page)
			allApiCards.push(...pageResponse.data)
			pagesDone += 1
			p.tick(pagesDone, { fetched: allApiCards.length })
		})
	}
	p.done({ fetched: allApiCards.length })
	console.log(`Fetched ${allApiCards.length} cards`)

	const canonical = allApiCards.filter(isCanonicalPrinting)
	// The message states the rule the code actually applies. It previously said
	// "variantOf and reprintOf both null", which is the narrower rule this
	// pipeline deliberately does NOT use (see isCanonicalPrinting) — a reader
	// checking the behaviour against the log would have been misled.
	console.log(`Canonical (variantOf null; reprints kept): ${canonical.length}`)

	const mapped = canonical.map(mapApiCardToSnapshotCard)
	const tag = tagOverride ?? deriveTagFromUpdatedAt(mapped.map((m) => m.updatedAt))
	console.log(`Derived tag: ${tag}`)

	const sortable: SortableCard[] = canonical.map((apiCard, i) => ({
		...(mapped[i] as { card: Card }).card,
		cardNumberSortKey: apiCard.attributes.cardNumber ?? Number.POSITIVE_INFINITY,
	}))
	const sorted = sortCardsStably(sortable)
	const finalCards: Card[] = sorted.map(({ cardNumberSortKey, ...card }) => card)

	const buckets = bucketByExpansion(finalCards)

	const DATA_DIR = join(REPO_ROOT, 'data', 'snapshots', tag)
	const PER_SET_DIR = join(DATA_DIR, 'per-set')
	mkdirSync(PER_SET_DIR, { recursive: true })

	const perSetCounts: Record<string, number> = {}
	const perSetSha256: Record<string, string> = {}
	const setCodes = [...buckets.keys()].sort()
	for (const code of setCodes) {
		const cards = buckets.get(code) as Card[]
		const text = `${JSON.stringify(cards, null, '\t')}\n`
		writeFileSync(join(PER_SET_DIR, `${code}.json`), text)
		perSetCounts[code] = cards.length
		perSetSha256[code] = sha256String(text)
	}

	const formatsSrc = readFileSync(join(REPO_ROOT, 'formats.json'), 'utf8')
	writeFileSync(join(DATA_DIR, 'formats.json'), formatsSrc)

	const meta = {
		tag,
		schema_version: 1,
		source_url: BASE_URL,
		total_cards_fetched: allApiCards.length,
		canonical_cards: canonical.length,
		sets: setCodes,
		set_counts: perSetCounts,
		set_sha256: perSetSha256,
	}
	writeFileSync(join(DATA_DIR, 'meta.json'), `${JSON.stringify(meta, null, '\t')}\n`)

	console.log(`Wrote ${DATA_DIR}`)
	console.log(
		JSON.stringify({ tag, total_cards_fetched: allApiCards.length, canonical: canonical.length }),
	)
	console.log(JSON.stringify(perSetCounts))
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url)
if (isMain) {
	main().catch((err) => {
		console.error(err)
		process.exitCode = 1
	})
}
