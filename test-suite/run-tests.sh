#!/usr/bin/env bash
# NG-S4 test suite.
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# Requires: bash, shellcheck (optional), ffprobe (optional for video probe test).
# Does NOT require a running nginx, stunnel or real ffmpeg - command assembly
# tests use an in-process mock.
#
# Usage (from repo root or test-suite/):
#   bash test-suite/run-tests.sh

set -u

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SUITE_DIR/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; skipped=0
ok()   { printf '  [PASS] %s\n' "$*"; pass=$((pass+1)); }
ng()   { printf '  [FAIL] %s\n' "$*"; fail=$((fail+1)); }
skip() { printf '  [SKIP] %s\n' "$*"; skipped=$((skipped+1)); }
section() { printf '\n=== %s ===\n' "$*"; }

# --------------------------------------------------------------------------
# Mock ffmpeg: answers capability queries, otherwise records the command.
# --------------------------------------------------------------------------
MOCK_BIN="$WORK/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/ffmpeg" <<'MOCK'
#!/usr/bin/env bash
for a in "$@"; do
    if [[ "$a" == "-encoders" ]]; then
        printf ' V..... libx264 (libx264 H.264 / AVC)\n'
        printf ' V..... libx265 (libx265 H.265 / HEVC)\n'
        printf ' V..... hevc_nvenc (NVIDIA NVENC hevc)\n'
        printf ' V..... h264_nvenc (NVIDIA NVENC H264)\n'
        printf ' V..... h264_v4l2m2m (V4L2 mem2mem H.264)\n'
        exit 0
    fi
    if [[ "$a" == "-protocols" ]]; then
        printf 'Output:\n https\n rtmp\n rtmps\n'
        exit 0
    fi
done
{ printf 'CMD:'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } \
    >> "${FFCMD_LOG:-$WORK/cmds.log}"
exit 0
MOCK
chmod +x "$MOCK_BIN/ffmpeg"
export PATH="$MOCK_BIN:$PATH"

# Minimal master.env used by most engine tests.
# Keys are non-placeholder so the engine does not skip them.
CONF="$WORK/master.env"
cat > "$CONF" <<'CONF'
export TARGETS="TW YT KI"
export INGEST_APP="ingest"
export INGEST_INPUT=""
export SOURCE_FPS_HINT="60"
export AUDIO_RATE="48000"
export AUDIO_CHANNELS="2"

export TW_ENABLE="1" TW_LABEL="Twitch"
export TW_INGEST="rtmp"
export TW_URL="rtmp://lhr.contribute.live-video.net/app"
export TW_KEY="tw_testkey"
export TW_VCODEC="h264" TW_HDR="sdr"
export TW_SCALE="1920:-2" TW_FPS="30"
export TW_VBITRATE="6000k" TW_MAXRATE="6000k" TW_BUFSIZE="9000k"
export TW_ABITRATE="160k" TW_GOP_SECONDS="2"

export YT_ENABLE="1" YT_LABEL="YouTube"
export YT_INGEST="hls"
export YT_URL="https://a.upload.youtube.com/http_upload_hls"
export YT_KEY="yt_testkey"
export YT_VCODEC="hevc" YT_HDR="hdr"
export YT_SCALE="" YT_FPS=""
export YT_VBITRATE="45000k" YT_MAXRATE="51000k" YT_BUFSIZE="90000k"
export YT_ABITRATE="192k" YT_GOP_SECONDS="2"
export YT_HLS_TIME="2" YT_HLS_SEGS="5"

export KI_ENABLE="0" KI_LABEL="Kick"
export KI_INGEST="rtmp"
export KI_URL="rtmp://127.0.0.1:19352/app"
export KI_KEY="ki_testkey"
export KI_VCODEC="h264" KI_HDR="sdr"
export KI_SCALE="1920:-2" KI_FPS="60"
export KI_VBITRATE="6000k" KI_MAXRATE="6000k" KI_BUFSIZE="9000k"
export KI_ABITRATE="160k" KI_GOP_SECONDS="2"
CONF

ENGINE="$PROJ_ROOT/UNIX-Scripts/ng-s4-transcode.sh"

# Run the engine and capture commands. Args: log_file env_overrides...
run_engine() {
    local log="$1"; shift
    FFCMD_LOG="$log" NG_S4_MASTER_ENV="$CONF" \
        LOG_DIR="$WORK/logs" TRANSCODE_LOG_DIR="$WORK/logs" \
        "$@" bash "$ENGINE" live 2>/dev/null
}

