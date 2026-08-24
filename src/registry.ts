// @manipulation This module is a read-only introspection node, not a data
// transform — it never touches card data. In-schema: the TSDoc comments and export
// declarations of every src/*.ts source file (parsed via the TypeScript Compiler
// API, never executed). Out-schema: RegistryManifest (this file), written to
// docs/registry.json. Declared effect: preserves — every discovered exported
// producer is represented in the manifest, annotated fully or gap-tracked, never
// silently dropped.
//
// BANNED in this file (write-time hook enforced, doctrine: reproducible data
// manipulation): Date.now(), new Date(, Math.random(), localeCompare. The manifest
// carries no wall-clock timestamp; ordering is deterministic string-sort
// (codepoint `<`/`>`), never locale-aware.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import ts from 'typescript'

/**
 * @displayName Registry Entry Kind
 * @strategicPurpose Classifies each annotated producer so the manifest reads as a
 *   contract catalog (Data Contract Specification vocabulary) rather than an
 *   undifferentiated dump — a reader scanning for "which of these guard a foreign-
 *   data boundary" filters on `kind === 'schema'` without opening every entry.
 * @tacticalObjective One of the six artifact-type buckets this project's producers
 *   fall into: `schema` (a Zod boundary schema), `function` (a pure transform/IO
 *   step), `const` (a pinned data table/config), `type` (a derived or standalone
 *   type export). `db-row` / `file-artifact` / `event` / `subprocess-handoff` /
 *   `column-blob` are reserved kinds this project's data-flow section documents at
 *   the pipeline level (this repo has no DB, event bus, or subprocess IPC — every
 *   producer here is a schema/function/const/type export).
 */
export type RegistryEntryKind = 'schema' | 'function' | 'const' | 'type'

/**
 * @displayName Registry Entry
 * @strategicPurpose One row of the compiled manifest — the unit a human or agent
 *   reading docs/registry.json actually consumes to answer "why does this producer
 *   exist and what does it do at its boundary," per the schema-registry doctrine.
 * @tacticalObjective `{file, exportName, displayName, strategicPurpose,
 *   tacticalObjective, kind}` plus an optional `canonicalRef` set only when this
 *   export's tags were inherited (never fabricated) from a structurally-linked
 *   sibling export.
 */
export type RegistryEntry = {
	file: string
	exportName: string
	displayName: string
	strategicPurpose: string
	tacticalObjective: string
	kind: RegistryEntryKind
	/** Set when this export's annotation is inherited from a canonical sibling
	 * export it is structurally derived from (`z.infer<typeof X>` or
	 * `(typeof X)[number]`), per the "type-only export may share its schema's
	 * block" allowance — never fabricated, always a real AST-verified reference. */
	canonicalRef?: string
}

/**
 * @displayName Registry Manifest
 * @strategicPurpose The complete, deterministic, agent-readable roll-up this
 *   whole architecture exists to produce — one JSON file giving full end-to-end
 *   data-flow visibility (inputs/emissions to outputs/ingestions) plus an honest
 *   gap list, never silently dropping an un-annotated producer.
 * @tacticalObjective `{dataFlow, entries, coverage}` — returned by
 *   {@link compileRegistry} and serialized verbatim (stable key order, no
 *   timestamps) to docs/registry.json.
 */
export type RegistryManifest = {
	dataFlow: {
		description: string
		stages: Array<{ id: string; description: string }>
	}
	entries: RegistryEntry[]
	coverage: {
		annotatedExports: number
		totalExports: number
		coveragePct: number
		gaps: string[]
	}
}

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')
const SRC_DIR = join(REPO_ROOT, 'src')

const REQUIRED_TAGS = ['displayName', 'strategicPurpose', 'tacticalObjective'] as const

function isExportedNode(node: ts.Node): boolean {
	if (!ts.canHaveModifiers(node)) return false
	const mods = ts.getModifiers(node)
	return !!mods && mods.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)
}

function tagsOf(node: ts.Node): Partial<Record<(typeof REQUIRED_TAGS)[number], string>> {
	const out: Partial<Record<(typeof REQUIRED_TAGS)[number], string>> = {}
	for (const tag of ts.getJSDocTags(node)) {
		const name = tag.tagName.text
		if ((REQUIRED_TAGS as readonly string[]).includes(name)) {
			const text = ts.getTextOfJSDocComment(tag.comment)
			if (text) out[name as (typeof REQUIRED_TAGS)[number]] = text.trim()
		}
	}
	return out
}

