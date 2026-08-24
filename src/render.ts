import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import {
	AlignmentType,
	Document,
	HeightRule,
	type ICharacterStyleOptions,
	type IParagraphStyleOptions,
	ImageRun,
	Paragraph,
	RunProperties,
	Table,
	TableBorders,
	TableCell,
	TableRow,
	TextRun,
	VerticalAlign,
	WidthType,
} from 'docx'
import sharp from 'sharp'
import type { LabelLayoutConfig } from './config.ts'
import type { Card } from './schema.ts'
import type { AspectGroupKey, LabelLineKind } from './transform.ts'
import {
	AVERY_5167_GEOMETRY,
	buildStatLineSegments,
	computeHangingIndent,
	computeSubtitleFontHalfPoints,
	computeTitleFontHalfPoints,
	computeUniqueMarker,
	orderLabelLines,
	styleIdsForStatSuffix,
} from './transform.ts'

const RARITIES = ['common', 'uncommon', 'rare', 'legendary', 'special'] as const
type RarityFile = (typeof RARITIES)[number]

/** Target icon height in twips (~0.14in), and the px height we rasterize the PNG fallback at. */
const ICON_HEIGHT_TWIPS = 200
const ICON_HEIGHT_PX = 128

type RarityAsset = {
	svgBuffer: Buffer
	pngBuffer: Buffer
	widthPx: number
	heightPx: number
}

/**
 * @displayName Rasterize Rarity Icon Assets
 * @strategicPurpose Loads each of the five rarity SVGs once and rasterizes one PNG
 *   fallback per rarity via sharp, so the DOCX embeds five SVG buffers and five PNG
 *   buffers total — not one pair per label — keeping the document small.
 * @tacticalObjective Reads assets/rarities/{rarity}.svg, parses each SVG's viewBox to
 *   preserve aspect ratio, and rasterizes a PNG fallback at ICON_HEIGHT_PX height.
 */
export async function loadRarityAssets(
	assetsDir: string,
): Promise<Record<Card['rarity'], RarityAsset>> {
	const entries = await Promise.all(
		RARITIES.map(async (file) => {
			const svgPath = join(assetsDir, `${file}.svg`)
			const svgBuffer = readFileSync(svgPath)
			const svgText = svgBuffer.toString('utf8')
			const viewBoxMatch = svgText.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/)
			if (!viewBoxMatch) {
				throw new Error(`loadRarityAssets: no viewBox found in ${svgPath}`)
			}
			const viewBoxWidth = Number(viewBoxMatch[1])
			const viewBoxHeight = Number(viewBoxMatch[2])
			const aspect = viewBoxWidth / viewBoxHeight
			const heightPx = ICON_HEIGHT_PX
			const widthPx = Math.round(heightPx * aspect)
			const pngBuffer = await sharp(svgBuffer, { density: 384 })
				.resize({ height: heightPx, width: widthPx })
				.png()
				.toBuffer()
			return [file, { svgBuffer, pngBuffer, widthPx, heightPx }] as const
		}),
	)
	const byFile = Object.fromEntries(entries) as Record<RarityFile, RarityAsset>
	return {
		Common: byFile.common,
		Uncommon: byFile.uncommon,
		Rare: byFile.rare,
		Legendary: byFile.legendary,
		Special: byFile.special,
	}
}

const FONT = { name: 'Helvetica', hint: 'default' } as const

/** Named Word paragraph-style ids, one per label line kind (v3). */
const PARAGRAPH_STYLE_IDS: Record<LabelLineKind, string> = {
	title: 'cardTitle',
	subtitle: 'cardSubtitle',
	stats: 'cardStats',
}

/** Named Word character-style id for the rarity icon's own run (best-effort, see below). */
const RARITY_ICON_STYLE_ID = 'rarityIcon'

/** Named Word character-style id for the unique-card diamond marker run. */
const UNIQUE_MARKER_STYLE_ID = 'uniqueMarker'

