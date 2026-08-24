// @manipulation This module is the manipulation node in the premier-labels pipeline
// (doctrine: ~/.claude/reproducible-data-manipulation.md). In-schema: CardSchema (schema.ts).
// Out-schema: Card[] grouped/sorted per ASPECT_GROUP_ORDER. Declared effects: dedupeCards
// reduces; groupByAspect/sortWithinGroup preserve (repartition/reorder, no drops). The replay
// record ({inputHash, codeCommit, outputHash}) is emitted by index.ts after every run.
import type { LabelLayoutConfig } from './config.ts'
import type { Card } from './schema.ts'

/**
 * @displayName Aspect Group Order
 * @strategicPurpose Fixes the fresh-sheet-per-aspect ordering the Avery 5167 label
 *   sheet must render in, matching the spec's exact seven-group sequence.
 * @tacticalObjective Ordered list consumed by {@link groupByAspect} and by render.ts
 *   to iterate sections in a deterministic, spec-pinned order.
 */
export const ASPECT_GROUP_ORDER = [
	'Vigilance',
	'Command',
	'Aggression',
	'Cunning',
	'Villainy',
	'Heroism',
	'Neutral',
] as const

export type AspectGroupKey = (typeof ASPECT_GROUP_ORDER)[number]

/**
 * @displayName Premier Per-Set File Precedence
 * @strategicPurpose Encodes the dedupe tie-break rule: when the same card appears
 *   in multiple pinned per-set files (main-set printing vs. Intro Battle reprint),
 *   the earlier set in this list wins.
 * @tacticalObjective Ordered list consumed by {@link dedupeCards}.
 */
export const PREMIER_FILE_SET_PRECEDENCE = ['JTL', 'LOF', 'SEC', 'LAW', 'ASH', 'IBH'] as const

/**
 * @displayName Avery 5167 Label Sheet Geometry
 * @strategicPurpose Pins the exact twips geometry for Avery 5167 (0.5in x 1.75in,
 *   80/sheet, 4 cols x 20 rows, US Letter) so the DOCX renderer never improvises a
 *   dimension — every number here is load-bearing for physical label alignment.
 * @tacticalObjective Constant geometry table consumed by render.ts.
 */
export const AVERY_5167_GEOMETRY = {
	page: { width: 12240, height: 15840 },
	margins: { top: 720, bottom: 576, left: 405, right: 405 },
	columnWidths: [2520, 450, 2520, 450, 2520, 450, 2520],
	rowHeightExact: 720,
	rowsPerSheet: 20,
	labelColumnIndices: [0, 2, 4, 6],
} as const

const COMBINING_MARKS_PATTERN = /\p{Mn}/gu

/**
 * @displayName Fold Sort Key
 * @strategicPurpose Deterministic, locale-independent sort key so label ordering
 *   is byte-identical on every run and every machine. The locale-aware string
 *   comparison built into JS strings is banned by the reproducible-data doctrine
 *   because its result depends on the host ICU locale data.
 * @tacticalObjective NFD-normalizes `title + ' ' + (subtitle ?? '')`, strips combining
 *   marks, lowercases. Compared by raw codepoint (`<`/`>`) by the caller.
 */
export function foldSortKey(title: string, subtitle: string | null): string {
	return `${title} ${subtitle ?? ''}`
		.normalize('NFD')
		.replace(COMBINING_MARKS_PATTERN, '')
		.toLowerCase()
}

/**
 * @displayName Sort Within Aspect Group
 * @strategicPurpose Alphabetical-by-title label ordering within one aspect group,
 *   deterministic and reproducible (no locale-aware string comparison).
 * @tacticalObjective Non-mutating sort by {@link foldSortKey}, codepoint-compared;
 *   ties break on raw `title` then raw `subtitle`.
 */