# --------------------------------------------------------------------------
section "1. ShellCheck"
# --------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
    all_clean=1
    while IFS= read -r script; do
        if ! shellcheck -x "$script" >/dev/null 2>&1; then
            ng "shellcheck failed: $script"
            all_clean=0
        fi
    done < <(find "$PROJ_ROOT/UNIX-Scripts" -name '*.sh')
    [[ "$all_clean" == "1" ]] && ok "all UNIX-Scripts pass shellcheck"
else
    skip "shellcheck not on PATH"
fi

# --------------------------------------------------------------------------
section "2. nginx config token render"
# --------------------------------------------------------------------------
RENDERED="$WORK/nginx.conf"
sed -e 's|@@HTTP_PORT@@|8080|g' \
    -e 's|@@LAN_CIDR@@|192.168.1.0/24|g' \
    -e 's|@@HLS_BASE_DIR@@|/mnt/hls|g' \
    "$PROJ_ROOT/example.env/nginx.conf" > "$RENDERED"
if grep -qE '@@(HTTP_PORT|LAN_CIDR|HLS_BASE_DIR)@@' "$RENDERED"; then
    ng "nginx.conf still contains unreplaced substitution tokens after render"
else
    ok "nginx.conf substitution tokens all rendered"
fi
opens=$(grep -o '{' "$RENDERED" | wc -l)
closes=$(grep -o '}' "$RENDERED" | wc -l)
if [[ "$opens" -eq "$closes" ]]; then
    ok "nginx.conf braces balance ($opens open, $closes close)"
else
    ng "nginx.conf brace mismatch: $opens open vs $closes close"
fi

# --------------------------------------------------------------------------
section "3. Twitch: HDR source, SDR output, RTMP"
# --------------------------------------------------------------------------
LOG="$WORK/tw.log"; : > "$LOG"
run_engine "$LOG" SOURCE_HDR=hdr ENCODER_BACKEND=software
TW_CMD=$(grep 'rtmp://lhr' "$LOG" || true)
if [[ -n "$TW_CMD" ]]; then
    ok "Twitch command targets RTMP ingest"
else
    ng "Twitch RTMP command not found in output"
fi
if printf '%s' "$TW_CMD" | grep -q '\-f flv'; then
    ok "Twitch uses FLV output format"
else
    ng "Twitch output is not FLV"
fi
# HDR source with SDR target means tone-map chain must appear.
if printf '%s' "$TW_CMD" | grep -q 'zscale'; then
    ok "Twitch command includes tone-map chain (zscale)"
else
    ng "Twitch tone-map chain missing for HDR->SDR"
fi
if printf '%s' "$TW_CMD" | grep -q 'libx264'; then
    ok "Twitch uses libx264 (software, SDR)"
else
    ng "Twitch encoder is not libx264"
fi
if printf '%s' "$TW_CMD" | grep -q 'fps=30'; then
    ok "Twitch FPS downmix applied (30)"
else
    ng "Twitch FPS not set to 30"
fi
if printf '%s' "$TW_CMD" | grep -q 'scale=w=min'; then
    ok "Twitch scale is downscale-only (caps width, never upscales)"
else
    ng "Twitch scale is not capped against upscaling"
fi

# --------------------------------------------------------------------------
section "4. YouTube: HDR source, HDR output, HLS ingest (software hevc)"
# --------------------------------------------------------------------------
LOG="$WORK/yt.log"; : > "$LOG"
run_engine "$LOG" SOURCE_HDR=hdr ENCODER_BACKEND=software
YT_CMD=$(grep 'upload.youtube.com' "$LOG" || true)
if [[ -n "$YT_CMD" ]]; then
    ok "YouTube command targets YouTube ingest URL"
else
    ng "YouTube HLS command not found in output"
fi
if printf '%s' "$YT_CMD" | grep -q '\-f hls'; then
    ok "YouTube uses HLS output format"
else
    ng "YouTube output is not HLS"
fi
if printf '%s' "$YT_CMD" | grep -q '\-method PUT'; then
    ok "YouTube HLS uses HTTP PUT method"
else
    ng "YouTube HLS -method PUT missing"
fi
if printf '%s' "$YT_CMD" | grep -q 'cid=yt_testkey'; then
    ok "YouTube stream key embedded in URL as cid="
else
    ng "YouTube stream key (cid=) not found in URL"
fi
if printf '%s' "$YT_CMD" | grep -q 'copy=0.*file=live.m3u8\|file=live.m3u8'; then
    ok "YouTube HLS URL contains copy=0&file=live.m3u8"
else
    ng "YouTube HLS URL format incorrect (expected copy=0&file=live.m3u8)"
