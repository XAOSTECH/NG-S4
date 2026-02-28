#!/usr/bin/env bash
# Streams video from a gphoto2-compatible camera to an RTMP server using ffmpeg
set -e
DEFAULT_RTMP_URL="rtmp://127.0.0.1:1935/Cam1/live_camera"
VIDEO_BITRATE="2500k"
VIDEO_MAXRATE="3000k"
VIDEO_BUFSIZE="5000k"
VIDEO_FRAMERATE="30"
VIDEO_GOP_SIZE="60"
VIDEO_PRESET="veryfast"
VIDEO_TUNE="zerolatency"
AUDIO_CODEC="aac"
AUDIO_BITRATE="128k"
AUDIO_SAMPLERATE="44100"
AUDIO_CHANNELS="2"
RTMP_URL="${1:-$DEFAULT_RTMP_URL}"
command -v gphoto2 >/dev/null 2>&1 || { echo >&2 "gphoto2 not found. Please install it. Aborting."; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo >&2 "ffmpeg not found. Please install it. Aborting."; exit 1; }
echo "Attempting to stream from gphoto2 compatible camera..."
echo "Source: Autodetected gphoto2 camera"
echo "Destination RTMP URL: $RTMP_URL"
echo "Video Bitrate: $VIDEO_BITRATE, Maxrate: $VIDEO_MAXRATE, Framerate: $VIDEO_FRAMERATE"
echo "Press Ctrl+C to stop streaming."
trap "echo 'Stopping stream...'; kill 0; exit 0;" SIGINT SIGTERM
sudo gphoto2 --capture-movie --stdout | ffmpeg \
    -re \
    -f mjpeg -i - \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=${AUDIO_SAMPLERATE} \
    -map 0:v:0 -map 1:a:0 \
    -vcodec libx264 \
    -pix_fmt yuv420p \
    -preset "${VIDEO_PRESET}" \
    -tune "${VIDEO_TUNE}" \
    -b:v "${VIDEO_BITRATE}" \
    -maxrate "${VIDEO_MAXRATE}" \
    -bufsize "${VIDEO_BUFSIZE}" \
    -r "${VIDEO_FRAMERATE}" \
    -g "${VIDEO_GOP_SIZE}" \
    -c:a "${AUDIO_CODEC}" \
    -b:a "${AUDIO_BITRATE}" \
    -ar "${AUDIO_SAMPLERATE}" \
    -ac "${AUDIO_CHANNELS}" \
    -shortest \
    -f flv \
    -flvflags no_duration_filesize \
    -rtmp_live live \
    -loglevel warning \
    "${RTMP_URL}"
echo "Stream ended."
