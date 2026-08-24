// @manipulation Vendoring step, not a transform: copies the canonical
// formats.json from slicer2/slicer-dev verbatim into this repo's root, appending
// nothing. Declared effect: preserves (byte-for-byte copy).
import { createHash } from 'node:crypto'
import { copyFileSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')

const CANONICAL_PATH = join(REPO_ROOT, '..', 'slicer2', 'slicer-dev', 'formats.json')
const VENDORED_PATH = join(REPO_ROOT, 'formats.json')

function main(): void {
	const contents = readFileSync(CANONICAL_PATH)
	copyFileSync(CANONICAL_PATH, VENDORED_PATH)
	const sha256 = createHash('sha256').update(contents).digest('hex')
	console.log(`Vendored formats.json from ${CANONICAL_PATH}`)
	console.log(`sha256: ${sha256}`)
	console.log(
		'Provenance: canonical home is /Users/graham/Projects/slicer2/slicer-dev/formats.json — edit there, re-pull here with `npm run pull-formats`.',
	)
}

main()
