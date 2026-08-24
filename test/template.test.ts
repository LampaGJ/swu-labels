import { describe, expect, it } from 'vitest'
import { DEFAULT_CONFIG } from '../src/config.ts'
import type { Card } from '../src/schema.ts'
import { parseTemplateLine, resolveLine } from '../src/template.ts'

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

function textOf(runs: ReturnType<typeof resolveLine>): string {
	if (!runs) return ''
	return runs.map((r) => (r.kind === 'text' ? r.text : '[icon]')).join('')
}

describe('parseTemplateLine: unknown variable', () => {
	it('throws naming the bad variable', () => {
		expect(() => parseTemplateLine({ style: 'cardTitle', text: '{Titel}' })).toThrow(/Titel/)
	})
})

describe('resolveLine: title line', () => {
	const line = parseTemplateLine({ style: 'cardTitle', text: '{unique_indicator} {Title}' })

	it('renders bare title text for a non-unique card (no leading space)', () => {
		const c = card({ title: 'Vanjon', unique: false })
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('Vanjon')
	})

	it('renders marker + space + title for a unique card', () => {
		const c = card({ title: 'Vanjon', unique: true })
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('◊ Vanjon')
	})
})

describe('resolveLine: subtitle line', () => {
	const line = parseTemplateLine({ style: 'cardSubtitle', text: '{Subtitle}' })

	it('renders subtitle text when present', () => {
		const c = card({ subtitle: 'Escape Craft' })
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('Escape Craft')
	})

	it('collapses to null (paragraph omitted) when subtitle is absent', () => {
		const c = card({ subtitle: null })
		expect(resolveLine(line, c, DEFAULT_CONFIG)).toBeNull()
	})
})

describe('resolveLine: stats line (acceptance sanity)', () => {
	const line = parseTemplateLine({
		style: 'cardStats',
		text: '{rarity_symbol} {SET} - {cost_value} {cost_label} | {power_value} {power_label} | {hp_value} {hp_label}',
	})

	it('unit: icon SET - 3 cost | 2 power | 4 HP', () => {
		const c = card({ cost: 3, power: 2, hp: 4, expansion_code: 'JTL' })
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe(
			'[icon] JTL - 3 cost | 2 power | 4 HP',
		)
	})

	it('base: icon SET - 30 HP', () => {
		const c = card({
			type_name: 'Base',
			cost: null,
			power: null,
			hp: 30,
			expansion_code: 'SEC',
		})
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('[icon] SEC - 30 HP')
	})

	it('event: icon SET - 5 cost', () => {
		const c = card({ type_name: 'Event', cost: 5, power: null, hp: null, expansion_code: 'LOF' })
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('[icon] LOF - 5 cost')
	})

	it('credit token: icon SET (no dash, no stats)', () => {
		const c = card({
			type_name: 'Credit Token',
			cost: null,
			power: null,
			hp: null,
			expansion_code: 'ASH',
		})
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe('[icon] ASH')
	})

	it('pilot: ... 4/3+ power | 6/4+ HP', () => {
		const c = card({
			cost: 2,
			power: 4,
			hp: 6,
			upgrade_power: 3,
			upgrade_hp: 4,
			expansion_code: 'JTL',
		})
		expect(textOf(resolveLine(line, c, DEFAULT_CONFIG))).toBe(
			'[icon] JTL - 2 cost | 4/3+ power | 6/4+ HP',
		)
	})
})
