
## [Unreleased]

### Added
- Hardware-accelerated fan-out transcode engine (`ng-s4-transcode.sh`) with per-platform profiles, NVENC/V4L2 M2M/software auto-detection, HDR passthrough and HDR to SDR tone mapping.
- Capability and configuration checker (`ng-s4-doctor.sh`) for verifying each host.
- LAN publish/play control, HLS preview and a health endpoint in the ingest configuration.

### Changed
- Rewrite `nginx.conf` around a single ingest application that triggers the transcoder; port, LAN range and HLS path are rendered from `master.env` at setup.
- Restructure `master.env` into core settings plus per-target HDR/SDR restream profiles.
- `setup-restream.sh` now installs the engine, renders the config, detects encode hardware and validates nginx before starting.
- `generate-stunnel-cert.sh` requires root and uses temporary files for key material.
- `stream-gphoto2-webcam.sh` selects the best hardware encoder and targets the ingest app.
- Make log directories host agnostic (`/var/log/ng-s4`).

### Fixed
- Invalid `//` comments in `nginx.conf` that prevented nginx from parsing the configuration.

## [0.1.0] - 2026-05-04 (re-release)

### Changed
- Merge pull request #5 from XAOSTECH/anglicise/20260501-040625
- chore: convert American spellings to British English
- chore: update git tree visualisation
- chore: update git tree visualisation
- chore: update git tree visualisation
- chore: update CHANGELOG for v0.1.0 (re-release)
- Merge pull request #4 from XAOSTECH/anglicise/20260401-033418
- chore: convert American spellings to British English
- chore: update git tree visualisation
- chore(dc-init): load workflows,actions
- chore(dc-init): recover interrupted update
- chore: update CHANGELOG for v0.1.0 (re-release)
- chore(dc-init): update workflows and actions
- Merge pull request #3 from XAOSTECH/anglicise/20260301-031812
- chore: convert American spellings to British English
- Merge pull request #2 from XAOSTECH:replace/20260228-164051

chore: Replace text - automated update
- chore: replace text across repository
- dc-init update
- gc-init

## [0.1.0] - 2026-04-06 (re-release)

### Changed
- Merge pull request #4 from XAOSTECH/anglicise/20260401-033418
- chore: convert American spellings to British English
- chore: update git tree visualisation
- chore(dc-init): load workflows,actions
- chore(dc-init): recover interrupted update
- chore: update CHANGELOG for v0.1.0 (re-release)
- chore(dc-init): update workflows and actions
- Merge pull request #3 from XAOSTECH/anglicise/20260301-031812
- chore: convert American spellings to British English
- Merge pull request #2 from XAOSTECH:replace/20260228-164051

chore: Replace text - automated update
- chore: replace text across repository
- dc-init update
- gc-init
- Replace Unlicense with GNU General Public Licence
- Add contribution guidelines to CONTRIBUTING.md
- Add LICENSE file for public domain dedication

## [0.1.0] - 2026-03-09 (re-release)

### Changed
- chore(dc-init): update workflows and actions
- Merge pull request #3 from XAOSTECH/anglicise/20260301-031812
- chore: convert American spellings to British English
- Merge pull request #2 from XAOSTECH:replace/20260228-164051

chore: Replace text - automated update
- chore: replace text across repository
- dc-init update
- gc-init
- Replace Unlicense with GNU General Public Licence
- Add contribution guidelines to CONTRIBUTING.md
- Add LICENSE file for public domain dedication

