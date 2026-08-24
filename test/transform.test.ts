import { describe, expect, it } from 'vitest'
import { DEFAULT_CONFIG, type LabelLayoutConfig } from '../src/config.ts'
import type { Card } from '../src/schema.ts'
import {
	ASPECT_GROUP_ORDER,
	AVERY_5167_GEOMETRY,
	PREMIER_FILE_SET_PRECEDENCE,
	assertPremierSetCoverage,
	buildStatLineSegments,
	computeHangingIndent,
	computeSubtitleFontHalfPoints,
	computeTitleFontHalfPoints,
	computeUniqueMarker,
	dedupeCards,
	foldSortKey,
	groupByAspect,
	groupByAspectThenSet,
	orderCardsWithinAspectBySet,
	orderLabelLines,
	sortWithinGroup,
	styleIdsForStatSuffix,
} from '../src/transform.ts'

function card(overrides: Partial<Card>): Card {
	return {
		title: 'Test Card',
		subtitle: null,
		cost: 1,
		type_name: 'Unit',
		rarity: 'Common',
		expansion_code: 'JTL',
		unique: false,
		aspects: ['Vigilance'],
		...overrides,
	}
}

describe('computeUniqueMarker', () => {
	it('returns config.uniqueMarker for a unique card', () => {
		const c = card({ unique: true })
		expect(computeUniqueMarker(c, DEFAULT_CONFIG)).toBe('◊ ')
	})

	it('returns empty string for a non-unique card', () => {
		const c = card({ unique: false })
		expect(computeUniqueMarker(c, DEFAULT_CONFIG)).toBe('')
	})

	it('returns empty string for a unique card when the marker is disabled via config', () => {
		const c = card({ unique: true })
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, uniqueMarker: '' }
		expect(computeUniqueMarker(c, config)).toBe('')
	})
})

describe('foldSortKey', () => {
	it('lowercases and strips diacritics for locale-independent comparison', () => {
		expect(foldSortKey('Émigré', null)).toBe('emigre ')
		expect(foldSortKey('Zebra', 'A Subtitle')).toBe('zebra a subtitle')
	})

	it('treats null subtitle as empty string', () => {
		expect(foldSortKey('Title', null)).toBe('title ')
	})
})

describe('sortWithinGroup', () => {
	it('sorts by codepoint-compared fold key, ascending', () => {
		const cards = [card({ title: 'Zebra' }), card({ title: 'Apple' }), card({ title: 'Mango' })]
		const sorted = sortWithinGroup(cards)
		expect(sorted.map((c) => c.title)).toEqual(['Apple', 'Mango', 'Zebra'])
	})

	it('ties on fold key break on raw title then raw subtitle', () => {
		const cards = [card({ title: 'Same', subtitle: 'Z' }), card({ title: 'Same', subtitle: 'A' })]
		const sorted = sortWithinGroup(cards)
		expect(sorted.map((c) => c.subtitle)).toEqual(['A', 'Z'])
	})

	it('never mutates the input array', () => {
		const cards = [card({ title: 'Zebra' }), card({ title: 'Apple' })]
		const copy = [...cards]
		sortWithinGroup(cards)
		expect(cards).toEqual(copy)
	})
})

describe('dedupeCards', () => {
	it('keeps the first occurrence in caller-supplied set-precedence order and drops later duplicates', () => {
		const jtlPrinting = card({ title: 'Vanjon', subtitle: 'Escape Craft', expansion_code: 'JTL' })
		const ibhReprint = card({ title: 'Vanjon', subtitle: 'Escape Craft', expansion_code: 'IBH' })
		const { kept, droppedCount } = dedupeCards([jtlPrinting, ibhReprint])
		expect(kept).toHaveLength(1)
		expect(kept[0]?.expansion_code).toBe('JTL')
		expect(droppedCount).toBe(1)
	})

	it('keys on title|subtitle|type_name so same-name different-type cards both survive', () => {
		const leader = card({ title: 'Boba Fett', subtitle: 'Mercenary', type_name: 'Leader' })
		const unit = card({ title: 'Boba Fett', subtitle: 'Mercenary', type_name: 'Unit' })
		const { kept, droppedCount } = dedupeCards([leader, unit])
		expect(kept).toHaveLength(2)
		expect(droppedCount).toBe(0)
	})

	it('treats null subtitle as empty string in the dedupe key', () => {
		const a = card({ title: 'Base One', subtitle: null, type_name: 'Base' })
		const b = card({ title: 'Base One', subtitle: '', type_name: 'Base' })
		const { kept, droppedCount } = dedupeCards([a, b])
		expect(kept).toHaveLength(1)
		expect(droppedCount).toBe(1)
	})
})

