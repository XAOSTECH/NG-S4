#!/usr/bin/env bash
# NG-S4 transcode engine: fan-out re-encode for multi-platform restreaming.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# Reads the target profiles from master.env, auto-detects the best encoder backend (NVENC on NVIDIA hosts, V4L2 M2M on Raspberry Pi, software otherwise) and launches one ffmpeg pipeline per enabled platform. HDR sources are passed through for HDR targets and tone mapped to SDR for SDR only platforms.
#
# Usage:
#   ng-s4-transcode.sh [STREAM_NAME] [INPUT_URL]
# When called from nginx via `exec`, STREAM_NAME is the published stream name.

set -u

# nginx `exec` may run with a minimal PATH. Ensure the usual locations are
# present, but APPEND them so a caller-provided PATH (e.g. a test mock) keeps
# precedence over the system binaries.
for _d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    case ":${PATH:-}:" in
        *":$_d:"*) ;;
        *) PATH="${PATH:+$PATH:}$_d";;
    esac
done
export PATH
unset _d

log() { printf '%s [ng-s4] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

# Read <VAR> with a fallback, using indirect expansion so profiles stay flat.
get() { local _n="$1"; printf '%s' "${!_n:-$2}"; }

# Cap a "<n>k" bitrate at a "<n>k" limit, returning the smaller. Empty or
# non-numeric inputs are returned unchanged.
cap_rate() {
    local v="$1" lim="$2" vn ln
    vn="${v%k}"; ln="${lim%k}"
    [[ "$vn" =~ ^[0-9]+$ && "$ln" =~ ^[0-9]+$ ]] || { printf '%s' "$v"; return; }
    if (( vn > ln )); then printf '%sk' "$ln"; else printf '%s' "$v"; fi
}

# --- Locate and load configuration ------------------------------------------
# /etc/default/ng-s4 (written by setup-restream.sh) points at the live master.env.
# An explicit NG_S4_MASTER_ENV in the environment wins, so tests can override it.
if [[ -z "${NG_S4_MASTER_ENV:-}" && -r /etc/default/ng-s4 ]]; then
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
# Fall back to a writable temp dir when the log dir is missing or not writable
# (e.g. running the engine by hand as a non-root, non-www-data user).
if ! mkdir -p "$LOG_ROOT" 2>/dev/null || [[ ! -w "$LOG_ROOT" ]]; then
    LOG_ROOT="${TMPDIR:-/tmp}/ng-s4-$UID"
    { mkdir -p "$LOG_ROOT" 2>/dev/null && [[ -w "$LOG_ROOT" ]]; } || LOG_ROOT="${TMPDIR:-/tmp}"
fi
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

# --- Probe the source once (colour transfer, frame rate, geometry) ----------
# Used to pick HDR vs SDR, keep the native resolution/frame rate, and size the
# keyframe interval to the real frame rate. The engine never upscales.
SRC_TRC=""; SRC_FPS=""; SRC_W=""; SRC_H=""
if command -v ffprobe >/dev/null 2>&1; then
    _probe="$(timeout 6 ffprobe -v error -select_streams v:0 \
        -show_entries stream=color_transfer,r_frame_rate,width,height \
        -of default=nw=1 "$INPUT_URL" 2>/dev/null)"
    SRC_TRC="$(sed -n 's/^color_transfer=//p' <<<"$_probe" | head -n1)"
    SRC_W="$(sed -n 's/^width=//p' <<<"$_probe" | head -n1)"
    SRC_H="$(sed -n 's/^height=//p' <<<"$_probe" | head -n1)"
    _rfr="$(sed -n 's/^r_frame_rate=//p' <<<"$_probe" | head -n1)"
    case "$_rfr" in
        */*) SRC_FPS="$(awk -F/ '{ if ($2 > 0) { f = $1 / $2; if (f >= 1) printf "%.0f", f } }' <<<"$_rfr")";;
        [1-9]*) SRC_FPS="$_rfr";;
    esac
    unset _probe _rfr
fi

case "${SOURCE_HDR:-auto}" in
    hdr) SRC_HDR=1;;
    sdr) SRC_HDR=0;;
    *) case "$SRC_TRC" in
           smpte2084|arib-std-b67) SRC_HDR=1;;
           *) if [[ "${SOURCE_HDR_DEFAULT:-sdr}" == "hdr" ]]; then SRC_HDR=1; else SRC_HDR=0; fi;;
       esac;;
esac
if [[ "$SRC_HDR" == "1" ]]; then log "source treated as HDR"; else log "source treated as SDR"; fi
if [[ -n "$SRC_W$SRC_H$SRC_FPS" ]]; then log "source: ${SRC_W:-?}x${SRC_H:-?} @ ${SRC_FPS:-?}fps"; fi

# --- Per target ffmpeg command construction ---------------------------------
# Builds the global CMD array for one target id (e.g. TW, YT, KI).
build_target_cmd() {
    local id="$1"
    local label ingest url key vcodec hdr scale fps vbr maxr buf abr gop
    label="$(get "${id}_LABEL" "$id")"
    ingest="$(get "${id}_INGEST" rtmp)"
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

    # Apply the global upstream bitrate ceiling (empty disables it).
    local bwlim; bwlim="$(get MAX_VIDEO_BITRATE '')"
    if [[ -n "$bwlim" ]]; then
        vbr="$(cap_rate "$vbr" "$bwlim")"
        maxr="$(cap_rate "$maxr" "$bwlim")"
        buf="$(cap_rate "$buf" "$bwlim")"
    fi

    [[ -n "$url" ]] || { log "$label: no URL set, skipping"; return 1; }
    # The local sink is for keyless testing, so it needs no stream key.
    if [[ "$ingest" != "local" ]]; then
        [[ -n "$key" ]] || { log "$label: no stream key set, skipping"; return 1; }
        case "$key" in your_*_stream_key_here) log "$label: placeholder key, skipping"; return 1;; esac
    fi

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

    # Effective output frame rate: honour a target cap, but never upsample a
    # slower source (duplicating frames just wastes bitrate).
    local fpsval apply_fps=0
    if [[ -n "$fps" ]]; then
        if [[ -z "$SRC_FPS" || "$SRC_FPS" -gt "$fps" ]]; then
            apply_fps=1; fpsval="$fps"
        else
            fpsval="$SRC_FPS"
        fi
    else
        fpsval="${SRC_FPS:-$(get SOURCE_FPS_HINT 60)}"
    fi

    # Video filters.
    local -a filt=()
    if [[ "$vcodec" != "copy" ]]; then
        if [[ -n "$scale" ]]; then
            local _sw="${scale%%:*}" _sh="${scale#*:}"
            if [[ "$_sw" =~ ^[0-9]+$ && ( "$_sh" == "-2" || "$_sh" == "-1" ) ]]; then
                # Cap width at the source width so a smaller source is not upscaled.
                filt+=("scale=w=min(iw\\,${_sw}):h=${_sh}:flags=lanczos")
            else
                filt+=("scale=${scale}:flags=lanczos")
            fi
        fi
        [[ "$apply_fps" == "1" ]] && filt+=("fps=${fps}")
        if [[ "$tonemap" == "1" ]]; then
            filt+=("zscale=t=linear:npl=100" "format=gbrpf32le" "zscale=p=bt709" \
                   "tonemap=tonemap=hable:desat=0" "zscale=t=bt709:m=bt709:r=tv" "format=yuv420p")
        fi
    fi

    # Keyframe interval in frames (from the effective output frame rate).
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

    # Output: local HLS sink (keyless testing), HLS PUT over HTTPS/stunnel
    # (YouTube HDR), or FLV over RTMP (Twitch, Kick). For HLS an optional
    # *_STUNNEL_PORT routes the PUT through a local stunnel proxy; the Host
    # header is then set so the remote accepts a request from 127.0.0.1.
    local out
    local -a out_args=()
    if [[ "$ingest" == "local" ]]; then
        mkdir -p "$url" 2>/dev/null || true
        out="${url%/}/index.m3u8"
        out_args=(-f hls -hls_time "$(get "${id}_HLS_TIME" 2)"
                  -hls_list_size "$(get "${id}_HLS_SEGS" 6)"
                  -hls_flags delete_segments+temp_file -hls_segment_type mpegts "$out")
    elif [[ "$ingest" == "hls" ]]; then
        local hlstime hlssegs stunport
        hlstime="$(get "${id}_HLS_TIME" 2)"
        hlssegs="$(get "${id}_HLS_SEGS" 5)"
        stunport="$(get "${id}_STUNNEL_PORT" '')"
        if [[ -n "$stunport" ]]; then
            local host path
            host="${url#https://}"; host="${host%%/*}"
            path="${url#https://*/}"
            out="http://127.0.0.1:${stunport}/${path}?cid=${key}&copy=0&file=live.m3u8"
            out_args=(-headers "Host: ${host}\r\n"
                      -f hls -hls_time "$hlstime" -hls_list_size "$hlssegs"
                      -hls_flags delete_segments+append_list
                      -hls_segment_type mpegts
                      -method PUT -http_persistent 1 "$out")
        else
            out="${url}?cid=${key}&copy=0&file=live.m3u8"
            out_args=(-f hls -hls_time "$hlstime" -hls_list_size "$hlssegs"
                      -hls_flags delete_segments+append_list
                      -hls_segment_type mpegts
                      -method PUT -http_persistent 1 "$out")
        fi
    else
        out="${url%/}/${key}"
        out_args=(-f flv "$out")
    fi

    CMD=(ffmpeg "${in_args[@]}")
    [[ -n "$vf" ]] && CMD+=(-vf "$vf")
    CMD+=(-map 0:v:0 -map "0:a:0?" "${venc[@]}" "${aenc[@]}" "${out_args[@]}")

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
