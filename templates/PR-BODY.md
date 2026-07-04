Adds a FreeBSD daemonless image for **<app>** (`<owner/repo>` @ `<tag>`).

## What & why
<one paragraph: what the app is, and the key FreeBSD-specific decisions — runtime, DB strategy, why any swap was needed>

## FreeBSD notes
- `<e.g. node26 from the latest pkg branch; Temporal via polyfill>`
- `<e.g. libsql swapped for node:sqlite (no FreeBSD native build) — see BUILD-NOTES>`

## Tested
`dbuild build` + `dbuild test` against `ghcr.io/daemonless/base:<tag>`: <migrations run, /health 200, CIT screenshot matches baseline>.
Functional probe (`scripts/smoke-test.sh`): <the one request that proves the app does its job, and what it returned>.

## Provenance
Every non-boilerplate line in `Containerfile.j2`, the run scripts, and each patch traces to the PORT-BRIEF, a cookbook entry, or an error recorded in `PROCESS-LOG.md`. Exceptions: <none / list each with its justification>. `port-auditor` verdict: <CLEAN / findings addressed: …>.

## Viva (answered by the porting session, in its own words)
- **Why this base/runtime, and not the obvious alternative?** <…>
- **Riskiest dependency or assumption in this image?** <…>
- **What breaks first on the next upstream bump, and would it fail loud or silent?** <…>

## Tradeoffs / limitations
<e.g. local file DB only; uses a release-candidate API>

See `BUILD-NOTES.md` for the full rationale, patches, and drift guards.