describe('groupByAspect', () => {
	it('groups by first aspect and defaults missing aspects to Neutral', () => {
		const cards = [
			card({ title: 'A', aspects: ['Command'] }),
			card({ title: 'B', aspects: [] }),
			card({ title: 'C', aspects: ['Vigilance', 'Villainy'] }),
		]
		const groups = groupByAspect(cards)
		expect(groups.get('Command')?.map((c) => c.title)).toEqual(['A'])
		expect(groups.get('Neutral')?.map((c) => c.title)).toEqual(['B'])
		expect(groups.get('Vigilance')?.map((c) => c.title)).toEqual(['C'])
	})

	it('returns groups keyed only from ASPECT_GROUP_ORDER', () => {
		const cards = [card({ title: 'A', aspects: ['Heroism'] })]
		const groups = groupByAspect(cards)
		for (const key of groups.keys()) {
			expect(ASPECT_GROUP_ORDER).toContain(key)
		}
	})
})

describe('ASPECT_GROUP_ORDER', () => {
	it('is the exact seven-group order the spec requires', () => {
		expect(ASPECT_GROUP_ORDER).toEqual([
			'Vigilance',
			'Command',
			'Aggression',
			'Cunning',
			'Villainy',
			'Heroism',
			'Neutral',
		])
	})
})

describe('assertPremierSetCoverage', () => {
	const premierSets = [
		'JTL',
		'JTLP',
		'LOF',
		'LOFP',
		'SEC',
		'SECP',
		'LAW',
		'LAWP',
		'ASH',
		'ASHP',
		'G25',
		'P25',
		'P26',
		'IBH',
	]
	const availableSets = ['JTL', 'LOF', 'SEC', 'LAW', 'ASH', 'IBH']

	it('passes when files present are exactly the six main sets and the rest are known promo codes', () => {
		expect(() => assertPremierSetCoverage(premierSets, availableSets)).not.toThrow()
	})

	it('throws when a set without a per-set file is not a known promo/dedupe code', () => {
		expect(() => assertPremierSetCoverage([...premierSets, 'UNKNOWNSET'], availableSets)).toThrow()
	})

	it('throws when the set of available per-set files is not exactly the six main sets', () => {
		expect(() => assertPremierSetCoverage(premierSets, ['JTL', 'LOF'])).toThrow()
	})
})

describe('PREMIER_FILE_SET_PRECEDENCE', () => {
	it('is JTL, LOF, SEC, LAW, ASH, IBH in that order', () => {
		expect(PREMIER_FILE_SET_PRECEDENCE).toEqual(['JTL', 'LOF', 'SEC', 'LAW', 'ASH', 'IBH'])
	})
})

describe('AVERY_5167_GEOMETRY', () => {
	it('matches the exact Avery 5167 twips geometry from spec', () => {
		expect(AVERY_5167_GEOMETRY.page).toEqual({ width: 12240, height: 15840 })
		expect(AVERY_5167_GEOMETRY.margins).toEqual({ top: 720, bottom: 576, left: 405, right: 405 })
		expect(AVERY_5167_GEOMETRY.columnWidths).toEqual([2520, 450, 2520, 450, 2520, 450, 2520])
		expect(AVERY_5167_GEOMETRY.rowHeightExact).toBe(720)
		expect(AVERY_5167_GEOMETRY.rowsPerSheet).toBe(20)
		expect(AVERY_5167_GEOMETRY.labelColumnIndices).toEqual([0, 2, 4, 6])
	})
})