export function sortWithinGroup(cards: readonly Card[]): Card[] {
	return [...cards].sort((a, b) => {
		const keyA = foldSortKey(a.title, a.subtitle)
		const keyB = foldSortKey(b.title, b.subtitle)
		if (keyA < keyB) return -1
		if (keyA > keyB) return 1
		if (a.title < b.title) return -1
		if (a.title > b.title) return 1
		const subA = a.subtitle ?? ''
		const subB = b.subtitle ?? ''
		if (subA < subB) return -1
		if (subA > subB) return 1
		return 0
	})
}

function dedupeKey(card: Card): string {
	return `${card.title}|${card.subtitle ?? ''}|${card.type_name}`
}

/**
 * @displayName Dedupe Cards Across Sets
 * @strategicPurpose Declared effect: reduces. The pinned per-set files independently
 *   include reprints (main-set printing + Intro Battle Halcyon reprint); the label
 *   sheet must list each unique card once, keyed to the canonical (earliest-in-
 *   precedence) printing.
 * @tacticalObjective Keep-first dedupe keyed on `title|subtitle ?? ''|type_name`,
 *   with `PREMIER_FILE_SET_PRECEDENCE` applied by the caller's input ordering
 *   (cards must already be concatenated in set-precedence order). Returns kept
 *   cards plus a dropped count for the replay record.
 */
export function dedupeCards(cardsInPrecedenceOrder: readonly Card[]): {
	kept: Card[]
	droppedCount: number
} {
	const seen = new Set<string>()
	const kept: Card[] = []
	let droppedCount = 0
	for (const card of cardsInPrecedenceOrder) {
		const key = dedupeKey(card)
		if (seen.has(key)) {
			droppedCount += 1
			continue
		}
		seen.add(key)
		kept.push(card)
	}
	return { kept, droppedCount }
}

/**
 * @displayName Group Cards By Primary Aspect
 * @strategicPurpose Each aspect group starts on a fresh label sheet; grouping must
 *   fail loudly rather than silently drop a card under an unrecognized aspect key.
 * @tacticalObjective Groups by `aspects[0] ?? 'Neutral'`; throws if any resulting
 *   group key is not a member of {@link ASPECT_GROUP_ORDER}. Returns a Map ordered
 *   per `ASPECT_GROUP_ORDER`, omitting empty groups.
 */
export function groupByAspect(cards: readonly Card[]): Map<AspectGroupKey, Card[]> {
	const buckets = new Map<string, Card[]>()
	for (const card of cards) {
		const key = card.aspects[0] ?? 'Neutral'
		const bucket = buckets.get(key)
		if (bucket) {
			bucket.push(card)
		} else {
			buckets.set(key, [card])
		}
	}
	for (const key of buckets.keys()) {
		if (!(ASPECT_GROUP_ORDER as readonly string[]).includes(key)) {
			throw new Error(`groupByAspect: unrecognized aspect group key "${key}"`)
		}
	}
	const ordered = new Map<AspectGroupKey, Card[]>()
	for (const key of ASPECT_GROUP_ORDER) {
		const bucket = buckets.get(key)
		if (bucket && bucket.length > 0) {
			ordered.set(key, bucket)
		}
	}
	return ordered
}

const KNOWN_PROMO_DEDUPE_CODES = new Set([
	'JTLP',
	'LOFP',
	'SECP',
	'LAWP',
	'ASHP',
	'G25',
	'P25',
	'P26',
])

/**
 * @displayName Assert Premier Set Coverage
 * @strategicPurpose Guards the input-selection step: the pinned formats.json names
 *   sets legal in Premier, but only six carry a standalone per-set JSON file in this
 *   snapshot — the rest are promo/dedupe printings folded into those six. A silent
 *   mismatch here (a new set added upstream with no file, or a missing main-set file)
 *   would produce a label sheet that looks complete but is quietly wrong.
 * @tacticalObjective Throws unless every premier set lacking a per-set file is a
 *   known promo/dedupe code, and the set of available per-set files is exactly
 *   {JTL, LOF, SEC, LAW, ASH, IBH}.
 */
