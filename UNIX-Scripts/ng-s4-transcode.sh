#!/usr/bin/env bash
# NG-S4 transcode engine: fan-out re-encode for multi-platform restreaming.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# Reads the target profiles from master.env, auto-detects the best encoder
# backend (NVENC on NVIDIA hosts, V4L2 M2M on Raspberry Pi, software otherwise)
# and launches one ffmpeg pipeline per enabled platform. HDR sources are passed
# through for HDR targets and tone mapped to SDR for SDR only platforms.
#
# Usage:
#   ng-s4-transcode.sh [STREAM_NAME] [INPUT_URL]
# When called from nginx via `exec`, STREAM_NAME is the published stream name.

set -u

# nginx `exec` may run with a minimal PATH, so guarantee the usual locations.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"

log() { printf '%s [ng-s4] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

# Read <VAR> with a fallback, using indirect expansion so profiles stay flat.
get() { local _n="$1"; printf '%s' "${!_n:-$2}"; }

# --- Locate and load configuration ------------------------------------------
# /etc/default/ng-s4 (written by setup-restream.sh) points at the live master.env.
if [[ -r /etc/default/ng-s4 ]]; then
    # shellcheck source=/dev/null
    . /etc/default/ng-s4
fi
if [[ -z "${NG_S4_MASTER_ENV:-}" ]]; then
    _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for _cand in "$_self_dir/../real.env/master.env" "$_self_dir/../example.env/master.env"; do
        if [[ -r "$_cand" ]]; then NG_S4_MASTER_ENV="$_cand"; break; fi
    done
fi
[[ -n "${NG_S4_MASTER_ENV:-}" && -r "${NG_S4_MASTER_ENV:-}" ]] \
    || die "master.env not found (set NG_S4_MASTER_ENV in /etc/default/ng-s4)"
# shellcheck source=/dev/null
. "$NG_S4_MASTER_ENV" || die "failed to source $NG_S4_MASTER_ENV"

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found on PATH"

# --- Inputs -----------------------------------------------------------------
STREAM_NAME="${1:-${INGEST_STREAM_NAME:-live}}"
if [[ -n "${2:-}" ]]; then
    INPUT_URL="$2"
elif [[ -n "${INGEST_INPUT:-}" ]]; then
    INPUT_URL="$INGEST_INPUT"
else
    INPUT_URL="rtmp://127.0.0.1:1935/${INGEST_APP:-ingest}/${STREAM_NAME}"
fi

LOG_ROOT="$(get TRANSCODE_LOG_DIR "${LOG_DIR:-/var/log/ng-s4}")"
mkdir -p "$LOG_ROOT" 2>/dev/null || LOG_ROOT="/tmp"
# When launched by nginx there is no terminal, so keep a combined engine log.
if [[ ! -t 1 ]]; then
    exec >>"$LOG_ROOT/transcode-${STREAM_NAME}.log" 2>&1
fi

# --- Encoder backend detection ----------------------------------------------
have_encoder() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"; }

detect_backend() {
    case "${ENCODER_BACKEND:-auto}" in
        nvenc|v4l2m2m|software) printf '%s' "$ENCODER_BACKEND"; return;;
    esac
    if have_encoder hevc_nvenc && { [[ -e /dev/nvidia0 ]] || command -v nvidia-smi >/dev/null 2>&1; }; then
        printf 'nvenc'; return
    fi
    if have_encoder h264_v4l2m2m && { [[ -e /dev/video11 ]] || grep -qi raspberry /proc/device-tree/model 2>/dev/null; }; then
        printf 'v4l2m2m'; return
    fi
    printf 'software'
}
BACKEND="$(detect_backend)"
log "encoder backend: $BACKEND"

# --- Source HDR detection ---------------------------------------------------
source_is_hdr() {
    case "${SOURCE_HDR:-auto}" in
        hdr) return 0;;
        sdr) return 1;;
    esac
    local trc
    trc="$(timeout 6 ffprobe -v error -select_streams v:0 \
        -show_entries stream=color_transfer -of default=nk=1:nw=1 \
        "$INPUT_URL" 2>/dev/null | head -n1)"
    case "$trc" in
        smpte2084|arib-std-b67) return 0;;
        *) [[ "${SOURCE_HDR_DEFAULT:-sdr}" == "hdr" ]] && return 0 || return 1;;
    esac
}
if source_is_hdr; then SRC_HDR=1; log "source treated as HDR"; else SRC_HDR=0; log "source treated as SDR"; fi

