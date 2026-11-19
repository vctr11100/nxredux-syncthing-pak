# nxredux-syncthing-pak

A [Syncthing](https://syncthing.net/) launcher for **NX Redux**, the custom firmware for TrimUI handhelds. Turn Syncthing on and off from the console's `Tools` menu and keep your saves, ROMs and other files in sync with your other devices.

This is a fork of [`josegonzalez/minui-syncthing-pak`](https://github.com/josegonzalez/minui-syncthing-pak), which targets NextUI and MinUI. The Syncthing handling is upstream's work; this fork replaces the NextUI-specific menu with NX Redux's native settings screen and fixes the environment differences between the two firmwares.

> [!NOTE]
> This pak does not rename files on disk before or after syncing, and cannot be used
> as a compatibility layer between handhelds. Files are synced as written to disk by other tools.

## Requirements

- **Firmware:** NX Redux (tested on v2.5.1).
- **Device:** TrimUI Brick Pro (`tg5040`, arm64). The Brick and Smart Pro share the same platform and should work, but they are untested.
- **Network:** the device must be connected to WiFi.

Not supported: NextUI, MinUI and other firmwares. Use the [upstream pak](https://github.com/josegonzalez/minui-syncthing-pak) for those.

## Installation

1. Mount your device's SD card.
2. Download `Syncthing.pak.zip` from this repository's Releases page.
3. Extract it into `Tools/tg5040/` so that `Tools/tg5040/Syncthing.pak/launch.sh` exists on the SD card.
4. Unmount the card and put it back in the device.

## Usage

Open `Tools > Syncthing`. The menu has one entry, `Settings`, with three rows:

- **Enabled:** starts or stops the Syncthing service.
- **Start on boot:** starts Syncthing automatically when the device boots. Off by default.
- **Syncthing version:** `2.x` (default) or `1.x`. See below.

Press `B` to apply your changes. The menu reopens with the current status on the hint line (for example `Running: http://192.168.1.20:8384`), and closes when you leave it without changing anything.

The web UI listens on port 8384, so from a computer on the same network open `http://<device-ip>:8384`. The default credentials are `minui` / `minui`; **change them in the web UI** under `Actions > Settings > GUI`.

### Syncthing version

The `Syncthing version` setting chooses between Syncthing 2.x, the default, and
Syncthing 1.x.

_The next two paragraphs come from upstream's testing on NextUI. They have not been measured on NX Redux. If your SD card is FAT32 or exFAT and Syncthing 2.x logs disk I/O errors, switch to 1.x._

Syncthing 2.x keeps its index in an SQLite database, and SQLite cannot run on a
FAT filesystem. MinUI and NextUI require the card to be exFAT or FAT32, so on
`h700` Syncthing 2.x reports `disk I/O error: input/output error` every few
seconds, and each failure drops a peer connection. Selecting `1.x` avoids this:
Syncthing 1.x keeps its index in LevelDB, which is unaffected.

Other platforms are less affected. On `tg5040` Syncthing 2.x produces no errors
in testing; its index journal simply never consolidates, so the database grows
larger than it should.

Worth knowing before switching:

- **Switching to 1.x costs a rescan. Switching back does not.** Syncthing 1.x
  cannot read 2.x's SQLite index, so it builds its own from scratch and
  re-exchanges index data with every peer; expect that to take a while over
  handheld WiFi. In the other direction Syncthing 2.x migrates the 1.x index
  itself, which on an h700 with 510 files took under a second with no rescan and
  no re-exchange. It leaves the old index behind as `index-v0.14.0.db-migrated`,
  which is safe to delete. Your device ID does not change either way and no peer
  needs re-approving.
- **Switching to 1.x rewrites `config.xml` and can drop settings.** The two
  versions know different configuration options, so 1.x re-saves the file through
  its own schema. The version number is left alone rather than converted, but
  options that exist only in 2.x are dropped, and options 2.x had retired come
  back at their defaults. Switching from 2.1.7 to 1.30.0 removed `pullerDelayS`
  and `blockIndexing` from each folder along with `sessionCookieDurationS` and
  `sessionCookiePath`, and added `disableTempIndexes`, `weakHashThresholdPct`,
  `urPostInsecurely`, `cacheIgnoredFiles` and `databaseTuning`. Your folders,
  devices and paths are not touched. Switching back to 2.x does not undo this:
  the file is left exactly as 1.x wrote it and the dropped options simply take
  their defaults. The original is kept beside it as `config.xml.v52`, which is
  the only way back to a 2.x-only value you had set deliberately.
- **Syncthing 1.x is no longer maintained.** v1.30.0, from July 2025, is the final
  1.x release and will receive no further fixes, including security fixes. It
  remains protocol compatible with 2.x, so it still syncs with up-to-date peers.

### Debug Logging

Logs are written to `.userdata/tg5040/logs/` on the SD card: `Syncthing.txt` (the launcher), `Syncthing.options.txt` (the menu), `Syncthing.service.txt` (Syncthing itself).

## Development

- `make build` downloads the bundled Syncthing binaries (arm64 only).
- `make test` runs the [bats](https://github.com/bats-core/bats-core) suite in `tests/`.

Both Syncthing versions are bundled: 2.x in `bin/<arch>/syncthing` and 1.x in
`bin/v1/<arch>/syncthing`. The 1.x build keeps the same filename deliberately, so
the running process is still called `syncthing` and `bin/service-off` can stop it
with `killall`, which matches process names exactly. The 1.x pin is final, because
v1.30.0 is the last release of that line.

A scheduled workflow opens a pull request when Syncthing publishes a new stable release, named and laid out like the dependabot pull requests for GitHub Actions. Each release gets its own `deps/github_releases/syncthing/syncthing-<version>` branch, an older open bump is closed as superseded by the newer one, and a bump closed without merging is not reopened. The workflow needs a `GH_ACCESS_TOKEN` repository secret with read and write access to contents and pull requests. Without it, the default workflow token can only open pull requests when "Allow GitHub Actions to create and approve pull requests" is enabled in the repository's Actions settings, and the pull requests it opens do not trigger CI.

## License

The original license is kept in `LICENSE`. Credit for the pak goes to [josegonzalez](https://github.com/josegonzalez); Syncthing is developed by the [Syncthing contributors](https://github.com/syncthing/syncthing).
