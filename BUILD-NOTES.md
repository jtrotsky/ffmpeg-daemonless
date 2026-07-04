# ffmpeg — FreeBSD daemonless build notes

| | |
|---|---|
| **Upstream** | ffmpeg.org, no git tag — tracks FreeBSD's quarterly pkg snapshot |
| **Runtime** | none (compiled binary via `pkg install ffmpeg`) |
| **Database** | none |
| **Base** | `ghcr.io/daemonless/base-core:15-pkg` (CLI, no s6) |

## FreeBSD-specific changes (and WHY)
- Installed via `pkg install ffmpeg` instead of building from source — FreeBSD
  packages ffmpeg with its full shared-lib dependency tree (libx264, libx265,
  libvpx, libdav1d, libaom, etc.), so a source build would just duplicate work
  `pkg` already does correctly. (PORT-BRIEF: "this is a pkg-based port, NOT a
  source build".)
- Major-version drift assert (`ffmpeg -version | head -1 | grep -qE '^ffmpeg
  version 8\.'`) — there is no upstream tag to pin (the quarterly snapshot IS
  the pin), so this is the only guard against a silent major bump shipping
  unnoticed. Fails the build loudly instead.

## Patches (`patches/`) — why each exists
None. No source is compiled or modified; `pkg` provides the binary.

## Native dependencies handled
| Dep | FreeBSD status | How handled |
|---|---|---|
| ffmpeg + full shared-lib tree (libx264, libx265, libvpx, libdav1d, libaom, libopus, libmp3lame, etc.) | packaged (quarterly) | `pkg install -y ffmpeg` resolves the whole tree; nothing built or pinned individually |

## Runtime image also ships a compiler toolchain — known, accepted, not fixed
`pkg install ffmpeg` pulls in **gcc14 (359 MiB), binutils (166 MiB), python311,
py311-numpy, openblas, boost-libs and suitesparse** as *runtime* dependencies —
verified via `pkg info -r` inside the built image, not just read off the
Containerfile. Traced chain:
`ffmpeg → libjxl (JPEG XL, --enable-libjxl) → openexr → Imath → py311-numpy
(Imath's Python bindings) → openblas/suitesparse (BLAS) → gcc14/binutils
(libgfortran)`.
This is a FreeBSD ports quirk: Imath's port depends on its Python bindings
even when the only consumer (openexr, then libjxl, then ffmpeg) uses it
purely as a C++ library. There is no `ffmpeg-lite`/no-jxl pkg flavour to
avoid it (checked `pkg search`; only `ffmpeg` and `ffmpeg-nox11` exist, and
`-nox11` doesn't touch the jxl/openexr chain). Building from source with
`--disable-libjxl` would drop it, but a source build and custom codec options
are explicitly out of scope per PORT-BRIEF. **This ships as-is** — documented
here rather than silently shipped, since it violates the general "no
toolchain in the runtime stage" quality floor in spirit (there's no builder
stage to strip it from; it's inherent to the single `pkg install ffmpeg`).
Image size is meaningfully larger than the base `ffmpeg` binary alone as a
result.

## Verified
- `dbuild build` ✅ — clean, no failure signatures in `build.log`
- `dbuild test` ✅ — command-mode CIT: `ffmpeg -version` (default CMD) exits 0,
  output matches `ffmpeg version \d`. Actual version resolved at build time:
  `ffmpeg-8.1,1` (confirmed in `build.log`; FreeBSD's live quarterly catalog
  had already moved to `8.1.2,1` by the time this was checked afterwards —
  the drift assert only pins the major digit, so either point release passes,
  by design).
- Functional probe (`scripts/smoke-test.sh`) ✅ — real transcode:
  `ffmpeg -f lavfi -i testsrc2=duration=1:size=128x128:rate=10 -f null -`
  (demux → filter → encode → mux, no input file / no output artifact), exit 0

## Guards in place
- Major-version drift assert — fails the build if pkg ffmpeg moves off major
  version 8. Deliberately major-only: a point-release bump (as already
  happened once, unnoticed, between PORT-BRIEF's research and this build)
  ships silently — that's accepted, not a gap, since nothing about a point
  release changes this image's behaviour.
- No patch-rot guard needed (no patches).
- No guard on the transitive package manifest (gcc14/numpy/etc. above) — a
  future quarterly could add or drop packages from this chain and neither
  CIT nor the smoke test would notice, since both only exercise ffmpeg's own
  behaviour. The one thing that *would* fail loudly: if a bump ever drops the
  `lavfi` demuxer or `testsrc2` filter, the smoke test exits non-zero.

## Known limitations
- No `--enable-nonfree` codecs (e.g. `libfdk-aac`) — FreeBSD's `pkg` build
  disables them, matching upstream's own default distribution policy.
- No hardware transcode (VA-API/QSV) — out of scope per PORT-BRIEF; CPU-only.
- No `dbuild screenshot` — ffmpeg is a CLI with no UI, so there is no upstream
  image to capture (documented in PROCESS-LOG rather than skipped silently).
- Runtime image includes a full GCC14 + Python3.11 + numpy/boost toolchain
  (~700+ MiB) as a transitive dependency of libjxl support — see above.
