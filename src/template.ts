// @manipulation Pure transform stage of the premier-labels manipulation node
// (doctrine: ~/.claude/reproducible-data-manipulation.md). In: LabelLayoutConfig.template
// (user-editable) + Card (schema.ts). Out: TemplateRunSpec[] per label line, consumed by
// render.ts to build docx runs. Declared effect: preserves (every variable's value is
// carried through verbatim or omitted per the documented collapsing rules — nothing is
// summarized, aggregated, or dropped silently).
import type { LabelLayoutConfig } from './config.ts'
import type { Card } from './schema.ts'
import {
	type CharacterStyleId,
	type StatLineSegment,
	buildStatLineSegments,
	computeSubtitleFontHalfPoints,
	computeTitleFontHalfPoints,
} from './transform.ts'

/**
 * @displayName Template Token
 * @strategicPurpose A template line's `text` is tokenized once (at startup, via
 *   {@link parseTemplateLine}) into an ordered list of literal runs and `{variable}`
 *   references, so per-card rendering never re-parses text and unknown variables fail
 *   fast before a single label is built.
 * @tacticalObjective Discriminated union consumed by {@link resolveLine}.
 */
export type TemplateToken = { type: 'literal'; text: string } | { type: 'variable'; name: string }

/** One dash-side, split further into `|`-separated segments of tokens. */
export type TemplateSegment = TemplateToken[]

/**
 * @displayName Parsed Template Line
 * @strategicPurpose Precomputed shape of one `config.template` entry: `sides` has one
 *   element when the line's text contains no top-level ` - `, two when it does (the
 *   first ` - ` only — precedence rule). Each side is an array of `|`-separated segments.
 * @tacticalObjective Consumed by {@link resolveLine}; produced by {@link parseTemplateLine}.
 */
export type ParsedLine = { style: string; sides: TemplateSegment[][] }

/**
 * @displayName Template Run Spec
 * @strategicPurpose Renderer-agnostic content unit resolved from one variable or kept
 *   literal — render.ts converts each to a real docx `TextRun`/`ImageRun`. Keeping this
 *   abstract lets template.ts stay a pure, docx-free module that unit tests exercise
 *   without constructing a single docx object.
 * @tacticalObjective `'text'` carries the exact run text plus optional character style
 *   and per-card size override; `'image'` is a marker the renderer substitutes with the
 *   rarity icon (baseline shift + `rarityIcon` style — unchanged mechanism from v3).
 */
export type TemplateRunSpec =
	| { kind: 'text'; text: string; style?: CharacterStyleId; size?: number }
	| { kind: 'image' }

type ResolveContext = {
	statSegments: StatLineSegment[]
	titleSize: number
	subtitleSize: number | undefined
}

type VariableDef = {
	resolve: (card: Card, config: LabelLayoutConfig, ctx: ResolveContext) => TemplateRunSpec | null
	/**
	 * True when this variable's own resolved text already carries a trailing
	 * separator space (today, only `unique_indicator`'s marker) — a literal
	 * single-space token immediately following it in the template is then
	 * redundant and is dropped rather than re-emitted as its own run, so the
	 * output reproduces the legacy single-run construction byte-for-byte.
	 */
	absorbSpaceAfter?: boolean
	/**
	 * True when this variable's own resolved text already carries a leading
	 * separator space (today, `cost_label`/`power_label`/`hp_label`) — a
	 * literal single-space token immediately preceding it is dropped for the
	 * same byte-identical-reproduction reason.
	 */
	absorbSpaceBefore?: boolean
}

function findStatSegment(
	ctx: ResolveContext,
	suffix: StatLineSegment['suffix'],
): StatLineSegment | undefined {
	return ctx.statSegments.find((s) => s.suffix === suffix)
}

/**
 * @displayName Template Variable Catalog
 * @strategicPurpose The single source of truth for every `{variable}` a template line
 *   may reference. {@link parseTemplateLine} validates every token against this catalog
 *   at parse time — an unrecognized variable throws immediately, naming itself, rather
 *   than rendering blank. Extending the label language (a new field, a new derived
 *   value) is a one-entry addition here, never a change to the collapsing engine.
 * @tacticalObjective Keyed by variable name (without braces); see {@link VariableDef}
 *   for the per-variable resolve/absorption contract. Docs: docs/template-language.md.
 */
