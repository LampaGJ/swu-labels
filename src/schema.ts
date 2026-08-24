import { z } from 'zod'

/**
 * @displayName Premier Card Boundary Schema
 * @strategicPurpose Guards the untrusted foreign-data seam between the pinned
 *   retrieve-cards JSON snapshot (data/snapshots/v<TAG>/per-set/*.json)
 *   and the Premier-format label transform. An unreviewed shape here is a silent-rot
 *   vector: a renamed field or a new rarity/aspect value must fail loudly rather than
 *   be coerced or defaulted away.
 * @tacticalObjective Parses one card record with `z.looseObject` (extra upstream
 *   fields pass through untouched) while `rarity` and each `aspects[]` entry are
 *   closed enums — an unknown rarity or aspect throws instead of defaulting.
 */
export const CardSchema = z.looseObject({
	title: z.string(),
	subtitle: z.string().nullable(),
	cost: z.number().nullable(),
	power: z.number().nullable().optional(),
	hp: z.number().nullable().optional(),
	upgrade_power: z.number().nullable().optional(),
	upgrade_hp: z.number().nullable().optional(),
	type_name: z.enum([
		'Leader',
		'Base',
		'Unit',
		'Event',
		'Upgrade',
		'Token Unit',
		'Token Upgrade',
		'Force Token',
		'Credit Token',
	]),
	rarity: z.enum(['Common', 'Uncommon', 'Rare', 'Legendary', 'Special']),
	expansion_code: z.string(),
	unique: z.boolean(),
	aspects: z.array(
		z.enum(['Vigilance', 'Command', 'Aggression', 'Cunning', 'Villainy', 'Heroism']),
	),
})

export type Card = z.infer<typeof CardSchema>

/**
 * @displayName Per-Set Card Array Schema
 * @strategicPurpose Same boundary as {@link CardSchema}, applied to the array shape
 *   each per-set snapshot file actually is on disk.
 * @tacticalObjective Array-of-CardSchema; parse failures name the offending index.
 */
export const CardArraySchema = z.array(CardSchema)

/**
 * @displayName Premier Formats Manifest Schema
 * @strategicPurpose Guards the foreign-data seam against the pinned formats.json,
 *   which names which set codes are legal in the Premier format today.
 * @tacticalObjective Parses only the `formats.premier.sets` path this transform
 *   actually consumes; extra top-level format entries pass through untouched.
 */
export const FormatsManifestSchema = z.looseObject({
	formats: z.looseObject({
		premier: z.looseObject({
			sets: z.array(z.string()),
		}),
	}),
})

export type FormatsManifest = z.infer<typeof FormatsManifestSchema>