function hasAllTags(tags: Partial<Record<(typeof REQUIRED_TAGS)[number], string>>): boolean {
	return REQUIRED_TAGS.every((t) => Boolean(tags[t]))
}

/** Extracts the identifier referenced by a `z.infer<typeof X>` or `(typeof X)[number]`
 * type-node's source text — the AST-verified structural link that lets a type-only
 * export inherit its canonical schema/const's annotation rather than needing its own. */
function canonicalIdentifierFromTypeText(typeText: string): string | null {
	const match = typeText.match(/typeof\s+([A-Za-z_$][\w$]*)/)
	return match ? (match[1] as string) : null
}

type RawExport = {
	name: string
	node: ts.Node
	kind: RegistryEntryKind
	typeNodeText?: string
}

function collectExports(sourceFile: ts.SourceFile): RawExport[] {
	const out: RawExport[] = []
	for (const statement of sourceFile.statements) {
		if (!isExportedNode(statement)) continue

		if (ts.isFunctionDeclaration(statement) && statement.name) {
			out.push({ name: statement.name.text, node: statement, kind: 'function' })
			continue
		}

		if (ts.isVariableStatement(statement)) {
			for (const decl of statement.declarationList.declarations) {
				if (!ts.isIdentifier(decl.name)) continue
				const name = decl.name.text
				const kind: RegistryEntryKind = name.endsWith('Schema') ? 'schema' : 'const'
				out.push({ name, node: statement, kind })
			}
			continue
		}

		if (ts.isTypeAliasDeclaration(statement)) {
			out.push({
				name: statement.name.text,
				node: statement,
				kind: 'type',
				typeNodeText: statement.type.getText(sourceFile),
			})
			continue
		}

		if (ts.isInterfaceDeclaration(statement)) {
			out.push({ name: statement.name.text, node: statement, kind: 'type' })
		}
	}
	return out
}

/**
 * @displayName Compile Schema/Artifact Registry
 * @strategicPurpose The single deterministic entry point that turns co-located
 *   TSDoc tags across every src/*.ts producer into one agent-readable, end-to-end
 *   data-flow manifest — the roll-up this repo's registry discipline exists to
 *   produce. Called both by the `registry` npm script (to write docs/registry.json)
 *   and by test/registry.test.ts (to detect staleness/drift without a subprocess).
 * @tacticalObjective Parses every src/*.ts file with the TS Compiler API (never
 *   executes source), extracts `@displayName`/`@strategicPurpose`/`@tacticalObjective`
 *   from every exported function/const/schema/type, resolves type-only exports
 *   structurally derived from an annotated sibling (`z.infer<typeof X>`,
 *   `(typeof X)[number]`) as canonical-ref-covered, and returns one sorted,
 *   timestamp-free {@link RegistryManifest}.
 */
