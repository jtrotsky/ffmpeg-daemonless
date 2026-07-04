#!/bin/sh
# Functional probe — proves ffmpeg actually transcodes, not just that it prints
# a version string. Runs demux(lavfi testsrc)->filter->encode->mux(null) with
# no input file and no output artifact, asserting exit 0.

set -u

IMAGE_NAME=$(basename "$(pwd)")
IMAGE="ghcr.io/daemonless/${IMAGE_NAME}:build-latest"

PODMAN="podman"
if [ "$(id -u)" -ne 0 ]; then
  if command -v doas >/dev/null 2>&1; then PODMAN="doas podman";
  elif command -v sudo >/dev/null 2>&1; then PODMAN="sudo podman"; fi
fi

echo "[smoke] running a real transcode (lavfi testsrc -> null) in $IMAGE"
if $PODMAN run --rm "$IMAGE" \
    -f lavfi -i testsrc2=duration=1:size=128x128:rate=10 -f null -; then
  echo "[smoke] PASS: ffmpeg demuxed/filtered/encoded a synthetic stream end-to-end"
  exit 0
else
  echo "[smoke] FAIL: transcode did not exit 0" >&2
  exit 1
fi
