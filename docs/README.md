# NG-S4

<!-- Project Shields/Badges -->
<p align="center">
  <a href="https://github.com/XAOSTECH/NG-S4">
    <img alt="GitHub repo" src="https://img.shields.io/badge/GitHub-XAOSTECH%2F-NG-S4-181717?style=for-the-badge&logo=github">
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/releases">
    <img alt="GitHub release" src="https://img.shields.io/github/v/release/XAOSTECH/NG-S4?style=for-the-badge&logo=semantic-release&colour=blue">
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/XAOSTECH/NG-S4?style=for-the-badge&colour=green">
  </a>
</p>

<p align="center">
  <a href="https://github.com/XAOSTECH/NG-S4/actions">
    <img alt="CI Status" src="https://github.com/XAOSTECH/NG-S4/actions/workflows/bash-lint.yml/badge.svg?branch=Main>
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/XAOSTECH/NG-S4?style=flat-square&logo=github&colour=yellow">
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/pulls">
    <img alt="Pull Requests" src="https://img.shields.io/github/issues-pr/XAOSTECH/NG-S4?style=flat-square&logo=github&colour=purple">
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/XAOSTECH/NG-S4?style=flat-square&logo=github&colour=gold">
  </a>
  <a href="https://github.com/XAOSTECH/NG-S4/network/members">
    <img alt="Forks" src="https://img.shields.io/github/forks/XAOSTECH/NG-S4?style=flat-square&logo=github">
  </a>
</p>

<p align="center">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/XAOSTECH/NG-S4?style=flat-square&logo=git&colour=blue">
  <img alt="Repo Size" src="https://img.shields.io/github/repo-size/XAOSTECH/NG-S4?style=flat-square&logo=files&colour=teal">
  <img alt="Code Size" src="https://img.shields.io/github/languages/code-size/XAOSTECH/NG-S4?style=flat-square&logo=files&colour=orange">
  <img alt="Contributors" src="https://img.shields.io/github/contributors/XAOSTECH/NG-S4?style=flat-square&logo=github&colour=green">
</p>

<!-- Optional: Stability/Maturity Badge -->
<p align="center">
  <img alt="Stability" src="https://img.shields.io/badge/stability-stable-green?style=flat-square">
  <img alt="Maintenance" src="https://img.shields.io/maintenance/yes/2026?style=flat-square">
</p>

---

<p align="center">
  <b>NG-S4: Nginx {{SHORT_DESCRIPTION}} Stunnel4 RTMP/RTMPS restream server with HLS for Linux {{SHORT_DESCRIPTION}} WSL2. Broadcast to multiple platforms (from Windows or Linux)!</b>
</p>

---

# Nginx + Stunnel4 RTMP Restreaming Server

This project provides a set of scripts to set up an Nginx server with RTMP module, optionally routing RTMP/RTMPS streams through Stunnel4. This allows you to restream to multiple platforms like Twitch, YouTube, and Kick.

**Date Created/Last Updated:** May 14, 2025

## Core Features

*   **Multi-Platform Restreaming:** Configure Nginx to push your input stream to multiple RTMP/RTMPS endpoints.
*   **Stunnel4 for RTMPS:** Securely stream to services requiring RTMPS by tunneling RTMP through Stunnel4.
*   **HLS Output:** Configure Nginx to output HLS (HTTP Live Streaming) for playback in web browsers or media players.
*   **Flexible Configuration:** Uses a `real.env/master.env` file for easy customization of stream keys, paths, and application names.
*   **Helper Scripts:** Includes scripts for initial setup, service management (start, stop, status), SSL certificate generation for Stunnel, and a full reset.
*   **WSL2 Support:** Includes a PowerShell script (`WSL2-Setup/Install-RestreamWSL.ps1`) to automate WSL2 setup, Linux distribution installation, and running the restream server setup on Windows.
*   **WSL2 Management Scripts:**
    *   `WSL2-Setup/WSL2-mgr.ps1`: For backing up and restoring your WSL2 distribution.
    *   `WSL2-Setup/WSL2-UFW.ps1`: For managing Windows Firewall rules for WSL2.
    *   These scripts are typically run from within their directory (e.g., `NG-S4/WSL2-Setup/`) using a command like: `powershell.exe -ExecutionPolicy RemoteSigned -File .\\WSL2-mgr.ps1`

