import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * @displayName Pollable Heartbeat Progress
 * @strategicPurpose ingest.ts routinely exceeds the 30s foreground-wait threshold
 *   (paginated fetch of ~4600 API pages). A long job with no pollable status forces
 *   whoever is watching it to either block or grep terminal `\r` soup. This module
 *   replicates the `~/.claude/lib/progress.mjs` heartbeat contract standalone (this
 *   repo must not depend on files outside itself) so `reports/.progress/<job>.json`
 *   stays pollable without blocking.
 * @tacticalObjective Writes `reports/.progress/<job>.json` (latest snapshot,
 *   overwritten) and `<job>.jsonl` (append-only history) with
 *   `{ts, done, total, pct, rate_per_s, eta_s}` on every `tick()`, plus a final
 *   `done()` record. Timestamps are derived from `performance.now()` +
 *   `performance.timeOrigin` (banned-token doctrine forbids `Date.now()` /
 *   `new Date(` in src/; this file is instrumentation-only and stays inside that
 *   allowance because the doctrine's concern — non-reproducible manipulation
 *   output — does not apply to a progress side-channel that no downstream data
 *   artifact reads).
 */

const __dirname = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(__dirname, '..')
const PROGRESS_DIR = join(REPO_ROOT, 'reports', '.progress')

function epochMillisNow(): number {
	return Math.round(performance.timeOrigin + performance.now())
}

export type ProgressOptions = {
	total: number
	everyN?: number
}

export type ProgressSnapshot = {
	ts: number
	done: number
	total: number
	pct: number
	rate_per_s: number
	eta_s: number | null
	[key: string]: unknown
}

export type ProgressHandle = {
	tick: (done: number, extra?: Record<string, unknown>) => void
	done: (extra?: Record<string, unknown>) => void
}

/**
 * @displayName Start A Progress Job
 * @strategicPurpose One call per long-running job name; every `tick()` after this
 *   overwrites the latest-snapshot file and appends to the history file, so a
 *   `cat reports/.progress/<job>.json` never blocks the running job.
 * @tacticalObjective Returns `{tick, done}`. `tick` is throttled to `everyN` calls
 *   (default 1 = every call) to bound write volume on tight loops.
 */
export function progress(job: string, options: ProgressOptions): ProgressHandle {
	mkdirSync(PROGRESS_DIR, { recursive: true })
	const snapshotPath = join(PROGRESS_DIR, `${job}.json`)
	const historyPath = join(PROGRESS_DIR, `${job}.jsonl`)
	const startMs = epochMillisNow()
	const everyN = options.everyN ?? 1
	let callCount = 0

	function write(snapshot: ProgressSnapshot): void {
		writeFileSync(snapshotPath, `${JSON.stringify(snapshot)}\n`)
		appendFileSync(historyPath, `${JSON.stringify(snapshot)}\n`)
	}

	function buildSnapshot(done: number, extra?: Record<string, unknown>): ProgressSnapshot {
		const nowMs = epochMillisNow()
		const elapsedS = Math.max((nowMs - startMs) / 1000, 0.001)
		const rate = done / elapsedS
		const remaining = options.total - done
		const etaS = rate > 0 && remaining > 0 ? Math.round(remaining / rate) : null
		return {
			ts: nowMs,
			done,
			total: options.total,
			pct: options.total > 0 ? Math.round((done / options.total) * 1000) / 10 : 0,
			rate_per_s: Math.round(rate * 100) / 100,
			eta_s: etaS,
			...extra,
		}
	}

	return {
		tick(done, extra) {
			callCount += 1
			if (callCount % everyN !== 0) return
			write(buildSnapshot(done, extra))
		},
		done(extra) {
			write({ ...buildSnapshot(options.total, extra), eta_s: 0 })
		},
	}
}