fi
if printf '%s' "$YT_CMD" | grep -q 'libx265'; then
    ok "YouTube uses libx265 (software HEVC HDR)"
else
    ng "YouTube encoder is not libx265"
fi
if printf '%s' "$YT_CMD" | grep -q 'bt2020'; then
    ok "YouTube HEVC carries BT.2020 colour metadata"
else
    ng "YouTube HDR colour metadata (bt2020) missing"
fi

# --------------------------------------------------------------------------
section "5. YouTube: HDR source, HDR output, HLS ingest (NVENC hevc)"
# --------------------------------------------------------------------------
LOG="$WORK/yt_nv.log"; : > "$LOG"
run_engine "$LOG" SOURCE_HDR=hdr ENCODER_BACKEND=nvenc
YT_NV=$(grep 'upload.youtube.com' "$LOG" || true)
if printf '%s' "$YT_NV" | grep -q 'hevc_nvenc'; then
    ok "YouTube NVENC path uses hevc_nvenc"
else
    ng "YouTube NVENC path does not use hevc_nvenc"
fi
if printf '%s' "$YT_NV" | grep -q 'hwaccel_output_format cuda'; then
    ok "YouTube NVENC full-GPU fast path active (hwaccel_output_format cuda)"
else
    ng "YouTube NVENC GPU fast path not active"
fi
if printf '%s' "$YT_NV" | grep -q '\-f hls'; then
    ok "YouTube NVENC path still uses HLS output"
else
    ng "YouTube NVENC output is not HLS"
fi

# --------------------------------------------------------------------------
section "6. YouTube: HDR output, HLS ingest via stunnel (Host header)"
# --------------------------------------------------------------------------
CONF_STUN="$WORK/stun.env"
cp "$CONF" "$CONF_STUN"
echo 'export YT_STUNNEL_PORT="19351"' >> "$CONF_STUN"
LOG="$WORK/yt_stun.log"; : > "$LOG"
FFCMD_LOG="$LOG" NG_S4_MASTER_ENV="$CONF_STUN" \
    LOG_DIR="$WORK/logs" TRANSCODE_LOG_DIR="$WORK/logs" \
    SOURCE_HDR=hdr ENCODER_BACKEND=software \
    bash "$ENGINE" live 2>/dev/null
YT_STUN=$(grep '127.0.0.1:19351' "$LOG" || true)
if [[ -n "$YT_STUN" ]]; then
    ok "YouTube stunnel path targets local port 19351"
else
    ng "YouTube stunnel command not found (expected 127.0.0.1:19351)"
fi
if printf '%s' "$YT_STUN" | grep -q 'Host:.*upload.youtube.com'; then
    ok "Host header set to a.upload.youtube.com for stunnel path"
else
    ng "Host header missing or incorrect for stunnel HLS path"
fi
if printf '%s' "$YT_STUN" | grep -q 'http://127.0.0.1:19351'; then
    ok "YouTube stunnel path uses plain HTTP to the local port (stunnel adds TLS)"
else
    ng "YouTube stunnel path should use http://127.0.0.1:19351 not https://"
fi

# --------------------------------------------------------------------------
section "7. Disabled target is skipped"
# --------------------------------------------------------------------------
LOG="$WORK/ki.log"; : > "$LOG"
run_engine "$LOG" SOURCE_HDR=sdr ENCODER_BACKEND=software
if grep -q 'rtmp://127.0.0.1:19352' "$LOG" 2>/dev/null; then
    ng "Kick (disabled) command appeared in output"
else
    ok "Kick (KI_ENABLE=0) is correctly skipped"
fi

# --------------------------------------------------------------------------
section "8. Placeholder stream key is skipped"
# --------------------------------------------------------------------------
CONF2="$WORK/placeholder.env"
sed 's/TW_KEY="tw_testkey"/TW_KEY="your_twitch_stream_key_here"/' "$CONF" > "$CONF2"
LOG="$WORK/placeholder.log"; : > "$LOG"
FFCMD_LOG="$LOG" NG_S4_MASTER_ENV="$CONF2" LOG_DIR="$WORK/logs" \
    TRANSCODE_LOG_DIR="$WORK/logs" SOURCE_HDR=sdr ENCODER_BACKEND=software \
    bash "$ENGINE" live 2>/dev/null
if grep -q 'lhr.contribute.live-video.net' "$LOG" 2>/dev/null; then
    ng "Twitch command ran despite placeholder key"
else
    ok "Placeholder key correctly skips the target"
fi