## Directory Structure

```
NG-S4/
├── example.env/            # Example configuration files
│   ├── master.env
│   ├── nginx.conf
│   └── stunnel.conf
├── real.env/               # Your actual configuration files (copy from example.env)
│   ├── master.env          # Main environment variables and stream keys
│   ├── nginx.conf          # Your Nginx configuration
│   └── stunnel.conf        # Your Stunnel4 configuration
├── UNIX-Scripts/           # Bash scripts for Linux setup and management
│   ├── setup-restream.sh
│   ├── generate-stunnel-cert.sh
│   ├── manage-services.sh
│   ├── reset-restream.sh
│   └── stream-gphoto2-webcam.sh
├── WSL2-Setup/             # PowerShell scripts for WSL2
│   ├── Install-RestreamWSL.ps1
│   ├── WSL2-mgr.ps1
│   └── WSL2-UFW.ps1
└── README.md               # This file
```

## Configuration (`real.env/`)

Before running any setup scripts, you **must** configure your environment.

1.  **Copy Example Configuration:**
    If the `real.env/` directory does not contain `master.env`, `nginx.conf`, and `stunnel.conf`, copy them from the `example.env/` directory:
    ```bash
    mkdir -p real.env
    cp example.env/master.env real.env/master.env
    cp example.env/nginx.conf real.env/nginx.conf
    cp example.env/stunnel.conf real.env/stunnel.conf
    ```
    *(The `WSL2-Setup/Install-RestreamWSL.ps1` script also attempts to do this copy if files are missing in `real.env`)*

2.  **Edit `real.env/master.env`:**
    Open `real.env/master.env` and update the following:
    *   `XX_TW_KEY`, `XX_YT_KEY`, `XX_KI_KEY`: **Replace these with your actual stream keys.**
    *   Review other path variables like `NGINX_WEB_CONTENT_SRC`, `HLS_BASE_DIR`, `STUNNEL_SSL_SUBJECT`, etc., and adjust if necessary.
    *   The `envDr` should point to your `real.env` directory, and `scriptsDr` to `UNIX-Scripts`. These should generally not need changing if you maintain the project structure.

3.  **Edit `real.env/nginx.conf`:**
    This is a critical step. Your `nginx.conf` defines how RTMP streams are handled, where they are pushed, and how HLS is generated.
    The file `example.env/nginx.conf` contains a comprehensive example incorporating common use cases like basic restreaming, HLS output, and applications for camera input (`Cam1`) and stream composition (`MultiMain`).
    You should:
    a.  Copy `example.env/nginx.conf` to `real.env/nginx.conf` (if not already done).
    b.  Carefully review and **adapt `real.env/nginx.conf` to your specific needs.**

    **Key considerations for `nginx.conf`:**
    *   **Stream Keys:** Replace placeholders like `YOUR_TWITCH_STREAM_KEY_HERE` in your `real.env/nginx.conf` with your actual keys (ideally sourced from `master.env` if your setup scripts handle variable substitution, or hardcoded if not). The example applications `XX_TW`, `XX_YT`, `XX_KI` in `example.env/nginx.conf` show placeholders.
    *   **Ingest URLs:** Ensure all `push rtmp://...` lines point to the correct ingest servers for each platform.
    *   **Stunnel Ports:** If using Stunnel, make sure the Nginx `push` URLs for RTMPS services match the `accept` ports in your `stunnel.conf` (e.g., `rtmp://127.0.0.1:19351`).
    *   **HLS Paths:** The `hls_path` in the RTMP block and the `root` in the HTTP `location /hls` block must correspond correctly. The `setup-restream.sh` script creates directories under `$HLS_BASE_DIR` (default `/mnt/hls`).
    *   **External Scripts (`pushCam1`, `pushM`):**
        *   For `pushCam1`-like functionality, your external script (using `gphoto2 | ffmpeg`) should push its RTMP output to an application defined in Nginx (e.g., `rtmp://<nginx_server_ip>:1935/Cam1`).
        *   For `pushM`-like functionality, your external `ffmpeg` script will pull from Nginx applications (e.g., `rtmp://localhost:1935/Main1`) and push the combined output to another Nginx application (e.g., `rtmp://localhost:1935/MultiMain`). Nginx simply provides the RTMP endpoints.

