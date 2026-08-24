import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import type { ApiCard } from '../src/api-schema.ts'
import { ApiPageResponseSchema } from '../src/api-schema.ts'
import {
	bucketByExpansion,
	buildPageUrl,
	deriveTagFromUpdatedAt,
	isCanonicalPrinting,
	mapApiCardToSnapshotCard,
	parseTagArg,
	sortCardsStably,
} from '../src/ingest.ts'
import type { Card } from '../src/schema.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))

/**
 * Small pinned fixture captured live from
 * https://admin.starwarsunlimited.com/api/card-list (page 1, pageSize 5, the exact
 * populate fields ingest.ts requests) on 2026-08-24. Committed at
 * test/fixtures/api-sample.json — five real canonical SOR cards (2 Leaders, 3
 * Units), covering multi-aspect Leaders and single-aspect Units.
 */
function loadFixture(): ApiCard[] {
	const raw = JSON.parse(readFileSync(join(__dirname, 'fixtures', 'api-sample.json'), 'utf8'))
	return ApiPageResponseSchema.parse(raw).data
}

function apiCard(overrides: {
	id?: number
	title?: string
	subtitle?: string | null
	cardNumber?: number | null
	updatedAt?: string
	expansionCode?: string
	typeName?: ApiCard['attributes']['type']['data'] extends { attributes: { name: infer N } } | null
		? N
		: never
	rarityName?: string
	aspects?: string[]
	variantOfId?: number | null
	reprintOfId?: number | null
}): ApiCard {
	return {
		id: overrides.id ?? 1,
		attributes: {
			title: overrides.title ?? 'Test Card',
			subtitle: overrides.subtitle ?? null,
			cardNumber: overrides.cardNumber ?? 1,
			cost: 1,
			power: 2,
			hp: 3,
			upgradePower: null,
			upgradeHp: null,
			unique: false,
			updatedAt: overrides.updatedAt ?? '2026-08-01T00:00:00.000Z',
			expansion: {
				data: { id: 1, attributes: { code: overrides.expansionCode ?? 'JTL' } },
			},
			type: {
				data: { id: 1, attributes: { name: (overrides.typeName ?? 'Unit') as never } },
			},
			rarity: {
				data: { id: 1, attributes: { name: (overrides.rarityName ?? 'Common') as never } },
			},
			aspects: {
				data: (overrides.aspects ?? ['Vigilance']).map((name, i) => ({
					id: i + 1,
					attributes: { name: name as never },
				})),
			},
			aspectDuplicates: { data: [] },
			variantOf: {
				data:
					overrides.variantOfId === undefined || overrides.variantOfId === null
						? null
						: { id: overrides.variantOfId, attributes: {} },
			},
			reprintOf: {
				data:
					overrides.reprintOfId === undefined || overrides.reprintOfId === null
						? null
						: { id: overrides.reprintOfId, attributes: {} },
			},
		},
	} as ApiCard
}

describe('buildPageUrl', () => {
	it('encodes pagination and populate fields, requesting no art fields', () => {
		const url = buildPageUrl(3)
		expect(url).toContain('pagination%5Bpage%5D=3')
		expect(url).toContain('pagination%5BpageSize%5D=100')
		expect(url).toContain('populate%5B0%5D=expansion')
		expect(url).not.toContain('artFront')
		expect(url).not.toContain('artBack')
		expect(url).not.toContain('artThumbnail')
	})
})

describe('isCanonicalPrinting', () => {
	it('every card in the pinned live fixture is canonical', () => {
		for (const card of loadFixture()) {
			expect(isCanonicalPrinting(card)).toBe(true)
		}
	})

	it('is false when variantOf is set', () => {
		expect(isCanonicalPrinting(apiCard({ variantOfId: 99 }))).toBe(false)
	})

	it("is true when reprintOf is set but variantOf is null — a reprint into a later set is still that set's own canonical printing", () => {
		expect(isCanonicalPrinting(apiCard({ reprintOfId: 99 }))).toBe(true)
	})

	it('is true when both are null', () => {
		expect(isCanonicalPrinting(apiCard({}))).toBe(true)
	})

	it('is false when both variantOf and reprintOf are set (a foil variant of a reprint)', () => {
		expect(isCanonicalPrinting(apiCard({ variantOfId: 42, reprintOfId: 99 }))).toBe(false)
	})
})