export function assertPremierSetCoverage(
	premierSets: readonly string[],
	availableSetCodes: readonly string[],
): void {
	const available = new Set(availableSetCodes)
	const withoutFile = premierSets.filter((set) => !available.has(set))
	const unexpectedWithoutFile = withoutFile.filter((set) => !KNOWN_PROMO_DEDUPE_CODES.has(set))
	if (unexpectedWithoutFile.length > 0) {
		throw new Error(
			`assertPremierSetCoverage: premier sets without a per-set file are not known promo codes: ${unexpectedWithoutFile.join(', ')}`,
		)
	}
	const expectedFileSets = [...PREMIER_FILE_SET_PRECEDENCE].sort()
	const actualFileSets = [...availableSetCodes].sort()
	const matches =
		expectedFileSets.length === actualFileSets.length &&
		expectedFileSets.every((set, i) => set === actualFileSets[i])
	if (!matches) {
		throw new Error(
			`assertPremierSetCoverage: available per-set files [${actualFileSets.join(', ')}] are not exactly [${expectedFileSets.join(', ')}]`,
		)
	}
}

/**
 * @displayName Stat Line Segment
 * @strategicPurpose Typed shape the renderer consumes to bold the numeric value
 *   while leaving the suffix word regular weight, per the v2 stat-line spec.
 * @tacticalObjective `bold` is the literal run text for the numeric portion
 *   (may carry a `/` and `+` for the pilot dual-stat and plain-upgrade shapes);
 *   `suffix` is the exact trailing word (`cost`, `power`, or `HP`).
 */
export type StatLineSegment = {
	bold: string
	suffix: 'cost' | 'power' | 'HP'
}

function buildStatSegment(
	unitValue: number | null | undefined,
	upgradeValue: number | null | undefined,
	suffix: 'power' | 'HP',
): StatLineSegment | null {
	const unit = unitValue ?? null
	const upgrade = upgradeValue ?? null
	if (unit !== null && upgrade !== null) {
		return { bold: `${unit}/${upgrade}+`, suffix }
	}
	if (unit !== null) {
		return { bold: String(unit), suffix }
	}
	if (upgrade !== null) {
		return { bold: `+${upgrade}`, suffix }
	}
	return null
}

/**
 * @displayName Build Stat Line Segments
 * @strategicPurpose Data-driven line-1 content: a Base shows only HP, an Event
 *   shows only cost, a Credit Token shows none — because the field is null,
 *   never because of a `type_name` special case. Also covers the two upgrade
 *   shapes: a plain Upgrade (unit power/hp null, upgrade_power/upgrade_hp set)
 *   renders `+N`; a JTL-era Pilot unit (both unit AND upgrade stats non-null)
 *   renders `{unit}/{upgrade}+` for that field, independently per field.
 * @tacticalObjective Returns segments in fixed order [cost, power, hp], omitting
 *   any field where both the unit value and the upgrade value are null.
 */
export function buildStatLineSegments(card: Card): StatLineSegment[] {
	const segments: StatLineSegment[] = []
	if (card.cost !== null && card.cost !== undefined) {
		segments.push({ bold: String(card.cost), suffix: 'cost' })
	}
	const power = buildStatSegment(card.power, card.upgrade_power, 'power')
	if (power) segments.push(power)
	const hp = buildStatSegment(card.hp, card.upgrade_hp, 'HP')
	if (hp) segments.push(hp)
	return segments
}

/**
 * @displayName Compute Title Font Size
 * @strategicPurpose Line 2 must fit the exact 720-twip row; a long title needs
 *   a smaller point size to reduce (not eliminate) wrap-induced clipping.
 * @tacticalObjective Returns `config.titleShrinkFontHalfPoints` when
 *   `title.length > config.titleShrinkThreshold`, else `config.titleFontHalfPoints`.
 */
export function computeTitleFontHalfPoints(title: string, config: LabelLayoutConfig): number {
	return title.length > config.titleShrinkThreshold
		? config.titleShrinkFontHalfPoints
		: config.titleFontHalfPoints
}

/**
 * @displayName Compute Subtitle Font Size
 * @strategicPurpose Same auto-shrink mitigation as {@link computeTitleFontHalfPoints},
 *   applied to line 3.
 * @tacticalObjective Returns `config.subtitleShrinkFontHalfPoints` when
 *   `subtitle.length > config.subtitleShrinkThreshold`, else `config.subtitleFontHalfPoints`.
 */