4.  **Edit `real.env/stunnel.conf`:**
    *   If you are using Stunnel4 for RTMPS, configure the services here.
    *   For each service (e.g., `[YT]`, `[KI]`):
        *   `accept = 127.0.0.1:LOCAL_PORT` (e.g., `127.0.0.1:19351` for YouTube). This is the port Nginx will push to.
        *   `connect = ACTUAL_RTMPS_INGEST_HOST:PORT` (e.g., `a.rtmp.youtube.com:443`). This is the actual RTMPS endpoint of the streaming service.
    *   The `cert` path is typically `/etc/stunnel/stunnel.pem` and is generated by `UNIX-Scripts/generate-stunnel-cert.sh`.

**Important `.gitignore` Note:**
The `.gitignore` in this project is typically set up to ignore the contents of `real.env/*` (except for the directory itself and potentially placeholder files if you choose to commit them initially). This is to prevent accidental commitment of your personal stream keys. Ensure your personalized `real.env` files are not tracked by Git if you are pushing to a public repository.

---

## I. WSL2 Installation (Windows 10/11)

This method uses PowerShell to set up WSL2, install a Linux distribution, and then run the Linux setup scripts.

### 1. Windows Prerequisites

*   **Enable WSL & Virtual Machine Platform:**
    You can do this via "Turn Windows features on or off" or by running PowerShell as Administrator:
    ```powershell
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    ```
    A **reboot is required** after enabling these features.

*   **Install a Linux Distribution from Microsoft Store (Optional if using `Install-RestreamWSL.ps1`):**
    If you don't use the `WSL2-Setup/Install-RestreamWSL.ps1` script to install a distro, you can install one like "Ubuntu" (e.g., Ubuntu 22.04 LTS) from the Microsoft Store and set up your user.

### 2. Run `WSL2-Setup/Install-RestreamWSL.ps1`

This script automates several steps:
*   Checks and helps enable WSL features (requires reboot if not already enabled).
*   Updates the WSL kernel.
*   Installs a specified Linux distribution (default: Ubuntu-22.04) if not already present.
*   Prompts you to copy/verify configuration files from `example.env/` to `real.env/`.
*   Executes the `UNIX-Scripts/setup-restream.sh` within the WSL distribution to install Nginx, Stunnel4, and configure them.

**Steps:**
1.  **Configure `real.env/` files as described in the "Configuration" section above.** This is crucial before running the script.
2.  Open PowerShell (preferably as Administrator, especially if WSL features need enabling).
3.  Navigate to the `NG-S4` project directory.
4.  Run the script:
    ```powershell
    .\\WSL2-Setup\\Install-RestreamWSL.ps1
    ```
5.  Follow any on-screen prompts. The script will execute `sudo bash UNIX-Scripts/setup-restream.sh` inside WSL.

### 3. WSL2 Network & Firewall (`WSL2-Setup/WSL2-UFW.ps1`)

WSL2 runs with a virtualized network. To access services running inside WSL2 from your local network (e.g., to send a stream from OBS on another machine to Nginx in WSL2), you'll need to:

1.  **Find WSL2's IP Address:**
    Open your WSL2 terminal and run: `ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1`
2.  **Port Forwarding / Firewall Rules:**
    The `WSL2-Setup/WSL2-UFW.ps1` script can help create Windows Firewall rules to allow traffic to your WSL2 instance.
    *   **Review and edit `WSL2-Setup/WSL2-UFW.ps1`** to ensure the ports you want to open (e.g., 1935 for RTMP, 8080 for HLS HTTP) are correctly listed.
    *   Run `WSL2-Setup/WSL2-UFW.ps1` in an **Administrator PowerShell**.
    *   You might need to update the firewall rules if your WSL2 IP address changes (it can change after a Windows reboot).

### 4. WSL2 Backup and Restore (`WSL2-Setup/WSL2-mgr.ps1`)

The `WSL2-Setup/WSL2-mgr.ps1` script provides functions to:
*   **Backup (Export):** Create a `.tar` archive of your WSL2 distribution.
*   **Restore (Import):** Restore a distribution from a `.tar` file, potentially as a new instance or overwriting an existing one.
*   **Reset:** Unregister and re-import a distribution from a backup.