/**
 * @displayName Build Named Word Styles
 * @strategicPurpose v3 core requirement: real DOCX paragraph/character styles
 *   (not just inline run formatting) so the user can restyle title, subtitle,
 *   stats, and each stat field independently from Word's style pane. Sizes are
 *   sourced from `config` so a config edit still reaches the style gallery,
 *   not just the first paragraph rendered.
 * @tacticalObjective Returns the `{ paragraphStyles, characterStyles }` shape
 *   consumed by `Document({ styles })`. All styles carry `quickFormat: true`
 *   so they surface in the gallery. Character styles are initialized to match
 *   the exact v2 inline look they replace (value runs bold, label runs
 *   regular, all at `config.statLineFontHalfPoints`).
 */
function buildStyles(config: LabelLayoutConfig): {
	paragraphStyles: IParagraphStyleOptions[]
	characterStyles: ICharacterStyleOptions[]
} {
	const alignment = alignmentFor(config)
	const paragraphSpacing = { before: 0, after: 0 }
	const paragraphStyles: IParagraphStyleOptions[] = [
		{
			id: PARAGRAPH_STYLE_IDS.title,
			name: 'Card Title',
			quickFormat: true,
			run: { font: FONT, size: config.titleFontHalfPoints, bold: true },
			paragraph: { alignment, spacing: paragraphSpacing },
		},
		{
			id: PARAGRAPH_STYLE_IDS.subtitle,
			name: 'Card Subtitle',
			quickFormat: true,
			run: { font: FONT, size: config.subtitleFontHalfPoints, italics: true },
			paragraph: { alignment, spacing: paragraphSpacing },
		},
		{
			id: PARAGRAPH_STYLE_IDS.stats,
			name: 'Card Stats',
			quickFormat: true,
			run: { font: FONT, size: config.statLineFontHalfPoints },
			paragraph: { alignment, spacing: paragraphSpacing },
		},
	]
	const size = config.statLineFontHalfPoints
	const characterStyles: ICharacterStyleOptions[] = [
		{ id: 'setName', name: 'Set Name', quickFormat: true, run: { font: FONT, size } },
		{ id: 'statSeparator', name: 'Stat Separator', quickFormat: true, run: { font: FONT, size } },
		{
			id: 'costValue',
			name: 'Cost Value',
			quickFormat: true,
			run: { font: FONT, size, bold: true },
		},
		{ id: 'costLabel', name: 'Cost Label', quickFormat: true, run: { font: FONT, size } },
		{
			id: 'powerValue',
			name: 'Power Value',
			quickFormat: true,
			run: { font: FONT, size, bold: true },
		},
		{ id: 'powerLabel', name: 'Power Label', quickFormat: true, run: { font: FONT, size } },
		{ id: 'hpValue', name: 'HP Value', quickFormat: true, run: { font: FONT, size, bold: true } },
		{ id: 'hpLabel', name: 'HP Label', quickFormat: true, run: { font: FONT, size } },
		{ id: RARITY_ICON_STYLE_ID, name: 'Rarity Icon', quickFormat: true, run: {} },
		{
			id: UNIQUE_MARKER_STYLE_ID,
			name: 'Unique Marker',
			quickFormat: true,
			run: { font: FONT, size: config.titleFontHalfPoints, bold: true },
		},
	]
	return { paragraphStyles, characterStyles }
}

