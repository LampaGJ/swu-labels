import { z } from 'zod'

/**
 * @displayName SWU Admin Card-List API Boundary Schema
 * @strategicPurpose Guards the untrusted foreign-data seam between the live
 *   https://admin.starwarsunlimited.com/api/card-list Strapi endpoint and this
 *   repo's ingest pipeline. Closed on every field the pipeline actually consumes
 *   (rarity name, type name, aspect name, expansion code, the numeric/boolean stat
 *   fields, variantOf/reprintOf presence, updatedAt) so a renamed upstream field or
 *   a new rarity/aspect/type value fails loudly at parse time instead of silently
 *   producing `undefined` downstream. Loose (`z.looseObject`) on every relation's
 *   `attributes` and on the top-level card attributes, so upstream fields this
 *   pipeline doesn't need (art URLs, styled-HTML text, traits, keywords, ...) pass
 *   through untouched rather than failing the parse.
 * @tacticalObjective One schema per Strapi relation shape (`data: {...} | null` for
 *   a to-one relation, `data: [...]` for a to-many relation) plus the top-level
 *   card and page-response schemas. `RARITY_NAMES`, `TYPE_NAMES`, and
 *   `ASPECT_NAMES` are the closed enums — deliberately the same value sets as
 *   schema.ts's CardSchema, since ingest.ts maps 1:1 into that shape.
 */

const RARITY_NAMES = ['Common', 'Uncommon', 'Rare', 'Legendary', 'Special'] as const
const TYPE_NAMES = [
	'Leader',
	'Base',
	'Unit',
	'Event',
	'Upgrade',
	'Token Unit',
	'Token Upgrade',
	'Force Token',
	'Credit Token',
] as const
const ASPECT_NAMES = [
	'Vigilance',
	'Command',
	'Aggression',
	'Cunning',
	'Villainy',
	'Heroism',
] as const

function toOneRelation<T extends z.ZodTypeAny>(attributesSchema: T) {
	return z.object({
		data: z
			.object({
				id: z.number(),
				attributes: attributesSchema,
			})
			.nullable(),
	})
}

function toManyRelation<T extends z.ZodTypeAny>(attributesSchema: T) {
	return z.object({
		data: z.array(
			z.object({
				id: z.number(),
				attributes: attributesSchema,
			}),
		),
	})
}

const ExpansionAttributesSchema = z.looseObject({
	code: z.string(),
})

const TypeAttributesSchema = z.looseObject({
	name: z.enum(TYPE_NAMES),
})

const RarityAttributesSchema = z.looseObject({
	name: z.enum(RARITY_NAMES),
})

const AspectAttributesSchema = z.looseObject({
	name: z.enum(ASPECT_NAMES),
})

/**
 * @displayName Card Attributes Schema
 * @strategicPurpose The Strapi `attributes` payload for one card-list entry.
 *   `reprintOf`/`variantOf` presence (not their content) drives canonicalization
 *   per slicer-dev CLAUDE.md: "the canonical printing has both as NULL."
 * @tacticalObjective Loose object; only the fields ingest.ts reads are named.
 */
export const CardAttributesSchema = z.looseObject({
	title: z.string(),
	subtitle: z.string().nullable(),
	cardNumber: z.number().nullable(),
	cost: z.number().nullable(),
	power: z.number().nullable(),
	hp: z.number().nullable(),
	upgradePower: z.number().nullable(),
	upgradeHp: z.number().nullable(),
	unique: z.boolean(),
	updatedAt: z.string(),
	expansion: toOneRelation(ExpansionAttributesSchema),
	type: toOneRelation(TypeAttributesSchema),
	rarity: toOneRelation(RarityAttributesSchema),
	aspects: toManyRelation(AspectAttributesSchema),
	aspectDuplicates: toManyRelation(AspectAttributesSchema),
	variantOf: toOneRelation(z.looseObject({})),
	reprintOf: toOneRelation(z.looseObject({})),
})

export type CardAttributes = z.infer<typeof CardAttributesSchema>

/**
 * @displayName API Card Schema
 * @strategicPurpose One entry in the `data[]` array of a card-list page response.
 * @tacticalObjective `{id, attributes}` — the Strapi entry envelope.
 */
export const ApiCardSchema = z.object({
	id: z.number(),
	attributes: CardAttributesSchema,
})

export type ApiCard = z.infer<typeof ApiCardSchema>

/**
 * @displayName API Page Response Schema
 * @strategicPurpose Guards one fetched page of the paginated card-list endpoint.
 * @tacticalObjective `{data: ApiCard[], meta: {pagination: {page, pageSize,
 *   pageCount, total}}}`; loose on other meta fields.
 */
export const ApiPageResponseSchema = z.object({
	data: z.array(ApiCardSchema),
	meta: z.looseObject({
		pagination: z.looseObject({
			page: z.number(),
			pageSize: z.number(),
			pageCount: z.number(),
			total: z.number(),
		}),
	}),
})

export type ApiPageResponse = z.infer<typeof ApiPageResponseSchema>
