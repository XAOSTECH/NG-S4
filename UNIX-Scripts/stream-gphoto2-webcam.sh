#!/usr/bin/env bash
# Stream a gphoto2 compatible camera into the NG-S4 ingest for restreaming.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# The camera feed lands on the ingest application, so the transcode engine then fans it out to every enabled platform. Run with sudo if your camera needs it.
set -euo pipefail

RTMP_URL="${1:-rtmp://127.0.0.1:1935/ingest/camera}"

VIDEO_BITRATE="${VIDEO_BITRATE:-6000k}"
VIDEO_MAXRATE="${VIDEO_MAXRATE:-6000k}"
VIDEO_BUFSIZE="${VIDEO_BUFSIZE:-9000k}"
VIDEO_FRAMERATE="${VIDEO_FRAMERATE:-30}"
VIDEO_GOP="${VIDEO_GOP:-60}"
AUDIO_BITRATE="${AUDIO_BITRATE:-160k}"
AUDIO_SAMPLERATE="${AUDIO_SAMPLERATE:-48000}"

command -v gphoto2 >/dev/null 2>&1 || { echo "gphoto2 not found. Aborting." >&2; exit 1; }
command -v ffmpeg  >/dev/null 2>&1 || { echo "ffmpeg not found. Aborting." >&2; exit 1; }

# Pick the best available H.264 encoder for the host.
enc_has() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"; }
VENC=(-c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p)
if enc_has h264_nvenc && { [[ -e /dev/nvidia0 ]] || command -v nvidia-smi >/dev/null 2>&1; }; then
    VENC=(-c:v h264_nvenc -preset p4 -tune ll -rc cbr -pix_fmt yuv420p)
    echo "Using NVENC hardware encoder."
elif enc_has h264_v4l2m2m && { [[ -e /dev/video11 ]] || grep -qi raspberry /proc/device-tree/model 2>/dev/null; }; then
    VENC=(-c:v h264_v4l2m2m -pix_fmt yuv420p)
    echo "Using V4L2 M2M hardware encoder."
else
    echo "Using software x264 encoder."
fi

echo "Streaming gphoto2 camera to: $RTMP_URL"
echo "Press Ctrl+C to stop."
trap 'echo; echo "Stopping..."; kill 0 2>/dev/null; exit 0' INT TERM

gphoto2 --capture-movie --stdout \
  | ffmpeg -hide_banner -loglevel warning -re \
      -f mjpeg -i - \
      -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=${AUDIO_SAMPLERATE}" \
      -map 0:v:0 -map 1:a:0 \
      "${VENC[@]}" \
      -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_MAXRATE" -bufsize "$VIDEO_BUFSIZE" \
      -r "$VIDEO_FRAMERATE" -g "$VIDEO_GOP" \
      -c:a aac -b:a "$AUDIO_BITRATE" -ar "$AUDIO_SAMPLERATE" -ac 2 \
      -shortest -f flv "$RTMP_URL"

echo "Stream ended."
