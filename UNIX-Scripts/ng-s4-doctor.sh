#!/usr/bin/env bash
# NG-S4 doctor: report encode capabilities and configuration health.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
#
# Read only. Run on each host (NVIDIA box and Raspberry Pi) to confirm the encoders, filters and configuration needed for HDR/SDR restreaming.
set -u

ok=0; warnc=0; badc=0
pass() { printf '  [ ok ] %s\n' "$*"; ok=$((ok + 1)); }
note() { printf '  [warn] %s\n' "$*"; warnc=$((warnc + 1)); }
fail() { printf '  [fail] %s\n' "$*"; badc=$((badc + 1)); }

echo "NG-S4 doctor"
echo "Host: $(uname -srm)"
[[ -r /proc/device-tree/model ]] && echo "Model: $(tr -d '\0' </proc/device-tree/model)"
echo

# --- Load configuration ------------------------------------------------------
if [[ -r /etc/default/ng-s4 ]]; then
    # shellcheck source=/dev/null
    . /etc/default/ng-s4
fi
if [[ -z "${NG_S4_MASTER_ENV:-}" ]]; then
    _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    for _cand in "$_self_dir/../real.env/master.env" "$_self_dir/../example.env/master.env"; do
        [[ -r "$_cand" ]] && { NG_S4_MASTER_ENV="$_cand"; break; }
    done
fi
if [[ -n "${NG_S4_MASTER_ENV:-}" && -r "${NG_S4_MASTER_ENV:-}" ]]; then
    # shellcheck source=/dev/null
    . "$NG_S4_MASTER_ENV" && pass "configuration loaded: $NG_S4_MASTER_ENV"
else
    note "master.env not found; skipping target checks"
fi

echo
echo "Tools:"
if command -v ffmpeg >/dev/null 2>&1; then
    pass "ffmpeg present ($(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $3}'))"
else
    fail "ffmpeg not found (sudo apt install ffmpeg)"
fi
if command -v ffprobe >/dev/null 2>&1; then
    pass "ffprobe present"
else
    note "ffprobe not found; automatic HDR detection is disabled"
fi

enc_has() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"; }
filt_has() { ffmpeg -hide_banner -filters 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"; }
check_enc() { if enc_has "$1"; then pass "$2"; else "$3" "$4"; fi; }

echo
echo "Encode backend:"
backend="software"
if enc_has hevc_nvenc && { [[ -e /dev/nvidia0 ]] || command -v nvidia-smi >/dev/null 2>&1; }; then
    backend="nvenc"
elif enc_has h264_v4l2m2m && { [[ -e /dev/video11 ]] || grep -qi raspberry /proc/device-tree/model 2>/dev/null; }; then
    backend="v4l2m2m"
fi
case "${ENCODER_BACKEND:-auto}" in
    nvenc|v4l2m2m|software) backend="$ENCODER_BACKEND"; note "backend forced to '$backend' via ENCODER_BACKEND";;
    *) pass "auto-selected backend: $backend";;
esac

echo
echo "Encoders:"
check_enc libx264 "libx264 (software H.264)" note "libx264 missing"
check_enc libx265 "libx265 (software H.265/HDR)" note "libx265 missing (needed for software HDR)"
if [[ "$backend" == "nvenc" ]]; then
    check_enc h264_nvenc "h264_nvenc" fail "h264_nvenc missing"
    check_enc hevc_nvenc "hevc_nvenc (HDR HEVC)" fail "hevc_nvenc missing"
    if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi -L 2>/dev/null | sed 's/^/    /'; fi
fi
if [[ "$backend" == "v4l2m2m" ]]; then
    check_enc h264_v4l2m2m "h264_v4l2m2m" fail "h264_v4l2m2m missing"
    if [[ -e /dev/video11 ]]; then pass "/dev/video11 encoder node present"; else note "/dev/video11 not found"; fi
fi

echo
echo "HDR tone mapping (HDR source -> SDR targets):"
if filt_has zscale; then
    pass "zscale filter available"
else
    note "zscale missing; HDR to SDR tone mapping unavailable (ffmpeg needs libzimg)"
fi
if filt_has tonemap; then pass "tonemap filter available"; else note "tonemap filter missing"; fi

echo
echo "Server components:"
if command -v nginx >/dev/null 2>&1; then
    pass "nginx present ($(nginx -v 2>&1 | awk -F/ '{print $2}'))"
    if nginx -V 2>&1 | grep -qi rtmp || dpkg -s libnginx-mod-rtmp >/dev/null 2>&1 \
       || compgen -G '/etc/nginx/modules-enabled/*rtmp*' >/dev/null 2>&1; then
        pass "nginx RTMP module installed"
    else
        note "nginx RTMP module not detected (sudo apt install libnginx-mod-rtmp)"
    fi
else
    note "nginx not installed yet (run setup-restream.sh)"
fi
if command -v stunnel4 >/dev/null 2>&1 || command -v stunnel >/dev/null 2>&1; then
    pass "stunnel present"
else
    note "stunnel4 not installed yet (needed for RTMPS targets)"
fi

echo
echo "Targets:"
if [[ -n "${TARGETS:-}" ]]; then
    for id in $TARGETS; do
        en="${id}_ENABLE"; ky="${id}_KEY"; lb="${id}_LABEL"
        [[ "${!en:-0}" == "1" ]] || { printf '  [ -- ] %s disabled\n' "${!lb:-$id}"; continue; }
        case "${!ky:-}" in
            ""|your_*_stream_key_here) fail "${!lb:-$id} enabled but stream key is not set";;
            *) pass "${!lb:-$id} enabled and configured";;
        esac
    done
else
    note "TARGETS not defined"
fi

echo
echo "Summary: $ok ok, $warnc warning(s), $badc failure(s)."
[[ "$badc" -eq 0 ]] || exit 1
exit 0