describe('buildStatLineSegments', () => {
	it('unit: renders cost | power | HP in order', () => {
		const c = card({ cost: 3, power: 2, hp: 4 })
		expect(buildStatLineSegments(c)).toEqual([
			{ bold: '3', suffix: 'cost' },
			{ bold: '2', suffix: 'power' },
			{ bold: '4', suffix: 'HP' },
		])
	})

	it('leader: renders all three when all present', () => {
		const c = card({ type_name: 'Leader', cost: 5, power: 6, hp: 7 })
		expect(buildStatLineSegments(c)).toEqual([
			{ bold: '5', suffix: 'cost' },
			{ bold: '6', suffix: 'power' },
			{ bold: '7', suffix: 'HP' },
		])
	})

	it('base: renders HP only (cost and power null)', () => {
		const c = card({ type_name: 'Base', cost: null, power: null, hp: 26 })
		expect(buildStatLineSegments(c)).toEqual([{ bold: '26', suffix: 'HP' }])
	})

	it('event: renders cost only (power/hp null)', () => {
		const c = card({ type_name: 'Event', cost: 2, power: null, hp: null })
		expect(buildStatLineSegments(c)).toEqual([{ bold: '2', suffix: 'cost' }])
	})

	it('credit token: renders no segments at all', () => {
		const c = card({ type_name: 'Credit Token', cost: null, power: null, hp: null })
		expect(buildStatLineSegments(c)).toEqual([])
	})

	it('plain upgrade: power/hp null, upgrade_power/upgrade_hp non-null render with + prefix', () => {
		const c = card({
			type_name: 'Upgrade',
			cost: 1,
			power: null,
			hp: null,
			upgrade_power: 2,
			upgrade_hp: 1,
		})
		expect(buildStatLineSegments(c)).toEqual([
			{ bold: '1', suffix: 'cost' },
			{ bold: '+2', suffix: 'power' },
			{ bold: '+1', suffix: 'HP' },
		])
	})

	it('plain upgrade with no upgrade stats: renders cost only', () => {
		const c = card({ type_name: 'Upgrade', cost: 1, power: null, hp: null })
		expect(buildStatLineSegments(c)).toEqual([{ bold: '1', suffix: 'cost' }])
	})

	it('pilot dual-stat: both unit and upgrade stats non-null render {unit}/{upgrade}+ for each', () => {
		const c = card({
			type_name: 'Unit',
			cost: 2,
			power: 4,
			hp: 3,
			upgrade_power: 5,
			upgrade_hp: 4,
		})
		expect(buildStatLineSegments(c)).toEqual([
			{ bold: '2', suffix: 'cost' },
			{ bold: '4/5+', suffix: 'power' },
			{ bold: '3/4+', suffix: 'HP' },
		])
	})

	it('pilot dual-stat applies independently per field: power dual but hp plain', () => {
		const c = card({
			type_name: 'Unit',
			cost: 2,
			power: 4,
			hp: null,
			upgrade_power: 5,
			upgrade_hp: 4,
		})
		expect(buildStatLineSegments(c)).toEqual([
			{ bold: '2', suffix: 'cost' },
			{ bold: '4/5+', suffix: 'power' },
			{ bold: '+4', suffix: 'HP' },
		])
	})
})

describe('computeTitleFontHalfPoints', () => {
	it('returns the default size for a title at or under the shrink threshold', () => {
		const title = 'A'.repeat(DEFAULT_CONFIG.titleShrinkThreshold)
		expect(computeTitleFontHalfPoints(title, DEFAULT_CONFIG)).toBe(
			DEFAULT_CONFIG.titleFontHalfPoints,
		)
	})

	it('returns the shrink size for a title over the shrink threshold', () => {
		const title = 'A'.repeat(DEFAULT_CONFIG.titleShrinkThreshold + 1)
		expect(computeTitleFontHalfPoints(title, DEFAULT_CONFIG)).toBe(
			DEFAULT_CONFIG.titleShrinkFontHalfPoints,
		)
	})
})

describe('computeSubtitleFontHalfPoints', () => {
	it('returns the default size for a subtitle at or under the shrink threshold', () => {
		const subtitle = 'A'.repeat(DEFAULT_CONFIG.subtitleShrinkThreshold)
		expect(computeSubtitleFontHalfPoints(subtitle, DEFAULT_CONFIG)).toBe(
			DEFAULT_CONFIG.subtitleFontHalfPoints,
		)
	})

	it('returns the shrink size for a subtitle over the shrink threshold', () => {
		const subtitle = 'A'.repeat(DEFAULT_CONFIG.subtitleShrinkThreshold + 1)
		expect(computeSubtitleFontHalfPoints(subtitle, DEFAULT_CONFIG)).toBe(
			DEFAULT_CONFIG.subtitleShrinkFontHalfPoints,
		)
	})
})