export function compileRegistry(): RegistryManifest {
	const fileNames = readdirSync(SRC_DIR)
		.filter((f) => f.endsWith('.ts'))
		.sort()

	const entries: RegistryEntry[] = []
	const gaps: string[] = []

	for (const fileName of fileNames) {
		const filePath = join(SRC_DIR, fileName)
		const relFile = `src/${fileName}`
		const text = readFileSync(filePath, 'utf8')
		const sourceFile = ts.createSourceFile(filePath, text, ts.ScriptTarget.Latest, true)
		const rawExports = collectExports(sourceFile)
		const byName = new Map(rawExports.map((e) => [e.name, e]))

		for (const exp of rawExports) {
			const ownTags = tagsOf(exp.node)
			if (hasAllTags(ownTags)) {
				entries.push({
					file: relFile,
					exportName: exp.name,
					displayName: ownTags.displayName as string,
					strategicPurpose: ownTags.strategicPurpose as string,
					tacticalObjective: ownTags.tacticalObjective as string,
					kind: exp.kind,
				})
				continue
			}

			const canonicalName = exp.typeNodeText
				? canonicalIdentifierFromTypeText(exp.typeNodeText)
				: null
			const canonical = canonicalName ? byName.get(canonicalName) : undefined
			const canonicalTags = canonical ? tagsOf(canonical.node) : undefined
			if (canonical && canonicalTags && hasAllTags(canonicalTags)) {
				entries.push({
					file: relFile,
					exportName: exp.name,
					displayName: canonicalTags.displayName as string,
					strategicPurpose: canonicalTags.strategicPurpose as string,
					tacticalObjective: canonicalTags.tacticalObjective as string,
					kind: exp.kind,
					canonicalRef: canonicalName as string,
				})
				continue
			}

			gaps.push(`${relFile}#${exp.name}`)
		}
	}

	entries.sort((a, b) => {
		if (a.file !== b.file) return a.file < b.file ? -1 : 1
		if (a.exportName !== b.exportName) return a.exportName < b.exportName ? -1 : 1
		return 0
	})
	gaps.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))

	const totalExports = entries.length + gaps.length
	const coveragePct =
		totalExports === 0 ? 100 : Math.round((entries.length / totalExports) * 1000) / 10

	return {
		dataFlow: {
			description:
				'Official SWU admin card-list API -> src/ingest.ts (boundary-parsed via ' +
				'api-schema.ts) -> data/snapshots/v<tag>/per-set/*.json + meta.json + ' +
				'vendored formats.json -> src/index.ts (boundary-parsed via schema.ts) -> ' +
				'src/transform.ts + src/template.ts (pure transform) -> src/render.ts ' +
				'(docx materialization) -> reports/premier-labels-avery5167-v<tag>.docx + ' +
				'reports/premier-labels-avery5167-v<tag>.replay.json. formats.json is ' +
				'vendored verbatim from slicer-dev (src/pull-formats.ts); its canonical home ' +
				'is /Users/graham/Projects/slicer2/slicer-dev/formats.json.',
			stages: [
				{
					id: 'ingest.fetch',
					description:
						'src/ingest.ts fetches https://admin.starwarsunlimited.com/api/card-list, ' +
						'paginated, 3-way concurrent with retry; parsed at the boundary by ' +
						'api-schema.ts (ApiPageResponseSchema).',
				},
				{
					id: 'ingest.write-snapshot',
					description:
						'src/ingest.ts filters to canonical printings, maps to the pinned Card ' +
						'shape (schema.ts), sorts stably, and writes ' +
						'data/snapshots/v<tag>/per-set/<CODE>.json + meta.json + formats.json.',
				},
				{
					id: 'generate.load-snapshot',
					description:
						'src/index.ts reads a pinned snapshot directory, parses each per-set file ' +
						'at the boundary with schema.ts (CardArraySchema), and selects sets via ' +
						'formats.premier.sets intersected with files present on disk.',
				},
				{
					id: 'generate.transform',
					description:
						'src/transform.ts dedupes across sets (dedupeCards), groups by aspect then ' +
						'set (groupByAspectThenSet); src/template.ts resolves the configured ' +
						'per-line template into renderer-agnostic run specs.',
				},
				{
					id: 'generate.render',
					description:
						'src/render.ts materializes the Avery 5167 label grid as a docx Document; ' +
						'src/index.ts packs it to reports/premier-labels-avery5167-v<tag>.docx and ' +
						'writes the {inputHash, codeCommit, outputHash} replay record alongside it.',
				},
			],
		},
		entries,
		coverage: {
			annotatedExports: entries.length,
			totalExports,
			coveragePct,
			gaps,
		},
	}
}

const MANIFEST_PATH = join(REPO_ROOT, 'docs', 'registry.json')

function serialize(manifest: RegistryManifest): string {
	return `${JSON.stringify(manifest, null, '\t')}\n`
}

function main(): void {
	const checkMode = process.argv.includes('--check')
	const manifest = compileRegistry()
	const fresh = serialize(manifest)

	if (checkMode) {
		let committed: string
		try {
			committed = readFileSync(MANIFEST_PATH, 'utf8')
		} catch {
			console.error(`registry --check: ${MANIFEST_PATH} does not exist — run \`npm run registry\`.`)
			process.exitCode = 1
			return
		}
		if (committed !== fresh) {
			console.error(
				'registry --check: docs/registry.json is stale relative to source. Run `npm run registry` and commit the result.',
			)
			process.exitCode = 1
			return
		}
		if (manifest.coverage.gaps.length > 0) {
			console.error(
				`registry --check: ${manifest.coverage.gaps.length} annotation gap(s): ${manifest.coverage.gaps.join(', ')}`,
			)
			process.exitCode = 1
			return
		}
		console.log(
			`registry --check: OK (${manifest.coverage.annotatedExports}/${manifest.coverage.totalExports} = ${manifest.coverage.coveragePct}% coverage, 0 gaps)`,
		)
		return
	}

	writeFileSync(MANIFEST_PATH, fresh)
	console.log(
		`Wrote ${MANIFEST_PATH} (${manifest.coverage.annotatedExports}/${manifest.coverage.totalExports} = ${manifest.coverage.coveragePct}% coverage, ${manifest.coverage.gaps.length} gap(s))`,
	)
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url)
if (isMain) {
	main()
}
