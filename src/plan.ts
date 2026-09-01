// @manipulation Pure projection stage. In: the same grouped LabelSlot map and
// LabelLayoutConfig that render.ts consumes. Out: a SheetPlan JSON document.
// Declared effect: preserves — every cell, paragraph and run is carried through
// verbatim; nothing is aggregated, summarized or dropped.
import type { LabelLayoutConfig } from './config.ts'
import type { Card } from './schema.ts'
import { type ParsedLine, type TemplateRunSpec, parseTemplateLine, resolveLine } from './template.ts'
import type { LabelSlot } from './transform.ts'
import { AVERY_5167_GEOMETRY } from './transform.ts'

/**
 * @displayName Sheet Plan Schema Version
 * @strategicPurpose A plan compared against a plan emitted by a different shape
 *   would produce a meaningless diff or, worse, a false match. Bumping this
 *   makes a shape change a loud failure at compare time rather than a quiet one.
 * @tacticalObjective Must equal `SheetPlan.currentSchemaVersion` in the Swift
 *   port (app/Sources/SWULabelsCore/Plan/SheetPlan.swift).
 */
export const SHEET_PLAN_SCHEMA_VERSION = 1

/** One resolved run, exactly as {@link resolveLine} produced it. */
export type PlanRun = TemplateRunSpec

/** One paragraph inside a label cell. */
export type PlanParagraph = { style: string; runs: PlanRun[] }

/** One label cell's resolved content. */
export type PlanCell = {
	kind: 'card' | 'divider' | 'empty'
	rarity?: Card['rarity']
	paragraphs: PlanParagraph[]
}

/** One grid row: always exactly one cell per label column. */
export type PlanRow = { cells: PlanCell[] }

/** One printed section. Every section starts a fresh sheet. */
export type PlanSection = { key: string; rows: PlanRow[] }

/** The sheet geometry a plan was laid out against. */
export type PlanGeometry = {
	pageWidthTwips: number
	pageHeightTwips: number
	marginTopTwips: number
	marginBottomTwips: number
	marginLeftTwips: number
	marginRightTwips: number
	columnWidthsTwips: number[]
	labelColumnIndices: number[]
	rowHeightTwips: number
	rowsPerSheet: number
}

/**
 * @displayName Sheet Plan
 * @strategicPurpose The fidelity-gate artifact. This is what goes in every cell
 *   of the sheet, captured immediately before render.ts turns it into docx
 *   objects — the last point at which the two implementations can be compared
 *   without one of them having to reproduce the other's serialization format.
 *   The Swift port emits the identical document, so structural equality of the
 *   two plans proves the port puts the same content in the same cell as the
 *   DOCX that was validated on paper.
 * @tacticalObjective Produced by {@link buildSheetPlan}; consumed by the Swift
 *   parity test (app/Tests/SWULabelsCoreTests/PlanParityTests.swift).
 */
export type SheetPlan = {
	schemaVersion: number
	geometry: PlanGeometry
	config: LabelLayoutConfig
	sections: PlanSection[]
}

/** Label columns per row. Derived, so it cannot drift from the geometry. */
const COLUMNS_PER_ROW = AVERY_5167_GEOMETRY.labelColumnIndices.length

/**
 * @displayName Plan Geometry From Pinned Constants
 * @strategicPurpose The plan is self-describing: a geometry change shows up as
 *   a plan diff rather than as a silently reprinted sheet.
 * @tacticalObjective Projects AVERY_5167_GEOMETRY into the flat, explicitly
 *   twips-suffixed shape the Swift `PlanGeometry` decodes.
 */
function planGeometry(): PlanGeometry {
	return {
		pageWidthTwips: AVERY_5167_GEOMETRY.page.width,
		pageHeightTwips: AVERY_5167_GEOMETRY.page.height,
		marginTopTwips: AVERY_5167_GEOMETRY.margins.top,
		marginBottomTwips: AVERY_5167_GEOMETRY.margins.bottom,
		marginLeftTwips: AVERY_5167_GEOMETRY.margins.left,
		marginRightTwips: AVERY_5167_GEOMETRY.margins.right,
		columnWidthsTwips: [...AVERY_5167_GEOMETRY.columnWidths],
		labelColumnIndices: [...AVERY_5167_GEOMETRY.labelColumnIndices],
		rowHeightTwips: AVERY_5167_GEOMETRY.rowHeightExact,
		rowsPerSheet: AVERY_5167_GEOMETRY.rowsPerSheet,
	}
}