export function computeSubtitleFontHalfPoints(subtitle: string, config: LabelLayoutConfig): number {
	return subtitle.length > config.subtitleShrinkThreshold
		? config.subtitleShrinkFontHalfPoints
		: config.subtitleFontHalfPoints
}

/**
 * @displayName Compute Unique Marker
 * @strategicPurpose SWU convention: the unique-card diamond `◊` is prepended
 *   before a unique card's name. Pure decision function so the marker text is
 *   red-green testable without constructing a single docx Paragraph, and so
 *   `uniqueMarker: ''` disables the marker (via config, not a code branch).
 * @tacticalObjective Returns `config.uniqueMarker` when `card.unique` is
 *   true, else `''`.
 */
export function computeUniqueMarker(
	card: Card,
	config: Pick<LabelLayoutConfig, 'uniqueMarker'>,
): string {
	return card.unique ? config.uniqueMarker : ''
}

/**
 * @displayName Compute Hanging Indent
 * @strategicPurpose `hangingIndent` is only meaningful in `align: 'left'` mode
 *   (it aligns wrapped text under the title start, not under the icon/cost);
 *   centered mode has no "start" for wrapped text to hang from.
 * @tacticalObjective Returns the OOXML paragraph indent shape when
 *   `config.align === 'left' && config.hangingIndent`, else `undefined`.
 */
export function computeHangingIndent(
	config: LabelLayoutConfig,
): { left: number; hanging: number } | undefined {
	if (config.align !== 'left' || !config.hangingIndent) {
		return undefined
	}
	return { left: config.hangingIndentTwips, hanging: config.hangingIndentTwips }
}

/**
 * @displayName Label Line Kind
 * @strategicPurpose Names the three possible paragraph roles in a label cell so
 *   ordering logic (v3: title, subtitle, stats) is expressed as data, not as
 *   duplicated paragraph-construction call order in render.ts.
 * @tacticalObjective Consumed by {@link orderLabelLines} and by render.ts's
 *   per-kind paragraph builder dispatch.
 */
export type LabelLineKind = 'title' | 'subtitle' | 'stats'

/**
 * @displayName Order Label Lines
 * @strategicPurpose v3 spec: Title first, Subtitle second, stats line LAST
 *   (`statsLinePosition: 'below'`, the default). `'above'` reproduces the v2
 *   order (stats, Title, Subtitle) for a config-level rollback with no code
 *   change. Pure and deterministic so it can be red-green tested without
 *   constructing a single docx Paragraph.
 * @tacticalObjective Returns the ordered `LabelLineKind[]` for one label cell,
 *   omitting `'subtitle'` when `hasSubtitle` is false.
 */
export function orderLabelLines(
	config: Pick<LabelLayoutConfig, 'statsLinePosition'>,
	hasSubtitle: boolean,
): LabelLineKind[] {
	const titleSubtitle: LabelLineKind[] = hasSubtitle ? ['title', 'subtitle'] : ['title']
	return config.statsLinePosition === 'above'
		? ['stats', ...titleSubtitle]
		: [...titleSubtitle, 'stats']
}

/**
 * @displayName Character Style Id
 * @strategicPurpose Names the eight per-field named Word character styles
 *   (plus the doc-wide set-name and separator styles) the v3 stat line
 *   references, so the field→style mapping is one typed lookup table instead
 *   of inline string literals scattered across render.ts.
 * @tacticalObjective Consumed by {@link styleIdsForStatSuffix} and directly by
 *   render.ts for `setName`/`statSeparator`.
 */
export type CharacterStyleId =
	| 'setName'
	| 'statSeparator'
	| 'costValue'
	| 'costLabel'
	| 'powerValue'
	| 'powerLabel'
	| 'hpValue'
	| 'hpLabel'
	| 'rarityIcon'

