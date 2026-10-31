#!/usr/bin/env bash
# NG-S4 host encode test: runs the real transcode engine against the bundled
# test video and writes HLS to a local directory. No platform keys, no network.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# This proves the encoders, filters and tone mapping actually work on this host
# (NVENC, V4L2 M2M or software) without touching any streaming platform.
#
# Usage (on the host, with ffmpeg installed):
#   bash test-suite/run-local-encode.sh [input-file]
# Optional overrides: ENCODER_BACKEND=nvenc SOURCE_HDR=hdr DURATION=20 OUT=/path
set -u

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SUITE_DIR/.." && pwd)"
VIDEO="${1:-$SUITE_DIR/testIMG+AUDIO.mkv}"
OUT="${OUT:-/tmp/ng-s4-test/hls}"
DURATION="${DURATION:-15}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found; run this on the host."; exit 1; }
[[ -f "$VIDEO" ]] || { echo "test video not found: $VIDEO"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
echo "Transcoding '$VIDEO' -> '$OUT' for ${DURATION}s (backend: ${ENCODER_BACKEND:-auto}, source: ${SOURCE_HDR:-auto})..."
echo

# NG_S4_MASTER_ENV is set explicitly so the engine ignores any installed
# /etc/default/ng-s4 and uses the local test profile instead.
LO_URL="$OUT" INGEST_INPUT="$VIDEO" \
    NG_S4_MASTER_ENV="$SUITE_DIR/testmaster.env" \
    ENCODER_BACKEND="${ENCODER_BACKEND:-auto}" SOURCE_HDR="${SOURCE_HDR:-auto}" \
    timeout "${DURATION}" bash "$PROJ_ROOT/UNIX-Scripts/ng-s4-transcode.sh" localtest \
    || true

echo
if ls "$OUT"/*.m3u8 >/dev/null 2>&1; then
    echo "PASS: HLS output written to $OUT"
    ls -la "$OUT" | sed 's/^/  /'
    if command -v ffprobe >/dev/null 2>&1; then
        seg="$(find "$OUT" -name '*.ts' | head -n1)"
        if [[ -n "$seg" ]]; then
            echo "First segment properties:"
            ffprobe -v error \
                -show_entries stream=codec_name,codec_type,width,height,color_transfer \
                -of compact "$seg" | sed 's/^/  /'
        fi
    fi
    echo "Play it:  ffplay $OUT/index.m3u8"
    exit 0
else
    echo "FAIL: no HLS output produced."
    echo "Check the engine log (printed above, or under /var/log/ng-s4 or /tmp)."
    exit 1
fi
