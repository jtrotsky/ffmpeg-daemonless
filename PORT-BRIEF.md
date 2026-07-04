# PORT-BRIEF — ffmpeg

Completed Phase 0/1 port plan (researched 2026-07-04 by a stronger-context
session; facts below are verified unless marked VERIFY). Per the skill's
execution-discipline rules: trust these facts, re-verify only the pkg version,
skip the research subagent, start at Phase 2.

## Mission
Build the FreeBSD daemonless image for **ffmpeg** (https://ffmpeg.org) and open
the PR. Nothing else. Explicitly OUT of scope: building ffmpeg from source,
custom codec/port options, the `--enable-nonfree` codecs, hardware transcode
(VA-API/QSV), and wiring ffmpeg into any other service.

## Verified facts
- **This is a pkg-based port, NOT a source build.** FreeBSD packages ffmpeg;
  the image is `base-core` + `pkg install -y ffmpeg`. If you find yourself
  cloning FFmpeg source or installing a compiler, stop and re-read this brief.
- **Version:** quarterly ships `ffmpeg 8.1.2,1` (verified `pkg rquery`
  2026-07-04 — re-verify, it's your only version fact). The quarterly snapshot
  IS the pin; there is no `ARG <APP>_VERSION` to set. Instead add a **major
  drift assert** in the Containerfile: fail the build if
  `ffmpeg -version` doesn't start `ffmpeg version 8.` (a surprise major bump
  must fail loudly, not ship silently).
- **License:** pkg reports `GPLv3+, LGPL3+` → label `GPL-3.0-or-later`.
- **Dependencies:** none for you to manage — `pkg` resolves the full shared-lib
  tree. The entire native-modules section of the cookbook is irrelevant here.
- **No config, no env vars, no ports, no volumes** beyond a work directory:
  create `/work`, `chown bsd:bsd`, `WORKDIR /work` — users bind-mount their
  media there. `ENTRYPOINT ["ffmpeg"]`, `CMD ["-version"]`.

## Crib (mandatory — do not tour the registry)
- **Copy from `~/workspace/immich-cli`** (`Containerfile.j2` +
  `.daemonless/config.yaml`): it is the CLI-class exemplar — `base-core` base,
  no s6, no compose.yaml, `cit: mode: command`, ENTRYPOINT+CMD shape,
  `pkg clean -ay` hygiene.
- Do NOT copy: everything node/npm (ffmpeg needs no runtime), the
  `chmod a+rX /usr/local/lib/node_modules` layer, and its
  `category: "Tools"` — that label predates dbuild validation and is INVALID.
  Use **`Utilities`** (must be in dbuild's `VALID_CATEGORIES`).

## Functional probe (mandatory — proves it WORKS, not just prints a version)
- CIT (`.daemonless/config.yaml`): `mode: command`,
  `expect_output: 'ffmpeg version \d'` (default CMD `-version`, exit 0).
- Smoke test (`scripts/smoke-test.sh`): a real transcode through the whole
  pipeline — run the image once with args
  `-f lavfi -i testsrc2=duration=1:size=128x128:rate=10 -f null -`
  and assert exit 0. That exercises demux→filter→encode with no input file
  and no output artifact. NOTE: the `templates/smoke-test.sh` is shaped for
  services (detached run + ready-wait + curl) — for this one-shot CLI, write a
  simpler script: `podman run --rm <image> <args>`, check the exit code.
  Keep the doas/sudo `_priv_prefix` detection from the template.

## Decisions already made
- **Base:** `ghcr.io/daemonless/base-core:15-pkg` (one-shot CLI → no s6;
  rolling lowest-minor tag per the skill's ABI rule).
- **Class:** `cli` → **no `compose.yaml` at all**; everything lives in
  `.daemonless/config.yaml` (see cookbook "Catalog metadata: set
  `x-daemonless: class:`").
- **Single stage.** No builder stage — nothing is compiled or fetched outside
  `pkg`.

## Expected traps (pre-mapped to cookbook entries)
1. Long silent pause after the pkg RUN = ZFS layer commit (ffmpeg's dep tree
   is large) — wait, don't kill (cookbook entry).
2. Don't run another build/pull in parallel (podman store lock, cookbook).
3. Build via `scripts/build.sh`, backgrounded — never foreground (skill rule 7;
   a hook enforces it).
4. A CLI image gets NO healthcheck label / healthz script — if the scaffold
   generated service artifacts (s6 run dir, compose.yaml), delete them.

## Definition of done
Per the skill: clean `scripts/build.sh` + `scripts/cit-with-logs.sh` pass
(command-mode CIT **and** the smoke transcode) + drift assert in place +
`dbuild screenshot` (ffmpeg has no UI — if no usable upstream image exists,
note that in PROCESS-LOG and skip) + `port-auditor` CLEAN + BUILD-NOTES.md +
PROCESS-LOG.md + lint-compose pass (expect it to no-op on compose.yaml — it's
CLI class) + PR (provenance + viva) + any new cookbook entries. Then STOP for
human review.