/**
 * @displayName Divider Paragraph Style Ids
 * @strategicPurpose Mirrors the three hardcoded style ids `dividerCell` in
 *   render.ts uses. Kept as its own constant so the plan and the renderer cannot
 *   drift apart silently — a change in one is a visible change here.
 * @tacticalObjective Title, subtitle, stats, in divider line order.
 */
const DIVIDER_STYLE_IDS = ['cardTitle', 'cardSubtitle', 'cardStats'] as const

/**
 * @displayName Build Plan Cell
 * @strategicPurpose One place that turns a slot into its resolved cell, using
 *   the same {@link resolveLine} call render.ts makes — not a parallel
 *   reimplementation, which would let the plan agree with itself while
 *   disagreeing with the DOCX.
 * @tacticalObjective Card slots resolve through the parsed template, dropping
 *   lines that collapse empty; divider slots emit three fixed-style paragraphs.
 */
function buildPlanCell(
	slot: LabelSlot | null,
	config: LabelLayoutConfig,
	parsedTemplate: readonly ParsedLine[],
): PlanCell {
	if (!slot) {
		return { kind: 'empty', paragraphs: [] }
	}
	if (slot.kind === 'divider') {
		return {
			kind: 'divider',
			paragraphs: slot.lines.map((text, i) => ({
				style: DIVIDER_STYLE_IDS[i] as string,
				runs: [{ kind: 'text', text } as PlanRun],
			})),
		}
	}
	const paragraphs: PlanParagraph[] = []
	for (const parsedLine of parsedTemplate) {
		const runs = resolveLine(parsedLine, slot.card, config)
		if (!runs) continue
		paragraphs.push({ style: parsedLine.style, runs })
	}
	return { kind: 'card', rarity: slot.card.rarity, paragraphs }
}

/**
 * @displayName Build Sheet Plan
 * @strategicPurpose Emits the fidelity-gate artifact from exactly the inputs
 *   render.ts receives, so the plan and the DOCX cannot disagree about what a
 *   cell contains.
 * @tacticalObjective Chunks each section's slots into rows of
 *   {@link COLUMNS_PER_ROW}, padding the final row with empty cells, and
 *   resolves every cell through the once-parsed template.
 */
export function buildSheetPlan(
	groups: ReadonlyMap<string, LabelSlot[]>,
	config: LabelLayoutConfig,
): SheetPlan {
	const parsedTemplate = config.template.map(parseTemplateLine)
	const sections: PlanSection[] = []
	for (const [key, slots] of groups) {
		const rows: PlanRow[] = []
		for (let i = 0; i < slots.length; i += COLUMNS_PER_ROW) {
			const cells: PlanCell[] = []
			for (let col = 0; col < COLUMNS_PER_ROW; col++) {
				cells.push(buildPlanCell(slots[i + col] ?? null, config, parsedTemplate))
			}
			rows.push({ cells })
		}
		sections.push({ key, rows })
	}
	return {
		schemaVersion: SHEET_PLAN_SCHEMA_VERSION,
		geometry: planGeometry(),
		config,
		sections,
	}
}

/**
 * @displayName Canonical JSON Stringify
 * @strategicPurpose The gate compares two documents produced by two languages.
 *   Key insertion order is an implementation detail of whichever engine built
 *   the object, so it must not be able to fail a comparison. Sorting every
 *   object's keys removes that variable entirely.
 * @tacticalObjective Recursively sorts object keys, then stringifies with
 *   two-space indentation. Arrays keep their order — theirs is meaningful.
 *   `undefined` properties are dropped by JSON.stringify, matching Swift's
 *   `encodeIfPresent`.
 */
export function canonicalJSONStringify(value: unknown): string {
	return `${JSON.stringify(sortKeysDeep(value), null, 2)}\n`
}

function sortKeysDeep(value: unknown): unknown {
	if (Array.isArray(value)) {
		return value.map(sortKeysDeep)
	}
	if (value === null || typeof value !== 'object') {
		return value
	}
	const source = value as Record<string, unknown>
	const sorted: Record<string, unknown> = {}
	for (const key of Object.keys(source).sort()) {
		if (source[key] === undefined) continue
		sorted[key] = sortKeysDeep(source[key])
	}
	return sorted
}
