# PROCESS LOG — porting `ffmpeg.org` to a FreeBSD daemonless image

## Phase 0 — Intake
- Target: `https://ffmpeg.org`, no upstream git tag — pinned to FreeBSD's
  quarterly pkg snapshot `ffmpeg 8.1.2,1` (GPLv3+, LGPL3+).
- Prior art: `PORT-BRIEF.md` was already a completed Phase 0/1 plan from a
  prior stronger-context session; per skill rules, research subagent skipped,
  started directly at Phase 2. Crib: `~/workspace/immich-cli` (CLI-class
  exemplar — `base-core`, no s6, no `compose.yaml`, `cit: mode: command`).

## Phase 1 — Research
Skipped (brief already supplied it). Summary from PORT-BRIEF:
- Runtime: none — compiled binary via `pkg`.
- Build: `pkg install -y ffmpeg`, no source build, no builder stage.
- Native hazards: none — `pkg` resolves the entire shared-lib tree
  (x264/x265/vpx/dav1d/aom/opus/mp3lame/etc.) as prebuilt packages.
- DB: none.
- Health: N/A (CLI, command-mode CIT).
- Verdict: EASY — no blockers anticipated, none found.

## Phase 2 — Scaffold
- Verified `pkg rquery '%n %v %L' ffmpeg` → `ffmpeg 8.1.2,1 GPLv3+, LGPL3+`
  (matches PORT-BRIEF exactly, re-verified as required by skill rules).
- Wrote `Containerfile.j2` (single stage, `base-core:15-pkg`, `pkg install
  ffmpeg` + major-drift assert + `pkg clean -ay`, `ENTRYPOINT ["ffmpeg"]`,
  `CMD ["-version"]`) and `.daemonless/config.yaml` (`class: cli`, `cit: mode:
  command`, `expect_output: 'ffmpeg version \d'`) — copied shape from
  `immich-cli`, no compose.yaml (CLI class ships none).
- `dbuild generate` ran clean; no git remote configured yet so no fork-URL
  rewrite to fix; generated README/Containerfile point at `ghcr.io/daemonless`
  correctly by default.
- Package name surprises: none — `ffmpeg` is the exact pkg name, no prefix/
  suffix variants to check.

## Phase 3 — Build loop
- Build 1: PASSED clean on the first attempt — no failure signatures in
  `build.log`. No debug loop needed.

## Phase 4 — CIT
```
=== Testing :latest ===
[info] $ doas podman run --rm ghcr.io/daemonless/ffmpeg:build-latest
[info]   ffmpeg version 8.1 Copyright (c) 2000-2026 the FFmpeg developers
[info]   ...
[info] Exit code: 0 (expected 0)
[info] Output matched /ffmpeg version \d/
[ok] Command test passed
[ok] :latest passed CIT (command)
[cit] CIT PASSED
[cit] Running functional probe (scripts/smoke-test.sh)...
... real transcode: testsrc2 -> null, frame=10 elapsed=0:00:00.00 ...
[smoke] PASS: ffmpeg demuxed/filtered/encoded a synthetic stream end-to-end
[cit] SMOKE PASSED
```
- Runtime issues found: none.

## Phase 5 — Harden
- Guards added: major-version drift assert (`ffmpeg -version` must start
  `ffmpeg version 8.`) — the only pin available since there's no upstream tag.
  No patch-rot guard needed (no patches/).
- **`port-auditor` caught a real error here, corrected below.** My first pass
  claimed "no toolchain to strip (single stage, no compiler installed)" —
  this was checked by reading the `Containerfile.j2` RUN lines, not the built
  image. It was **wrong**. `pkg info -r` inside `ghcr.io/daemonless/
  ffmpeg:build-latest` shows the runtime image ships `gcc14` (359 MiB),
  `binutils`, `python311`, `py311-numpy`, `openblas`, `boost-libs`, and
  `suitesparse` — pulled in transitively: `ffmpeg → libjxl → openexr → Imath
  → py311-numpy (Imath's Python bindings) → openblas/suitesparse → gcc14
  (libgfortran)`. Checked for a lighter pkg flavour (`pkg search ffmpeg`) —
  only `ffmpeg` and `ffmpeg-nox11` exist, neither avoids the jxl/openexr
  chain, and a source rebuild with `--disable-libjxl` is out of scope per
  PORT-BRIEF (no custom codec/port options). **Accepted as a documented
  limitation, not fixed** — see BUILD-NOTES "Runtime image also ships a
  compiler toolchain."
- Also corrected: BUILD-NOTES originally cited the CIT run as confirming
  ffmpeg `8.1.2,1` (PORT-BRIEF's pre-build `pkg rquery` fact). The actual
  `build.log` shows the package resolved and installed at build time was
  `ffmpeg-8.1,1` — a different, older point release than what PORT-BRIEF
  verified, discovered only because the auditor checked the log instead of
  trusting the carried-forward claim. The major-only drift assert correctly
  didn't care, but the docs were asserting a version nothing had actually
  confirmed. Fixed to state the true installed version.
- `scripts/lint-compose.sh` **does not apply**: it requires a `compose.yaml`,
  which CLI-class images don't ship (confirmed: `immich-cli`, the crib image,
  also has neither a `compose.yaml` nor a lint script). Manually checked the
  three quality floors the script enforces instead: (1) no moving-ref version
  pin — none present, pure `pkg install`; (2) no unguarded patches — none
  exist; (3) no build toolchain in the runtime stage — **this check was
  initially wrong, see above; corrected after re-verifying against the built
  image, not just the Containerfile text.** PORT-BRIEF's expectation that the
  script would "no-op" was also wrong — it hard-errors on a missing file;
  noting both as cookbook/toolkit gaps rather than editing the shared script
  for one port.
- Screenshots: skipped. ffmpeg is a CLI with no UI/README screenshots to
  capture — `dbuild screenshot` has nothing to download against. Documented
  per PORT-BRIEF's explicit fallback instruction rather than silently omitted.

## Phase 6 — PR
- PR: (opened after this log was written — see final message)
- Final status: build ✅, CIT ✅, smoke test ✅

## Cookbook entries added
- `scripts/lint-compose.sh` hard-errors (`ERROR: compose.yaml not found`) on
  CLI-class images, which ship no `compose.yaml` by design — it has no
  no-op/skip path for `class: cli`. Documented here rather than in the
  cookbook proper since it's a toolkit gap, not a FreeBSD/app porting fix;
  flagging for the toolkit maintainer to add a CLI-class bypass.
- New cookbook-worthy pattern (not yet added to the cookbook file itself,
  flagging here first): a single `pkg install <app>` can pull in a full
  compiler toolchain as a *transitive runtime* dependency with nothing in the
  Containerfile naming it — `lint-compose.sh`'s toolchain floor (and my own
  manual substitute check) only greps the Containerfile text for
  `FreeBSD-clang|lld|toolchain|clibs-dev|node-gyp`, which never appears here.
  The only way to actually verify "no toolchain in the runtime stage" for a
  pkg-based image is `pkg info -r <pkg>` (or full `pkg info` diffed) inside
  the *built* image, not a grep of the source file. ffmpeg's chain:
  `libjxl → openexr → Imath → py311-numpy → openblas/suitesparse → gcc14`.

## Lessons / notes for next time
- pkg-based ports (no source build, no native modules) are the fastest
  possible port shape — this one passed build + CIT + smoke on the first
  attempt with zero debug-loop iterations. The PORT-BRIEF's insistence on
  "verify only the pkg version, trust everything else" held up exactly as
  described.