**Usage:**
1.  Open PowerShell.
2.  Navigate to the `NG-S4/WSL2-Setup/` directory.
3.  Run the script: `.\WSL2-mgr.ps1`
4.  Follow the prompts to choose an action.

---

## II. Standalone Unix/Linux Installation

This method is for setting up the restreaming server directly on a dedicated Linux machine or a VM.

### 1. Prerequisites

*   A Linux system (e.g., Ubuntu, Debian).
*   `sudo` access.
*   `git` installed (`sudo apt install git`).

### 2. Clone Repository

```bash
git clone <repository_url> # Replace <repository_url> with the actual URL
cd NG-S4 # Or your chosen directory name
```

### 3. Configure Environment

Follow the steps outlined in the main **"Configuration (`real.env/`)"** section at the beginning of this README to copy and edit your `master.env`, `nginx.conf`, and `stunnel.conf` files.

### 4. Run Setup Script

The main setup script will install Nginx, Stunnel4, libnginx-mod-rtmp, generate SSL certs for Stunnel, copy configurations, and start the services.

```bash
sudo bash UNIX-Scripts/setup-restream.sh
```
Review the output for any errors.

### 5. Managing Services (`UNIX-Scripts/manage-services.sh`)

This script helps you manage Nginx and Stunnel4.

**Usage:** `sudo bash UNIX-Scripts/manage-services.sh {start|stop|restart|status|enable|disable} [nginx|stunnel4|all]`

**Examples:**
*   Check status of all services: `sudo bash UNIX-Scripts/manage-services.sh status all`
*   Restart Nginx: `sudo bash UNIX-Scripts/manage-services.sh restart nginx`
*   Stop Stunnel4: `sudo bash UNIX-Scripts/manage-services.sh stop stunnel4`

### 6. Generating Stunnel Certificate Manually (`UNIX-Scripts/generate-stunnel-cert.sh`)

The `setup-restream.sh` script calls this automatically. However, if you need to regenerate the Stunnel SSL certificate manually (e.g., if it expires or you change the subject in `master.env`):

```bash
sudo bash UNIX-Scripts/generate-stunnel-cert.sh
```
This will create/overwrite `/etc/stunnel/stunnel.pem`. Remember to restart Stunnel4 afterwards:
`sudo bash UNIX-Scripts/manage-services.sh restart stunnel4`

### 7. Resetting the Installation (`UNIX-Scripts/reset-restream.sh`)

This script will stop services, purge Nginx and Stunnel4 packages, and remove their configuration files and related directories. **Use with caution!**

```bash
sudo bash UNIX-Scripts/reset-restream.sh
```
After resetting, you can re-run `UNIX-Scripts/setup-restream.sh` for a fresh installation. Logs for the reset operation are stored in the directory specified by `LOG_DIR` in `master.env` (default: `/home/jnxlr/PROJECTS/LOG`).

### 8. Streaming with a gphoto2 Compatible Camera (`UNIX-Scripts/stream-gphoto2-webcam.sh`)

This script facilitates streaming video directly from a `gphoto2`-compatible camera (e.g., many DSLRs, mirrorless cameras) to your Nginx RTMP server.

**Functionality:**
*   Uses `gphoto2` to capture live video from the connected camera.
*   Pipes the video to `ffmpeg` for encoding (H.264 video, AAC audio by default).
*   Adds a silent audio track if the camera doesn't provide one, for better compatibility with RTMP servers.
*   Streams the final output to a specified RTMP URL, typically an input application on your Nginx server (e.g., `rtmp://127.0.0.1:1935/Cam1/my_camera_feed`).

**Prerequisites:**
*   `gphoto2` and `ffmpeg` must be installed. The `setup-restream.sh` script now includes these in its installation process.
*   A `gphoto2`-compatible camera connected to your Linux system.

**Configuration:**
*   The script `UNIX-Scripts/stream-gphoto2-webcam.sh` has configurable parameters at the top, such as default RTMP URL, video/audio bitrates, framerate, and ffmpeg preset.