export const VARIABLE_CATALOG: Record<string, VariableDef> = {
	Title: {
		resolve: (card, _config, ctx) =>
			card.title.length > 0 ? { kind: 'text', text: card.title, size: ctx.titleSize } : null,
	},
	Subtitle: {
		resolve: (card, _config, ctx) =>
			card.subtitle ? { kind: 'text', text: card.subtitle, size: ctx.subtitleSize } : null,
	},
	unique_indicator: {
		resolve: (card, config, ctx) =>
			card.unique
				? { kind: 'text', text: config.uniqueMarker, style: 'uniqueMarker', size: ctx.titleSize }
				: null,
		absorbSpaceAfter: true,
	},
	SET: {
		resolve: (card) =>
			card.expansion_code.length > 0
				? { kind: 'text', text: card.expansion_code, style: 'setName' }
				: null,
	},
	rarity_symbol: {
		resolve: () => ({ kind: 'image' }),
	},
	cost_value: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'cost')
			return seg ? { kind: 'text', text: seg.bold, style: 'costValue' } : null
		},
	},
	power_value: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'power')
			return seg ? { kind: 'text', text: seg.bold, style: 'powerValue' } : null
		},
	},
	hp_value: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'HP')
			return seg ? { kind: 'text', text: seg.bold, style: 'hpValue' } : null
		},
	},
	cost_label: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'cost')
			return seg ? { kind: 'text', text: ` ${seg.suffix}`, style: 'costLabel' } : null
		},
		absorbSpaceBefore: true,
	},
	power_label: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'power')
			return seg ? { kind: 'text', text: ` ${seg.suffix}`, style: 'powerLabel' } : null
		},
		absorbSpaceBefore: true,
	},
	hp_label: {
		resolve: (_card, _config, ctx) => {
			const seg = findStatSegment(ctx, 'HP')
			return seg ? { kind: 'text', text: ` ${seg.suffix}`, style: 'hpLabel' } : null
		},
		absorbSpaceBefore: true,
	},
	rarity_name: {
		resolve: (card) => ({ kind: 'text', text: card.rarity, style: 'rarityName' }),
	},
	type: {
		resolve: (card) => ({ kind: 'text', text: card.type_name, style: 'typeName' }),
	},
	aspect: {
		resolve: (card) => ({
			kind: 'text',
			text: card.aspects[0] ?? 'Neutral',
			style: 'aspectName',
		}),
	},
}

const VARIABLE_PATTERN = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g

function tokenizeSegmentText(text: string): TemplateToken[] {
	const tokens: TemplateToken[] = []
	let lastIndex = 0
	VARIABLE_PATTERN.lastIndex = 0
	for (const match of text.matchAll(VARIABLE_PATTERN)) {
		const start = match.index ?? 0
		if (start > lastIndex) {
			tokens.push({ type: 'literal', text: text.slice(lastIndex, start) })
		}
		const name = match[1] as string
		if (!(name in VARIABLE_CATALOG)) {
			throw new Error(`parseTemplateLine: unknown template variable "{${name}}"`)
		}
		tokens.push({ type: 'variable', name })
		lastIndex = start + match[0].length
	}
	if (lastIndex < text.length) {
		tokens.push({ type: 'literal', text: text.slice(lastIndex) })
	}
	return tokens
}

function splitOnFirst(text: string, separator: string): string[] {
	const idx = text.indexOf(separator)
	if (idx === -1) return [text]
	return [text.slice(0, idx), text.slice(idx + separator.length)]
}

/**
 * @displayName Parse Template Line
 * @strategicPurpose Compiles one `config.template` entry's raw `text` into the
 *   {@link ParsedLine} shape {@link resolveLine} consumes, applying the joiner
 *   precedence (first ` - `, then `|` within each side) once, up front — never
 *   per-card. Throws immediately (fail fast) on an unrecognized `{variable}`, naming
 *   it, rather than letting it render blank.
 * @tacticalObjective Pure, no Card/config dependency — safe to call once per generate.
 */
export function parseTemplateLine(line: { style: string; text: string }): ParsedLine {
	const dashParts = splitOnFirst(line.text, ' - ')
	const sides = dashParts.map((part) =>
		part.split('|').map((segmentText) => tokenizeSegmentText(segmentText.trim())),
	)
	return { style: line.style, sides }
}