describe('mapApiCardToSnapshotCard', () => {
	it('maps the live fixture into exactly the pinned-snapshot Card shape', () => {
		const fixture = loadFixture()
		const luke = fixture.find((c) => c.id === 5)
		if (!luke) throw new Error('fixture missing card id 5 (Luke Skywalker)')
		const { card, updatedAt } = mapApiCardToSnapshotCard(luke)
		expect(card).toEqual<Card>({
			title: 'Luke Skywalker',
			subtitle: 'Faithful Friend',
			cost: 6,
			power: 4,
			hp: 7,
			upgrade_power: null,
			upgrade_hp: null,
			unique: true,
			type_name: 'Leader',
			rarity: 'Special',
			expansion_code: 'SOR',
			aspects: ['Vigilance', 'Heroism'],
		})
		expect(updatedAt).toBe('2024-07-15T17:47:00.124Z')
	})

	it('preserves the API relation order for aspects, unmerged with aspectDuplicates', () => {
		const fixture = loadFixture()
		const vader = fixture.find((c) => c.id === 6)
		if (!vader) throw new Error('fixture missing card id 6 (Darth Vader)')
		const { card } = mapApiCardToSnapshotCard(vader)
		expect(card.aspects).toEqual(['Aggression', 'Villainy'])
	})

	it('throws loudly when the expansion relation is missing', () => {
		const c = apiCard({})
		c.attributes.expansion = { data: null }
		expect(() => mapApiCardToSnapshotCard(c)).toThrow(/expansion relation/)
	})

	it('rejects an unknown rarity value at the schema boundary rather than mapping', () => {
		expect(() =>
			ApiPageResponseSchema.parse({
				data: [
					{
						...apiCard({}),
						attributes: {
							...apiCard({}).attributes,
							rarity: { data: { id: 1, attributes: { name: 'Mythic' } } },
						},
					},
				],
				meta: { pagination: { page: 1, pageSize: 100, pageCount: 1, total: 1 } },
			}),
		).toThrow()
	})
})

describe('deriveTagFromUpdatedAt', () => {
	it('derives v<YYYY-MM-DD> from the max updatedAt across all cards', () => {
		const tag = deriveTagFromUpdatedAt([
			'2026-08-01T00:00:00.000Z',
			'2026-08-23T19:40:39.599Z',
			'2026-01-15T00:00:00.000Z',
		])
		expect(tag).toBe('v2026-08-23')
	})

	it('is a pure function of the data, not wall-clock time — same input always yields the same tag', () => {
		const input = ['2026-08-23T19:40:39.599Z', '2026-08-01T00:00:00.000Z']
		expect(deriveTagFromUpdatedAt(input)).toBe(deriveTagFromUpdatedAt([...input]))
	})

	it('throws on empty input instead of deriving undefined', () => {
		expect(() => deriveTagFromUpdatedAt([])).toThrow()
	})
})

type SortableCard = Card & { cardNumberSortKey: number }

function sortableCard(overrides: {
	title: string
	subtitle?: string | null
	cardNumberSortKey: number
}): SortableCard {
	return {
		cost: 1,
		power: null,
		hp: null,
		upgrade_power: null,
		upgrade_hp: null,
		unique: false,
		type_name: 'Unit',
		rarity: 'Common',
		expansion_code: 'JTL',
		aspects: [],
		subtitle: null,
		...overrides,
	}
}

describe('sortCardsStably', () => {
	it('sorts primarily by card number ascending', () => {
		const cards = [
			sortableCard({ title: 'B', cardNumberSortKey: 20 }),
			sortableCard({ title: 'A', cardNumberSortKey: 5 }),
		]
		expect(sortCardsStably(cards).map((c) => c.title)).toEqual(['A', 'B'])
	})

	it('sorts cards with no card number last', () => {
		const cards = [
			sortableCard({ title: 'NoNumber', cardNumberSortKey: Number.POSITIVE_INFINITY }),
			sortableCard({ title: 'HasNumber', cardNumberSortKey: 1 }),
		]
		expect(sortCardsStably(cards).map((c) => c.title)).toEqual(['HasNumber', 'NoNumber'])
	})

	it('ties on card number break on raw title then raw subtitle, never localeCompare', () => {
		const cards = [
			sortableCard({ title: 'Same', subtitle: 'Z', cardNumberSortKey: 1 }),
			sortableCard({ title: 'Same', subtitle: 'A', cardNumberSortKey: 1 }),
		]
		expect(sortCardsStably(cards).map((c) => c.subtitle)).toEqual(['A', 'Z'])
	})

	it('never mutates the input array', () => {
		const cards = [
			sortableCard({ title: 'B', cardNumberSortKey: 2 }),
			sortableCard({ title: 'A', cardNumberSortKey: 1 }),
		]
		const copy = [...cards]
		sortCardsStably(cards)
		expect(cards).toEqual(copy)
	})
})

describe('bucketByExpansion', () => {
	it('buckets cards by expansion_code', () => {
		const a: Card = {
			title: 'A',
			subtitle: null,
			cost: 1,
			power: null,
			hp: null,
			upgrade_power: null,
			upgrade_hp: null,
			unique: false,
			type_name: 'Unit',
			rarity: 'Common',
			expansion_code: 'JTL',
			aspects: [],
		}
		const b: Card = { ...a, title: 'B', expansion_code: 'LOF' }
		const c: Card = { ...a, title: 'C', expansion_code: 'JTL' }
		const buckets = bucketByExpansion([a, b, c])
		expect([...buckets.keys()].sort()).toEqual(['JTL', 'LOF'])
		expect(buckets.get('JTL')?.map((x) => x.title)).toEqual(['A', 'C'])
		expect(buckets.get('LOF')?.map((x) => x.title)).toEqual(['B'])
	})
})

describe('parseTagArg', () => {
	it('returns the value after --tag', () => {
		expect(parseTagArg(['--tag', 'v2026-01-01'])).toBe('v2026-01-01')
	})

	it('returns null when --tag is absent', () => {
		expect(parseTagArg([])).toBeNull()
	})
})