**FFmpeg Command Breakdown (Conceptual):**
The `stream-gphoto2-webcam.sh` script uses `ffmpeg` to process the output from `gphoto2` and stream it. While the exact command can be seen in the script, here's a breakdown of common options you might find or want to adjust:
*   Input & Audio Generation:
    *   `-i pipe:0` or similar: Tells `ffmpeg` to read video data from standard input (piped from `gphoto2`).
    *   `-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100`: Generates a silent stereo audio track at 44.1kHz. This is crucial if your camera doesn't provide audio or for compatibility with some streaming platforms that require an audio track.
*   Video Encoding (`libx264` - H.264):
    *   `-c:v libx264`: Specifies the H.264 video codec.
    *   `-preset ultrafast`: A common preset for live streaming, prioritizing low CPU usage over quality/compression. Other presets include `superfast`, `veryfast`, `faster`, `fast`, `medium` (default), `slow`, `slower`, `veryslow`. Slower presets give better quality/compression at the cost of higher CPU.
    *   `-b:v 2000k` (e.g., 2 Mbps): Sets the target video bitrate. Adjust based on your internet upload speed and desired quality.
    *   `-maxrate 2500k`: Sets the maximum allowed video bitrate.
    *   `-bufsize 4000k`: Sets the decoder buffer size, often twice the maxrate.
    *   `-vf "format=yuv420p"`: Sets the pixel format to `yuv420p`, which is widely compatible.
    *   `-r 30`: Sets the output video framerate (e.g., 30 frames per second).
*   Audio Encoding (AAC):
    *   `-c:a aac`: Specifies the AAC audio codec.
    *   `-b:a 128k` (e.g., 128 kbps): Sets the audio bitrate.
    *   `-ar 44100`: Sets the audio sample rate (e.g., 44.1 kHz).
*   Output:
    *   `-f flv`: Specifies the output format as FLV, suitable for RTMP.
    *   `"$RTMP_URL"`: The destination RTMP server URL (e.g., `rtmp://127.0.0.1:1935/Cam1/my_stream_key`).

You can modify these parameters within the `stream-gphoto2-webcam.sh` script to fine-tune the output for your specific camera, network conditions, and streaming platform requirements.

**Usage:**
1.  Navigate to the scripts directory (e.g., if you are in `NG-S4`):
    ```bash
    cd UNIX-Scripts/
    ```
2.  Run the script. You may need `sudo` if `gphoto2` requires root permissions to access the camera hardware:
    ```bash
    sudo ./stream-gphoto2-webcam.sh [OPTIONAL_RTMP_URL]
    ```
    *   If `OPTIONAL_RTMP_URL` is not provided, it will use the `DEFAULT_RTMP_URL` defined inside the script (e.g., `rtmp://127.0.0.1:1935/Cam1/live_camera`).
    *   **Example:** To stream to the `Cam1` application on your local Nginx server with a stream key `my_gphoto_feed`:
        ```bash
        sudo ./stream-gphoto2-webcam.sh rtmp://127.0.0.1:1935/Cam1/my_gphoto_feed
        ```
3.  Press `Ctrl+C` to stop the stream.

**Note for WSL2 Users:**
Using `gphoto2` within WSL2 requires successful USB device passthrough from Windows to the WSL2 environment. This can sometimes be complex to configure (often involving `usbipd-win`). If you intend to use this script in WSL2, ensure your camera is accessible within the WSL2 Linux distribution.

---

## Troubleshooting

*   **Check Service Status:** Use `sudo bash UNIX-Scripts/manage-services.sh status all`.
*   **Nginx Logs:** Typically found in `/var/log/nginx/error.log` and `/var/log/nginx/access.log`.
*   **Stunnel4 Logs:** Check the `output` path specified in your `/etc/stunnel/stunnel.conf` (e.g., `/var/log/stunnel4/stunnel.log`). The debug level can also be adjusted in `stunnel.conf`.
*   **Permissions:** Ensure file and directory permissions are correct, especially for Nginx PID files, web content, HLS directories, and Stunnel run/log directories. The setup script attempts to handle these.
*   **Firewall:** On standalone Linux, ensure your system firewall (e.g., `ufw`) allows incoming connections on the necessary ports (e.g., 1935 for RTMP, or any ports Stunnel listens on if accessed externally, 8080 for HLS HTTP).
*   **WSL2 Networking:** If OBS or your streaming source can't connect to Nginx in WSL2, double-check the WSL2 IP address and your Windows Firewall rules (see WSL2 section).