function buildResolveContext(card: Card, config: LabelLayoutConfig): ResolveContext {
	return {
		statSegments: buildStatLineSegments(card),
		titleSize:
			card.title.length > 0
				? computeTitleFontHalfPoints(card.title, config)
				: config.titleFontHalfPoints,
		subtitleSize: card.subtitle ? computeSubtitleFontHalfPoints(card.subtitle, config) : undefined,
	}
}

function resolveSegment(
	tokens: TemplateSegment,
	card: Card,
	config: LabelLayoutConfig,
	ctx: ResolveContext,
): TemplateRunSpec[] | null {
	const resolved: (TemplateRunSpec | null)[] = tokens.map((token) =>
		token.type === 'variable'
			? (VARIABLE_CATALOG[token.name] as VariableDef).resolve(card, config, ctx)
			: null,
	)
	const anyRendered = resolved.some((r) => r !== null)
	if (!anyRendered) return null

	const out: TemplateRunSpec[] = []
	for (let i = 0; i < tokens.length; i++) {
		const token = tokens[i] as TemplateToken
		if (token.type === 'variable') {
			const r = resolved[i]
			if (r) out.push(r)
			continue
		}
		if (token.text.length === 0) continue
		if (token.text === ' ') {
			const prevToken = tokens[i - 1]
			const nextToken = tokens[i + 1]
			const prevAbsorbs =
				prevToken?.type === 'variable' &&
				resolved[i - 1] !== null &&
				Boolean(VARIABLE_CATALOG[prevToken.name]?.absorbSpaceAfter)
			const nextAbsorbs =
				nextToken?.type === 'variable' &&
				resolved[i + 1] !== null &&
				Boolean(VARIABLE_CATALOG[nextToken.name]?.absorbSpaceBefore)
			if (prevAbsorbs || nextAbsorbs) continue
		}
		const prevFlag = tokens[i - 1]?.type === 'variable' ? resolved[i - 1] !== null : null
		const nextFlag = tokens[i + 1]?.type === 'variable' ? resolved[i + 1] !== null : null
		const neighbors = [prevFlag, nextFlag].filter((f): f is boolean => f !== null)
		const keep = neighbors.length === 0 || neighbors.every((f) => f)
		if (keep) out.push({ kind: 'text', text: token.text })
	}
	return out.length > 0 ? out : null
}

function resolveSide(
	segments: TemplateSegment[],
	card: Card,
	config: LabelLayoutConfig,
	ctx: ResolveContext,
): TemplateRunSpec[] | null {
	const segRuns = segments
		.map((seg) => resolveSegment(seg, card, config, ctx))
		.filter((r): r is TemplateRunSpec[] => r !== null)
	if (segRuns.length === 0) return null
	const out: TemplateRunSpec[] = []
	segRuns.forEach((runs, i) => {
		if (i > 0) out.push({ kind: 'text', text: ' | ', style: 'statSeparator' })
		out.push(...runs)
	})
	return out
}

/**
 * @displayName Resolve Template Line
 * @strategicPurpose Renders one parsed template line for one card into an ordered
 *   list of {@link TemplateRunSpec}, or `null` when every segment collapsed empty (the
 *   paragraph is then omitted entirely — this is how the Subtitle line vanishes for
 *   subtitle-less cards). Implements the full collapsing contract: per-segment
 *   emptiness, per-literal keep/drop, sibling `|`-join, and dash-side `-`-join only
 *   when both sides are non-empty. See docs/template-language.md for worked examples.
 * @tacticalObjective Pure — no docx dependency. render.ts converts the returned specs
 *   to real `TextRun`/`ImageRun` instances.
 */
export function resolveLine(
	parsedLine: ParsedLine,
	card: Card,
	config: LabelLayoutConfig,
): TemplateRunSpec[] | null {
	const ctx = buildResolveContext(card, config)
	const sideResults = parsedLine.sides.map((segments) => resolveSide(segments, card, config, ctx))
	if (parsedLine.sides.length === 1) {
		return sideResults[0] ?? null
	}
	const [left, right] = sideResults
	if (left && right) {
		return [...left, { kind: 'text', text: ' - ', style: 'statSeparator' }, ...right]
	}
	return left ?? right ?? null
}
