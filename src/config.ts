/**
 * @displayName Premier Label Layout Config
 * @strategicPurpose Externalizes every v2 layout knob (alignment, icon baseline
 *   shift, hanging indent, set ordering, per-line font sizes and auto-shrink
 *   thresholds) into one typed, documented config object instead of scattering
 *   magic numbers across render.ts/transform.ts/index.ts. A future layout tweak
 *   (e.g. flipping setOrder to alphabetical) becomes a one-field edit here.
 * @tacticalObjective Defines {@link LabelLayoutConfig} and the single
 *   DEFAULT_CONFIG instance consumed by index.ts and render.ts.
 */
export interface LabelLayoutConfig {
	/** Paragraph alignment for all three label lines. Default: 'center'. */
	align: 'center' | 'left'
	/**
	 * OOXML run vertical position (`w:position`, half-points, negative = lowered)
	 * applied to the rarity icon's run so the icon optically sits on the stat
	 * line's text baseline instead of riding high above it. v2 shipped -4
	 * half-points (2pt) but user feedback found that too low; 0 (tried in
	 * between) was too high. Chosen v3 default: -2 half-points (1pt) for a
	 * ~0.14in icon beside 6pt (12-half-point) text.
	 */
	iconBaselineShiftHalfPoints: number
	/**
	 * Whether wrapped stat-line/title text indents under the title start rather
	 * than under the icon/cost. Only meaningful when `align: 'left'` — centered
	 * mode ignores it. Default: false (off in centered mode).
	 */
	hangingIndent: boolean
	/** Hanging indent depth in twips, used only when `hangingIndent` is true. */
	hangingIndentTwips: number
	/**
	 * Set ordering within an aspect group. 'release' = JTL, LOF, SEC, LAW, ASH,
	 * IBH (chronological release order — default). 'alphabetical' = fold-sorted
	 * set codes (deterministic, no localeCompare).
	 */
	setOrder: 'release' | 'alphabetical'
	/** Stat line (line 1) font size, in half-points. Default: 12 (6pt). */
	statLineFontHalfPoints: number
	/** Title (line 2) font size, in half-points, before auto-shrink. Default: 14 (7pt), bold. */
	titleFontHalfPoints: number
	/** Title font size, in half-points, once shrunk. Default: 12 (6pt). */
	titleShrinkFontHalfPoints: number
	/** Title character-length threshold (of `title`) above which the shrink size applies. Default: 30. */
	titleShrinkThreshold: number
	/** Subtitle (line 3) font size, in half-points, before auto-shrink. Default: 12 (6pt), italic. */
	subtitleFontHalfPoints: number
	/** Subtitle font size, in half-points, once shrunk. Default: 11. */
	subtitleShrinkFontHalfPoints: number
	/** Subtitle character-length threshold above which the shrink size applies. Default: 34. */
	subtitleShrinkThreshold: number
	/**
	 * Where the stats line ([icon] SET - stats) sits relative to title/subtitle.
	 * 'below' (v3 default): Title, Subtitle, Stats — the stats line reads last.
	 * 'above': Stats, Title, Subtitle — reproduces the v2 order.
	 */
	statsLinePosition: 'below' | 'above'
	/**
	 * Text prepended, as its own run, before the title text run on cards where
	 * `unique` is true — the SWU convention of marking a unique card with a
	 * diamond before its name. Default: '◊ ' (diamond + regular space). Set to
	 * '' to disable the marker without removing the mechanism.
	 */
	uniqueMarker: string
}

export const DEFAULT_CONFIG: LabelLayoutConfig = {
	align: 'center',
	iconBaselineShiftHalfPoints: -2,
	hangingIndent: false,
	hangingIndentTwips: 360,
	setOrder: 'release',
	statLineFontHalfPoints: 12,
	titleFontHalfPoints: 14,
	titleShrinkFontHalfPoints: 12,
	titleShrinkThreshold: 30,
	subtitleFontHalfPoints: 12,
	subtitleShrinkFontHalfPoints: 11,
	subtitleShrinkThreshold: 34,
	statsLinePosition: 'below',
	uniqueMarker: '◊ ',
}