/**
 * @displayName Inject Icon Baseline Shift
 * @strategicPurpose docx@9.7.1's `ImageRun` constructor unconditionally emits
 *   `this.root.push(new RunProperties({}))` — it never reads a `position`
 *   field off its own options at all, so passing `position` through the
 *   `ImageRunOptions` object (even via a cast) is silently dropped; verified
 *   empirically (a first attempt at that shape produced zero `w:position`
 *   elements in the unzipped document.xml). `root` is public at runtime
 *   (`protected` only in the `.d.ts`), so the working mechanism is to
 *   construct the ImageRun, then replace its already-pushed empty
 *   `RunProperties` (root[0]) with one built from
 *   `RunProperties({ position, style })` — `RunProperties` itself IS exported
 *   and DOES honor both fields, writing `position` verbatim into `w:val` with
 *   no unit conversion (a plain half-points integer string like "-2", not a
 *   `UniversalMeasure` string like "-2pt", which would emit an invalid
 *   `w:val="-2pt"`), and `style` into `w:rStyle` ahead of `w:position` in
 *   `root[0]`'s children — verified by reading the constructor source
 *   (`node_modules/docx/dist/index.mjs`): `if (options.style) this.push(new
 *   StringValueElement("w:rStyle", options.style))` runs before the
 *   `w:position` push, satisfying the CT_RPr child-order schema. So the v3
 *   `rarityIcon` character style attaches through the same root[0] patch
 *   mechanism as the baseline shift — no separate code path needed.
 * @tacticalObjective Mutates the constructed ImageRun's `root[0]` in place and
 *   returns it.
 */
function withIconBaselineShift(imageRun: ImageRun, halfPoints: number): ImageRun {
	const mutable = imageRun as unknown as { root: unknown[] }
	mutable.root[0] = new RunProperties({
		position: String(halfPoints) as never,
		style: RARITY_ICON_STYLE_ID,
	})
	return imageRun
}

function alignmentFor(
	config: LabelLayoutConfig,
): (typeof AlignmentType)[keyof typeof AlignmentType] {
	return config.align === 'center' ? AlignmentType.CENTER : AlignmentType.LEFT
}

function emptyCell(widthTwips: number): TableCell {
	return new TableCell({
		width: { size: widthTwips, type: WidthType.DXA },
		margins: { top: 0, bottom: 0, left: 40, right: 40 },
		children: [new Paragraph({ children: [] })],
	})
}

/**
 * @displayName Build Stat Line Paragraph
 * @strategicPurpose The stats line ([icon] SET - stats): rarity icon
 *   (baseline-shifted onto the text via `w:position`), the card's own set
 *   code (named-styled `setName`), then — only when
 *   {@link buildStatLineSegments} returns anything — a " - " separator and
 *   the data-driven stat segments joined by " | ", each field's numeric value
 *   and label run referencing its own named character style
 *   ({@link styleIdsForStatSuffix}) so the user can restyle per field from
 *   Word's style pane.
 * @tacticalObjective Single `cardStats`-styled paragraph per `config.align`;
 *   no inline size/bold on the runs — that comes from the named styles.
 */
function buildStatLineParagraph(
	card: Card,
	asset: RarityAsset,
	config: LabelLayoutConfig,
): Paragraph {
	const heightTwips = ICON_HEIGHT_TWIPS
	const widthTwipsIcon = Math.round((heightTwips * asset.widthPx) / asset.heightPx)
	const segments = buildStatLineSegments(card)

	const iconRun = withIconBaselineShift(
		new ImageRun({
			type: 'svg',
			data: asset.svgBuffer,
			fallback: { type: 'png', data: asset.pngBuffer },
			transformation: { width: widthTwipsIcon / 20, height: heightTwips / 20 },
		}),
		config.iconBaselineShiftHalfPoints,
	)

	const runs: (TextRun | ImageRun)[] = [
		iconRun,
		new TextRun({ text: ' ' }),
		new TextRun({ text: card.expansion_code, style: 'setName' }),
	]

	if (segments.length > 0) {
		runs.push(new TextRun({ text: ' - ', style: 'statSeparator' }))
		segments.forEach((segment, i) => {
			if (i > 0) {
				runs.push(new TextRun({ text: ' | ', style: 'statSeparator' }))
			}
			const ids = styleIdsForStatSuffix(segment.suffix)
			runs.push(new TextRun({ text: segment.bold, style: ids.value }))
			runs.push(new TextRun({ text: ` ${segment.suffix}`, style: ids.label }))
		})
	}

	return new Paragraph({
		style: PARAGRAPH_STYLE_IDS.stats,
		alignment: alignmentFor(config),
		indent: computeHangingIndent(config),
		spacing: { before: 0, after: 0 },
		children: runs,
	})
}