# --- Per target ffmpeg command construction ---------------------------------
# Builds the global CMD array for one target id (e.g. TW, YT, KI).
build_target_cmd() {
    local id="$1"
    local label url key vcodec hdr scale fps vbr maxr buf abr gop
    label="$(get "${id}_LABEL" "$id")"
    url="$(get "${id}_URL" '')"
    key="$(get "${id}_KEY" '')"
    vcodec="$(get "${id}_VCODEC" h264)"
    hdr="$(get "${id}_HDR" sdr)"
    scale="$(get "${id}_SCALE" '')"
    fps="$(get "${id}_FPS" '')"
    vbr="$(get "${id}_VBITRATE" 6000k)"
    maxr="$(get "${id}_MAXRATE" "$vbr")"
    buf="$(get "${id}_BUFSIZE" "$maxr")"
    abr="$(get "${id}_ABITRATE" 160k)"
    gop="$(get "${id}_GOP_SECONDS" 2)"

    [[ -n "$url" ]] || { log "$label: no URL set, skipping"; return 1; }
    [[ -n "$key" ]] || { log "$label: no stream key set, skipping"; return 1; }
    case "$key" in your_*_stream_key_here) log "$label: placeholder key, skipping"; return 1;; esac

    local tonemap=0
    [[ "$SRC_HDR" == "1" && "$hdr" == "sdr" ]] && tonemap=1

    # Choose the effective encoder, falling back where hardware cannot cope.
    local need10=0
    [[ "$hdr" == "hdr" && "$tonemap" == "0" && "$vcodec" == "hevc" ]] && need10=1
    if [[ "$hdr" == "hdr" && "$vcodec" == "h264" ]]; then
        log "$label: H.264 cannot carry HDR, sending as 8 bit SDR-range"
    fi
    local backend="$BACKEND"
    if [[ "$backend" == "v4l2m2m" && "$need10" == "1" ]]; then
        log "$label: V4L2 M2M lacks 10 bit HDR, using software x265 for this target"
        backend="software"
    fi

    # Full GPU fast path: HDR HEVC passthrough re-encode with no scaling.
    local gpu_full=0
    [[ "$backend" == "nvenc" && "$vcodec" == "hevc" && "$need10" == "1" \
        && -z "$scale" && -z "$fps" ]] && gpu_full=1

    # Input options (decode).
    local -a in_args=(-hide_banner -nostdin -loglevel "$(get FFMPEG_LOGLEVEL warning)")
    if [[ "$backend" == "nvenc" && "$(get HWDECODE 1)" == "1" ]]; then
        in_args+=(-hwaccel cuda)
        [[ "$gpu_full" == "1" ]] && in_args+=(-hwaccel_output_format cuda)
    fi
    in_args+=(-i "$INPUT_URL")

    # Video filters.
    local -a filt=()
    if [[ "$vcodec" != "copy" ]]; then
        [[ -n "$scale" ]] && filt+=("scale=${scale}:flags=lanczos")
        [[ -n "$fps" ]] && filt+=("fps=${fps}")
        if [[ "$tonemap" == "1" ]]; then
            filt+=("zscale=t=linear:npl=100" "format=gbrpf32le" "zscale=p=bt709" \
                   "tonemap=tonemap=hable:desat=0" "zscale=t=bt709:m=bt709:r=tv" "format=yuv420p")
        fi
    fi

    # Keyframe interval in frames.
    local fpsval="${fps:-$(get SOURCE_FPS_HINT 60)}"
    local gopf=$(( fpsval * gop ))

    # Video encoder selection and options.
    local -a venc=()
    if [[ "$vcodec" == "copy" ]]; then
        venc=(-c:v copy)
    else
        local enc
        case "$backend:$vcodec" in
            nvenc:h264)    enc=h264_nvenc;;
            nvenc:hevc)    enc=hevc_nvenc;;
            v4l2m2m:h264)  enc=h264_v4l2m2m;;
            v4l2m2m:hevc)  enc=hevc_v4l2m2m;;
            software:hevc) enc=libx265;;
            *)             enc=libx264;;
        esac
        venc=(-c:v "$enc")
        case "$enc" in
            *nvenc)
                venc+=(-preset "$(get NVENC_PRESET p5)" -tune ll -rc cbr \
                       -b:v "$vbr" -maxrate "$maxr" -bufsize "$buf" \
                       -g "$gopf" -forced-idr 1 -no-scenecut 1)
                if [[ "$need10" == "1" ]]; then
                    venc+=(-profile:v main10 -color_primaries bt2020 \
                           -color_trc smpte2084 -colorspace bt2020nc)
                    [[ "$gpu_full" == "0" ]] && filt+=("format=p010le")
                fi
                ;;
            libx264)
                venc+=(-preset "$(get X264_PRESET veryfast)" -profile:v high \
                       -b:v "$vbr" -maxrate "$maxr" -bufsize "$buf" \
                       -g "$gopf" -keyint_min "$fpsval" -sc_threshold 0)
                [[ "$tonemap" == "0" ]] && filt+=("format=yuv420p")
                ;;
            libx265)
                venc+=(-preset "$(get X265_PRESET fast)" \
                       -b:v "$vbr" -maxrate "$maxr" -bufsize "$buf")
                if [[ "$need10" == "1" ]]; then
                    filt+=("format=yuv420p10le")
                    venc+=(-x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1:keyint=${gopf}:min-keyint=${fpsval}:repeat-headers=1")
                else
                    [[ "$tonemap" == "0" ]] && filt+=("format=yuv420p")
                    venc+=(-x265-params "keyint=${gopf}:min-keyint=${fpsval}")
                fi
                ;;
            *v4l2m2m)
                venc+=(-b:v "$vbr" -g "$gopf")
                [[ "$tonemap" == "0" ]] && filt+=("format=yuv420p")
                ;;
        esac
    fi

    # Audio encoder.
    local -a aenc=()
    if [[ "$vcodec" == "copy" ]]; then
        aenc=(-c:a copy)
    else
        aenc=(-c:a aac -b:a "$abr" -ar "$(get AUDIO_RATE 48000)" -ac "$(get AUDIO_CHANNELS 2)")
    fi

    # Join filters with commas.
    local vf=""
    if [[ "${#filt[@]}" -gt 0 ]]; then
        local IFS=,; vf="${filt[*]}"; unset IFS
    fi

    local out="${url%/}/${key}"

    CMD=(ffmpeg "${in_args[@]}")
    [[ -n "$vf" ]] && CMD+=(-vf "$vf")
    CMD+=(-map 0:v:0 -map "0:a:0?" "${venc[@]}" "${aenc[@]}" -f flv "$out")

    CMD_LABEL="$label"
    CMD_ID="$id"
    return 0
}

# --- Launch and supervise ----------------------------------------------------
declare -a PIDS=()

cleanup() {
    trap - TERM INT EXIT
    [[ "${#PIDS[@]}" -gt 0 ]] && kill "${PIDS[@]}" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup TERM INT EXIT

log "input: $INPUT_URL"
started=0
for id in ${TARGETS:-}; do
    [[ "$(get "${id}_ENABLE" 0)" == "1" ]] || { log "$id disabled, skipping"; continue; }
    CMD=(); CMD_LABEL=""; CMD_ID=""
    if build_target_cmd "$id"; then
        tlog="$LOG_ROOT/transcode-${STREAM_NAME}-${CMD_ID}.log"
        log "$CMD_LABEL: starting (log: $tlog)"
        "${CMD[@]}" >>"$tlog" 2>&1 &
        PIDS+=("$!")
        started=$((started + 1))
    fi
done

[[ "$started" -gt 0 ]] || die "no targets started (check *_ENABLE, URLs and keys in master.env)"
log "$started target(s) running for stream '$STREAM_NAME'"
wait
