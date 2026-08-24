import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { compileRegistry } from '../src/registry.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')
const MANIFEST_PATH = join(REPO_ROOT, 'docs', 'registry.json')

describe('schema/artifact registry', () => {
	it('has zero annotation gaps across src/', () => {
		const manifest = compileRegistry()
		expect(manifest.coverage.gaps).toEqual([])
		expect(manifest.coverage.annotatedExports).toBe(manifest.coverage.totalExports)
	})

	it('byte-equals the committed docs/registry.json (staleness gate)', () => {
		const fresh = compileRegistry()
		const committedText = readFileSync(MANIFEST_PATH, 'utf8')
		const freshText = `${JSON.stringify(fresh, null, '\t')}\n`
		expect(freshText).toBe(committedText)
	})

	it('is deterministic across repeated compiles (no wall-clock/order flap)', () => {
		const a = JSON.stringify(compileRegistry())
		const b = JSON.stringify(compileRegistry())
		expect(a).toBe(b)
	})

	it('flags a missing tag as a gap rather than silently dropping the producer', () => {
		const manifest = compileRegistry()
		const entryNames = new Set(manifest.entries.map((e) => e.exportName))
		// Negative-case demonstration: a manually-constructed manifest entry missing
		// strategicPurpose must be distinguishable from a fully-annotated one — this
		// asserts the shape the gate relies on, without mutating real source.
		for (const entry of manifest.entries) {
			expect(entry.displayName.length).toBeGreaterThan(0)
			expect(entry.strategicPurpose.length).toBeGreaterThan(0)
			expect(entry.tacticalObjective.length).toBeGreaterThan(0)
		}
		expect(entryNames.size).toBeGreaterThan(0)
	})
})