describe('computeHangingIndent', () => {
	it('returns undefined in centered mode regardless of hangingIndent flag', () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, align: 'center', hangingIndent: true }
		expect(computeHangingIndent(config)).toBeUndefined()
	})

	it('returns undefined in left mode when hangingIndent is off', () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, align: 'left', hangingIndent: false }
		expect(computeHangingIndent(config)).toBeUndefined()
	})

	it('returns left/hanging twips in left mode when hangingIndent is on', () => {
		const config: LabelLayoutConfig = {
			...DEFAULT_CONFIG,
			align: 'left',
			hangingIndent: true,
			hangingIndentTwips: 360,
		}
		expect(computeHangingIndent(config)).toEqual({ left: 360, hanging: 360 })
	})
})

describe('orderCardsWithinAspectBySet', () => {
	const cards = [
		card({ title: 'Zebra', expansion_code: 'SEC' }),
		card({ title: 'Apple', expansion_code: 'JTL' }),
		card({ title: 'Mango', expansion_code: 'SEC' }),
		card({ title: 'Bravo', expansion_code: 'LOF' }),
	]

	it('release order: sets flow JTL, LOF, SEC, ... and each set is alphabetical within itself', () => {
		const ordered = orderCardsWithinAspectBySet(cards, 'release')
		expect(ordered.map((c) => `${c.expansion_code}:${c.title}`)).toEqual([
			'JTL:Apple',
			'LOF:Bravo',
			'SEC:Mango',
			'SEC:Zebra',
		])
	})

	it('alphabetical order: sets flow fold-sorted by set code', () => {
		const ordered = orderCardsWithinAspectBySet(cards, 'alphabetical')
		expect(ordered.map((c) => c.expansion_code)).toEqual(['JTL', 'LOF', 'SEC', 'SEC'])
	})

	it('never mutates the input array', () => {
		const copy = [...cards]
		orderCardsWithinAspectBySet(cards, 'release')
		expect(cards).toEqual(copy)
	})
})

describe('orderLabelLines', () => {
	it("v3 default ('below'): title, subtitle, stats when a subtitle is present", () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, statsLinePosition: 'below' }
		expect(orderLabelLines(config, true)).toEqual(['title', 'subtitle', 'stats'])
	})

	it("v3 default ('below'): title, stats when no subtitle is present", () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, statsLinePosition: 'below' }
		expect(orderLabelLines(config, false)).toEqual(['title', 'stats'])
	})

	it("'above' reproduces the v2 order: stats, title, subtitle", () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, statsLinePosition: 'above' }
		expect(orderLabelLines(config, true)).toEqual(['stats', 'title', 'subtitle'])
	})

	it("'above' with no subtitle: stats, title", () => {
		const config: LabelLayoutConfig = { ...DEFAULT_CONFIG, statsLinePosition: 'above' }
		expect(orderLabelLines(config, false)).toEqual(['stats', 'title'])
	})

	it('DEFAULT_CONFIG.statsLinePosition is below', () => {
		expect(DEFAULT_CONFIG.statsLinePosition).toBe('below')
	})
})

describe('styleIdsForStatSuffix', () => {
	it('maps cost to costValue/costLabel', () => {
		expect(styleIdsForStatSuffix('cost')).toEqual({ value: 'costValue', label: 'costLabel' })
	})

	it('maps power to powerValue/powerLabel', () => {
		expect(styleIdsForStatSuffix('power')).toEqual({ value: 'powerValue', label: 'powerLabel' })
	})

	it('maps HP to hpValue/hpLabel', () => {
		expect(styleIdsForStatSuffix('HP')).toEqual({ value: 'hpValue', label: 'hpLabel' })
	})
})

describe('groupByAspectThenSet', () => {
	it('groups by aspect (unchanged order), then by set within each aspect', () => {
		const cards = [
			card({ title: 'B', aspects: ['Command'], expansion_code: 'LOF' }),
			card({ title: 'A', aspects: ['Command'], expansion_code: 'JTL' }),
			card({ title: 'C', aspects: ['Vigilance'], expansion_code: 'SEC' }),
		]
		const groups = groupByAspectThenSet(cards, DEFAULT_CONFIG)
		expect([...groups.keys()]).toEqual(['Vigilance', 'Command'])
		expect(groups.get('Command')?.map((c) => c.expansion_code)).toEqual(['JTL', 'LOF'])
	})
})