/**
 * @displayName Build Title Paragraph
 * @strategicPurpose v3: Title is line 1 (see {@link orderLabelLines}). Bold
 *   comes from the `cardTitle` named style; only the per-card auto-shrink
 *   size stays a run-level override, since the shrink value is computed per
 *   card and cannot live in a static style. SWU convention: a unique card's
 *   diamond marker is its own run, in the `uniqueMarker` named style, placed
 *   before the title run — sharing the same per-card auto-shrink size
 *   override as the title run so the two shrink together.
 * @tacticalObjective `cardTitle`-styled paragraph with zero spacing
 *   before/after (belt-and-suspenders alongside the style's own spacing).
 */
function buildTitleParagraph(card: Card, config: LabelLayoutConfig): Paragraph {
	const titleSize = computeTitleFontHalfPoints(card.title, config)
	const markerText = computeUniqueMarker(card, config)
	const children: TextRun[] = []
	if (markerText) {
		children.push(new TextRun({ text: markerText, style: UNIQUE_MARKER_STYLE_ID, size: titleSize }))
	}
	children.push(new TextRun({ text: card.title, size: titleSize }))
	return new Paragraph({
		style: PARAGRAPH_STYLE_IDS.title,
		alignment: alignmentFor(config),
		indent: computeHangingIndent(config),
		spacing: { before: 0, after: 0 },
		children,
	})
}

/**
 * @displayName Build Subtitle Paragraph
 * @strategicPurpose v3: Subtitle is line 2, directly under Title with ZERO
 *   paragraph spacing between them (see {@link orderLabelLines}). Italics
 *   comes from the `cardSubtitle` named style; only the per-card auto-shrink
 *   size stays a run-level override.
 * @tacticalObjective `cardSubtitle`-styled paragraph with zero spacing
 *   before/after (belt-and-suspenders alongside the style's own spacing).
 */
function buildSubtitleParagraph(subtitle: string, config: LabelLayoutConfig): Paragraph {
	return new Paragraph({
		style: PARAGRAPH_STYLE_IDS.subtitle,
		alignment: alignmentFor(config),
		indent: computeHangingIndent(config),
		spacing: { before: 0, after: 0 },
		children: [
			new TextRun({
				text: subtitle,
				size: computeSubtitleFontHalfPoints(subtitle, config),
			}),
		],
	})
}

/**
 * @displayName Build Label Cell Paragraphs
 * @strategicPurpose v3 reorder: paragraph construction order is driven by
 *   {@link orderLabelLines}, not by call order in source — so
 *   `statsLinePosition: 'above'` reproduces the exact v2 order with no
 *   duplicated branch here.
 * @tacticalObjective Dispatches each `LabelLineKind` to its builder in the
 *   order `orderLabelLines` returns.
 */
function buildLabelCellParagraphs(
	card: Card,
	asset: RarityAsset,
	config: LabelLayoutConfig,
): Paragraph[] {
	const order = orderLabelLines(config, Boolean(card.subtitle))
	return order.map((kind) => {
		if (kind === 'title') return buildTitleParagraph(card, config)
		if (kind === 'stats') return buildStatLineParagraph(card, asset, config)
		// kind === 'subtitle': only present in `order` when card.subtitle is set.
		return buildSubtitleParagraph(card.subtitle as string, config)
	})
}

function labelCell(
	card: Card,
	assets: Record<Card['rarity'], RarityAsset>,
	widthTwips: number,
	config: LabelLayoutConfig,
): TableCell {
	const asset = assets[card.rarity]
	const paragraphs = buildLabelCellParagraphs(card, asset, config)
	return new TableCell({
		width: { size: widthTwips, type: WidthType.DXA },
		margins: { top: 0, bottom: 0, left: 40, right: 40 },
		verticalAlign: VerticalAlign.CENTER,
		children: paragraphs,
	})
}