# --------------------------------------------------------------------------
section "9. Local HLS sink needs no key"
# --------------------------------------------------------------------------
CONF_LOCAL="$WORK/local.env"
cat > "$CONF_LOCAL" <<LOCALCONF
export TARGETS="LO"
export LO_ENABLE="1" LO_LABEL="LocalHLS" LO_INGEST="local"
export LO_URL="$WORK/localout" LO_KEY=""
export LO_VCODEC="h264" LO_HDR="sdr" LO_SCALE="1280:-2" LO_FPS="30"
export LO_VBITRATE="3000k" LO_MAXRATE="3000k" LO_BUFSIZE="6000k"
export LO_ABITRATE="128k" LO_GOP_SECONDS="2"
LOCALCONF
LOG="$WORK/local.log"; : > "$LOG"
FFCMD_LOG="$LOG" NG_S4_MASTER_ENV="$CONF_LOCAL" LOG_DIR="$WORK/logs" \
    TRANSCODE_LOG_DIR="$WORK/logs" SOURCE_HDR=sdr ENCODER_BACKEND=software \
    bash "$ENGINE" localtest 2>/dev/null
LO_CMD=$(grep 'localout' "$LOG" || true)
if [[ -n "$LO_CMD" ]]; then
    ok "Local sink target runs with an empty key"
else
    ng "Local sink target did not run with an empty key"
fi
if printf '%s' "$LO_CMD" | grep -q '\-f hls'; then
    ok "Local sink uses HLS output"
else
    ng "Local sink output is not HLS"
fi
if printf '%s' "$LO_CMD" | grep -q 'index.m3u8'; then
    ok "Local sink writes index.m3u8 to the given directory"
else
    ng "Local sink playlist path incorrect"
fi
if printf '%s' "$LO_CMD" | grep -q 'method PUT'; then
    ng "Local sink should not use HTTP PUT"
else
    ok "Local sink does not use HTTP PUT (plain file write)"
fi

# --------------------------------------------------------------------------
section "10. Global bitrate cap"
# --------------------------------------------------------------------------
CONF_CAP="$WORK/cap.env"
cp "$CONF" "$CONF_CAP"
echo 'export MAX_VIDEO_BITRATE="22000k"' >> "$CONF_CAP"
LOG="$WORK/cap.log"; : > "$LOG"
FFCMD_LOG="$LOG" NG_S4_MASTER_ENV="$CONF_CAP" LOG_DIR="$WORK/logs" \
    TRANSCODE_LOG_DIR="$WORK/logs" SOURCE_HDR=hdr ENCODER_BACKEND=software \
    bash "$ENGINE" live 2>/dev/null
YT_CAP=$(grep 'upload.youtube.com' "$LOG" || true)
TW_CAP=$(grep 'rtmp://lhr' "$LOG" || true)
if printf '%s' "$YT_CAP" | grep -q 'b:v 22000k'; then
    ok "YouTube bitrate capped to the global limit (22000k)"
else
    ng "YouTube bitrate not capped to 22000k"
fi
if printf '%s' "$YT_CAP" | grep -q '45000k'; then
    ng "YouTube still carries the uncapped 45000k bitrate"
else
    ok "YouTube uncapped 45000k value is gone"
fi
if printf '%s' "$TW_CAP" | grep -q 'b:v 6000k'; then
    ok "Twitch (already below the cap) is unaffected (6000k)"
else
    ng "Twitch bitrate changed unexpectedly"
fi

# --------------------------------------------------------------------------
section "11. Test video probe"
# --------------------------------------------------------------------------
VIDEO="$SUITE_DIR/testIMG+AUDIO.mkv"
if [[ ! -f "$VIDEO" ]]; then
    skip "test video not found at $VIDEO"
elif ! command -v ffprobe >/dev/null 2>&1; then
    skip "ffprobe not on PATH; install ffmpeg to run this test"
else
    probe="$(ffprobe -v error \
        -show_entries stream=codec_name,codec_type,width,height,r_frame_rate,color_transfer \
        -of compact "$VIDEO" 2>/dev/null)"
    if [[ -n "$probe" ]]; then
        ok "ffprobe read test video successfully"
        printf '  Video streams:\n'
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf '    %s\n' "$line"
        done <<< "$probe"
        if printf '%s' "$probe" | grep -q 'color_transfer=smpte2084\|color_transfer=arib-std-b67'; then
            printf '  [note] HDR colour transfer detected - engine will treat as HDR source\n'
        else
            printf '  [note] No HDR colour transfer detected - engine will treat as SDR source\n'
        fi
    else
        ng "ffprobe returned no output for $VIDEO"
    fi
fi

# --------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed, %d skipped.\n' "$pass" "$fail" "$skipped"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