/**
 * @displayName Style Ids For Stat Suffix
 * @strategicPurpose Each {@link StatLineSegment} carries a `suffix` of
 *   `'cost' | 'power' | 'HP'`; the v3 spec asks for a distinct bold "value"
 *   character style and a regular "label" character style per field so the
 *   user can restyle each independently from Word's style pane.
 * @tacticalObjective Pure lookup, no docx dependency — deterministic and
 *   exhaustively switch-typed so a new `StatLineSegment['suffix']` value is a
 *   compile error here, not a silent fallthrough.
 */
export function styleIdsForStatSuffix(suffix: StatLineSegment['suffix']): {
	value: CharacterStyleId
	label: CharacterStyleId
} {
	switch (suffix) {
		case 'cost':
			return { value: 'costValue', label: 'costLabel' }
		case 'power':
			return { value: 'powerValue', label: 'powerLabel' }
		case 'HP':
			return { value: 'hpValue', label: 'hpLabel' }
	}
}

function foldCompareCodes(a: string, b: string): number {
	const ka = foldSortKey(a, null)
	const kb = foldSortKey(b, null)
	if (ka < kb) return -1
	if (ka > kb) return 1
	return 0
}

/**
 * @displayName Order Cards Within An Aspect By Set
 * @strategicPurpose Sets flow continuously within an aspect section (no page
 *   break on set change): the label sheet groups by set, but the row grid
 *   itself is unaware of the set boundary. Every card passed in must be
 *   accounted for in the output — a set code the ordering doesn't recognize
 *   would otherwise silently vanish from the sheet.
 * @tacticalObjective Buckets by `expansion_code`, orders the buckets per
 *   `setOrder` ('release' = {@link PREMIER_FILE_SET_PRECEDENCE}; 'alphabetical'
 *   = fold-sorted set codes, never localeCompare), sorts each bucket with
 *   {@link sortWithinGroup}, and concatenates. Throws if any set code present
 *   in `cards` is missing from the computed order (accounting guard).
 */
export function orderCardsWithinAspectBySet(
	cards: readonly Card[],
	setOrder: LabelLayoutConfig['setOrder'],
): Card[] {
	const bySet = new Map<string, Card[]>()
	for (const c of cards) {
		const bucket = bySet.get(c.expansion_code)
		if (bucket) {
			bucket.push(c)
		} else {
			bySet.set(c.expansion_code, [c])
		}
	}
	const setCodes = [...bySet.keys()]
	const orderedCodes =
		setOrder === 'release'
			? (PREMIER_FILE_SET_PRECEDENCE as readonly string[]).filter((code) => bySet.has(code))
			: [...setCodes].sort(foldCompareCodes)
	if (orderedCodes.length !== setCodes.length) {
		const missing = setCodes.filter((code) => !orderedCodes.includes(code))
		throw new Error(
			`orderCardsWithinAspectBySet: set code(s) [${missing.join(', ')}] not accounted for in '${setOrder}' order`,
		)
	}
	const result: Card[] = []
	for (const code of orderedCodes) {
		const bucket = bySet.get(code)
		if (bucket) {
			result.push(...sortWithinGroup(bucket))
		}
	}
	return result
}

/**
 * @displayName Group By Aspect, Then By Set
 * @strategicPurpose The v2 grouping spec: GROUP BY aspect (unchanged order,
 *   one DOCX section per aspect), then GROUP BY set within the aspect (no
 *   page break on set change), then alphabetical by title within each set.
 * @tacticalObjective Composes {@link groupByAspect} (unchanged, still throws
 *   on an unrecognized aspect key) with {@link orderCardsWithinAspectBySet}
 *   per aspect bucket.
 */
export function groupByAspectThenSet(
	cards: readonly Card[],
	config: LabelLayoutConfig,
): Map<AspectGroupKey, Card[]> {
	const byAspect = groupByAspect(cards)
	const ordered = new Map<AspectGroupKey, Card[]>()
	for (const [key, bucket] of byAspect) {
		ordered.set(key, orderCardsWithinAspectBySet(bucket, config.setOrder))
	}
	return ordered
}