function labelRow(
	cards: (Card | null)[],
	assets: Record<Card['rarity'], RarityAsset>,
	config: LabelLayoutConfig,
): TableRow {
	const cols = AVERY_5167_GEOMETRY.columnWidths
	const cells: TableCell[] = []
	let labelIndex = 0
	for (let col = 0; col < cols.length; col++) {
		const width = cols[col] as number
		if ((AVERY_5167_GEOMETRY.labelColumnIndices as readonly number[]).includes(col)) {
			const card = cards[labelIndex]
			labelIndex += 1
			cells.push(card ? labelCell(card, assets, width, config) : emptyCell(width))
		} else {
			cells.push(emptyCell(width))
		}
	}
	return new TableRow({
		height: { value: AVERY_5167_GEOMETRY.rowHeightExact, rule: HeightRule.EXACT },
		children: cells,
	})
}

/**
 * @displayName Build One Aspect-Group Label Table
 * @strategicPurpose Renders the 4-col x N-row Avery 5167 grid for one aspect group.
 *   The table is the section's first child so row 1 sits exactly at the top margin,
 *   per spec — no pageBreakBefore paragraphs, which would push it down.
 * @tacticalObjective Fixed-layout borderless table, columnWidths from
 *   AVERY_5167_GEOMETRY, zero indent/cell-margin-top/bottom, one row per 4 labels.
 */
export function buildLabelTable(
	cards: readonly Card[],
	assets: Record<Card['rarity'], RarityAsset>,
	config: LabelLayoutConfig,
): Table {
	const rows: TableRow[] = []
	for (let i = 0; i < cards.length; i += 4) {
		const chunk: (Card | null)[] = [
			cards[i] ?? null,
			cards[i + 1] ?? null,
			cards[i + 2] ?? null,
			cards[i + 3] ?? null,
		]
		rows.push(labelRow(chunk, assets, config))
	}
	return new Table({
		rows,
		columnWidths: [...AVERY_5167_GEOMETRY.columnWidths],
		layout: 'fixed' as never,
		indent: { size: 0, type: WidthType.DXA },
		borders: TableBorders.NONE,
		margins: { top: 0, bottom: 0, left: 40, right: 40 },
	})
}

/**
 * @displayName Build Premier Labels DOCX Document
 * @strategicPurpose Assembles one Document with one section per non-empty aspect
 *   group, each section a fresh Avery 5167 sheet, per spec.
 * @tacticalObjective Iterates the grouped/sorted cards in ASPECT_GROUP_ORDER,
 *   builds one section per group with the label table as its first child and a
 *   minimal trailing paragraph so docx's forced final paragraph never adds a
 *   phantom page.
 */
export function buildDocument(
	groups: ReadonlyMap<AspectGroupKey, Card[]>,
	assets: Record<Card['rarity'], RarityAsset>,
	config: LabelLayoutConfig,
): Document {
	const sections = [...groups.entries()].map(([, cards]) => ({
		properties: {
			page: {
				size: { width: AVERY_5167_GEOMETRY.page.width, height: AVERY_5167_GEOMETRY.page.height },
				margin: {
					top: AVERY_5167_GEOMETRY.margins.top,
					bottom: AVERY_5167_GEOMETRY.margins.bottom,
					left: AVERY_5167_GEOMETRY.margins.left,
					right: AVERY_5167_GEOMETRY.margins.right,
				},
			},
		},
		children: [
			buildLabelTable(cards, assets, config),
			new Paragraph({
				alignment: AlignmentType.LEFT,
				spacing: { before: 0, after: 0, line: 20, lineRule: 'exact' as never },
				children: [new TextRun({ text: '', size: 2 })],
			}),
		],
	}))
	return new Document({ styles: buildStyles(config), sections })
}
