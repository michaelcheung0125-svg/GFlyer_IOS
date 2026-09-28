# GFlyer iOS personal sideload prototype

This is a separate SwiftUI prototype for personal sideloading. It does not modify the Android project.

## Current scope

- Branded MapKit home screen with place/coordinate search and map tool controls
- Current-device-location button with explicit Core Location permission handling
- Static teleport plus single-point, multi-point, and exploration modes
- Exploration follows GFlyer Android's serpentine pattern (GFlyer-Suite
  `docs/features/serpentine-exploration.md`; it replaces the `0.6.8` spiral):
  north for Y, 530 m sideways (「左（西）」 or 「右（東）」), then 2Y south, 530 m,
  2Y north and so on until stopped. Y is 200-5,000 m in 100 m steps (default
  1,000 m); Y and the direction are saved, apply to the next start, and are
  locked while exploring. The map previews 10Y + 2,120 m ahead from the start
  point (the simulated position while simulating, otherwise the selected
  point); while not exploring, the camera zooms to the whole preview whenever
  that start changes, including on entering 探索 and on a map tap there (not
  when only Y or the direction changes). Pressing 「開始探索」 again restarts
  from the current position; each
  0.25 s tick moves speed x 0.25 s with no minimum. An interrupted exploration
  resumes where it stopped with its saved progress, and a spiral snapshot left
  by `0.6.8` resumes as a fresh serpentine at its position (Y 1,000 m, east)
- Multi-point route playback with a nonlinear 1.8-900 km/h speed scale
- Route playback options ported from GFlyer Android: per-point teleport travel
  mode, dwell seconds, orbit (skippable) and micro-move arrival actions,
  manual "next point" advance, start countdown, and an auto-stop timer. They
  behave exactly like Android (GFlyer-Suite
  `docs/features/route-arrival-actions.md`): arrival actions, manual advance and
  dwell apply only to 「定點傳送」 on multi-point routes (a 「模擬移動」 route walks
  straight on), manual advance means no dwell, the countdown applies only to
  multi-point routes, and single-point routes and message-board routes started
  directly are a plain walk. Dwell is 1-300 seconds; orbit radii keep Android's
  cleanup (5-500 m, duplicates dropped, at most 4 laps, a new lap is 40 m) and
  are read when each orbit starts. Status texts match Android word for word,
  and a walk advances speed x 0.25 s per step (no 0.5 m minimum). Settings saved
  by 0.6.8 are migrated once when the app loads; people who used an arrival
  action or manual advance with 「模擬移動」 see a one-time notice. The saved
  arrival action is never rewritten (a 「模擬移動」 route still walks straight
  after a rollback to 0.6.8); 繞圈 is pre-selected the first time someone
  switches to 「定點傳送」, which is Android's default
- Cross-date teleport reminder using the Android longitude-based offline
  UTC-offset estimate
- Visible iOS 17 background location activity for route and exploration playback
- Pause, resume, stop, looping, and return behavior. Like Android, only
  multi-point routes loop; the return options are 「走回起點」 and 「瞬間跳轉」
- In-app foreground joystick with Android-parity displacement speed dynamics,
  edge continuous acceleration, and an independent speed cap
- Reusable built-in and custom speed presets (at most 6, the same limit as
  Android; people who already saved more than 6 keep them but cannot add more).
  Speeds are compared like Android, as km/h with a 0.01 km/h tolerance: built-in
  presets restored from an Android backup stay built-in (no delete button), and
  the 「注意: 超過 20 km/h 將無法種花」 warning appears only above 20 km/h. The old
  Android walk preset (1.4 m/s) restores as 5.0 km/h, and a 5.04 km/h walk preset
  saved by an earlier restore is corrected when the app loads
- Local favorites, history, favorite folders, named routes, and route-draft recovery.
  Favorite names are trimmed and cut to 80 Unicode code points when added or
  renamed, a blank rename is refused, and, like Android, an unnamed favorite is
  called 「收藏 <座標>」 and a coordinate that is already a favorite is not added
  again (「此座標已經收藏過」)
- Country and city labels in the favorite, history and saved-route lists like
  GFlyer Android (GFlyer-Suite `docs/features/region-labels.md`). A favorite's
  second line reads `25.033900, 121.564500  ·  臺灣 · 臺北市` and a saved
  route's `12 個點 · 循環 · 臺灣 · 臺北市` (the label of its first point); each
  row gains 「收藏於」, 「定位於」 or 「儲存於」 with the medium date and short time
  in the system language. The labels come from OpenStreetMap Nominatim (see
  [Privacy](#privacy)): favorites and the first point of each saved route are
  looked up when the app starts and whenever those lists change, one request
  at a time with at least 1.1 s between requests, cached per 0.01° cell
  (about 1 km) under their own UserDefaults key and never in the backup.
  History is never looked up; a failed lookup shows nothing and is retried on
  the next launch
- GPX 1.1 import (tracks, routes, and loose waypoints; several files at once)
  and all-routes export. Like Android, an unreadable file is skipped, one
  message reports the total, import works while simulating, and the first
  imported route is loaded into the editor only when no simulation is running
  and the draft has at most one point, without changing the loop setting
- Cross-platform backup/restore in the Android-compatible `GFlyer Backup` v1
  JSON format (favorites, history, folders, routes, speed presets). Settings
  keys iOS does not use are kept and written back on export, so an
  Android -> iOS -> Android round trip no longer resets Android-only settings.
  Import follows the same rules as Android (GFlyer-Suite
  `contracts/backup.schema.json`): a bad item is skipped on its own, JSON
  booleans and numbers are kept apart, names are truncated by Unicode code
  point, shared settings missing from the file reset to their defaults, and a
  non-option auto-stop value rounds to the nearest option (ties go up)
- Coordinate library (座標圖鑑) downloaded from the GFlyer-updates Pages JSON,
  with favorites, visit reminders, and anonymous 「回報資料已過時」 reports for
  postcards (the same reasons, request and single failure message as Android);
  unlike Android there is no bundled seed, so the first load needs network
  access. The parser keeps JSON booleans and numbers apart like the backup
  import
- Coordinate-library teleport history and 「隱藏已前往」 like GFlyer Android
  (GFlyer-Suite `docs/features/library-teleport-history.md`): 「傳送」 on a
  library row records the time and a count (「預覽」, an invalid coordinate
  and a teleport refused during a simulation record nothing). The row shows
  「➤ 已前往 09/19 14:32 · 3 次」 and its ⋯ menu has the full time and
  「清除紀錄」. The 「隱藏已前往」 chip under the search field hides visited
  coordinates (except on 「⏲ 提醒中」) next to 「已前往 N / 總數」, counted
  before hiding. The history is kept apart from the visit reminders, only on
  the device under its own UserDefaults keys, and is not in the backup
- Interrupted-session snapshots with a relaunch resume prompt (10-minute window)
- Manual step logging through a user-supplied Shortcut, with 1000/3000/5000
  presets, a custom amount, and a seven-day history. GFlyer never touches
  HealthKit itself, because a free Apple ID cannot carry that entitlement, so
  the feature works on free and paid signing alike. A map-toolbar button logs
  a configurable amount in one tap once the Shortcut has succeeded at least
  once; before that it opens the setup screen instead of firing a Shortcut
  that may not exist
- Airplane-mode assistant for cellular users. Simulation is more reliable when
  the tunnel is built with the radio off, so the app watches `NWPathMonitor`,
  tells the user which of the three steps they are on, and advances by itself
  when airplane mode is toggled from Control Center. iOS exposes no API for an
  app to toggle airplane mode, so an optional user-supplied Shortcut does the
  switching; only turning it back **off** is ever automatic
- LocalDevVPN hand-off. A free Apple ID cannot sign a Network Extension, so
  GFlyer cannot carry its own VPN; instead it drives LocalDevVPN through
  `localdevvpn://enable?scheme=gflyer` (and `disable`), which switches the VPN
  and returns to GFlyer after about a second. Start opens it automatically
  when the route to the target IP does not go through a VPN interface; the
  full-clear action can optionally switch it off afterwards, but only once the
  clear itself has succeeded. The result is confirmed by a routing-table check
  on return, not by the callback, so a manual return works too
- Private message board shared with GFlyer Android for coordinates, routes,
  announcements, replies, tags, pinning, expiry, and member administration
- Pairing-file import and protected local storage
- Preview backend that builds without native dependencies
- Optional `idevice` backend for device-wide GPS simulation
- Stop clears the set point and keeps the CoreDevice session for the next
  Start; a separate full-clear action tears the session down and then verifies
  the reported location, telling the user whether it is real, still simulated,
  or unavailable

The prototype deliberately excludes anti-detection, modified third-party clients, and App Store distribution.

The feature UI, current-location flow, background activity, message-board unit
tests, and native archive pass the repository's macOS/Xcode CI. Message-board
version `0.2.0 (4)` still requires target-iPhone and Android/iOS interoperability
testing; Windows checks do not replace those device gates.

Version `0.3.0 (5)` adds the Android-parity feature set above (playback
options, cross-date reminder, joystick dynamics, GPX, backup/restore,
coordinate library, and session resume) with new unit tests. Commit `ada19c5`
passed both macOS CI jobs in
[workflow run 33500571429](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/33500571429):
38 simulator unit tests with 0 failures, plus the unsigned arm64 device
archive and IPA. Personal signing, target-iPhone regression, and live
Android/iOS backup interoperability remain separate validation gates.

Version `0.6.0 (13)` adds the one-tap step button and the airplane-mode
assistant described above.

Version `0.4.0 (6)` added the in-app update check, and `0.4.1`-`0.4.5` were
verified on the target iPhone through the SideStore source: install, in-app
update prompts, the app icon, playback fixes, and the clear-simulation
behaviour described below. The per-version history lives in `HANDOFF.md`; the
currently published release is listed in the public `altstore.json`.

## Installing with AltStore / SideStore

The unsigned CI IPA can be installed directly by AltStore or SideStore, which
re-sign it with your own Apple ID. An AltStore source is published next to the
Android update manifest so new versions appear inside the app:

```text
https://michaelcheung0125-svg.github.io/GFlyer-updates/altstore.json
```

This does not extend the signing period. A free Apple ID still expires after
seven days; AltStore and SideStore only automate the refresh. See
[docs/ALTSTORE_DISTRIBUTION.md](docs/ALTSTORE_DISTRIBUTION.md) for the install
steps and the source format. The source entry is generated from a built IPA by
`tools/release/release_manifest.py` in the GFlyer-Suite repository (`build ios`,
then `project`), which also maintains the cross-platform `releases.json` next to
`altstore.json`.

## Release process

Every code change reaches users through the runbook in
[docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md): bump the version in
`Info.plist`, push and wait for CI, download the unsigned IPA artifact,
**inspect the IPA payload** (a green CI run does not prove the payload is
complete — an early build shipped without the entire asset catalog), publish
it as an `ios-v<version>` release in the public `GFlyer-updates` repository,
update `altstore.json` and `releases.json` with GFlyer-Suite's
`tools/release/release_manifest.py` (`build ios`, then `project`, with a
`--dry-run` first), verify the live source and download URL, then record the
version in `HANDOFF.md`.

The two optional Shortcuts (step logging and the airplane toggle) are
documented in [docs/SHORTCUTS.md](docs/SHORTCUTS.md), including why each one
has to be a Shortcut rather than app code.

Solved problems are logged case by case in
[docs/TROUBLESHOOTING_CASES.md](docs/TROUBLESHOOTING_CASES.md), including the
exact error strings, what actually fixed each one, and which attempts did not
work — that last part is the time saver when the same symptom returns.

The runbook also lists the decisions that must not be reverted (SideStore's
flat source format, the resigned-bundle-identifier matching, the XcodeGen
resources rule, the split SwiftUI view bodies, and the clear-simulation
verification rule). Read that section before touching related code.

## End-user guide

The Traditional Chinese usage guide is published at
https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html
(hosted in the public `GFlyer-updates` repository) and linked from the app's
**Settings -> About -> Usage guide**. The 2026-09-04 edition covers install and
full daily use in twelve parts, written for complete beginners: glossary,
animated overview diagram, per-stage checkpoints, the four simulation modes,
favourites/routes/GPX/backup, both optional Shortcuts, the device-confirmed
full-clear + airplane-mode recovery, and troubleshooting split into install /
location / Shortcuts tables.

It recommends **SideStore (Nightly)** over Stable, because the fixes new iOS
releases need land there first. Every iloader step quotes the on-screen label in
both Traditional Chinese and English (`揀版本` / `Choose a build`,
`SideStore（夜晚版）` / `SideStore (Nightly)`), since the installer's own UI
language varies. The maintainer-facing install notes stay in
[docs/ALTSTORE_DISTRIBUTION.md](docs/ALTSTORE_DISTRIBUTION.md).

## Why the backend is separate

iOS has no public equivalent to Android's mock-location provider. Device-wide simulation uses Apple developer services through the MIT-licensed [`idevice`](https://github.com/jkcoxson/idevice) library:

```text
pairing file
  -> LocalDevVPN at 10.7.0.1:49152 (raw RPPairing)
  -> CoreDevice/RPPairing tunnel
  -> verified Personalized Developer Disk Image mount (when needed)
  -> RemoteXPC remote server
  -> location_simulation_set(latitude, longitude)
```

The normal `GFlyerIOS` scheme uses a preview backend. The `GFlyerIOS-Idevice` scheme enables the native backend after the static library is installed.

## Android/iOS message board

The iOS message board uses the same Cloudflare Worker/D1 REST API as GFlyer
Android. A device joins with the administrator bootstrap code or the active
shared invitation code. Its bearer session token is stored in iOS Keychain;
only the display name and last-read time use `UserDefaults`.

Members can share a current or saved coordinate, a saved route, tags and
replies. Shared coordinates and routes can be previewed, started, or saved into
the local iOS library. Administrators can publish announcements, pin posts,
replace/revoke the shared invite, promote members, and revoke individual
devices. The board refreshes when the App becomes active and shows an unread
badge without treating the user's own posts or replies as unread.

Every length limit is counted in Unicode code points, the same unit as the
Worker and Android (GFlyer-Suite `docs/features/message-board-limits.md`): user
name 30, replies, remarks and announcements 300, tags 20, the tag inputs 120,
the search field 80. Favorite and route names are normalized to 80 code points
before sharing, so names saved by older versions no longer get rejected. Tag
de-duplication is case-sensitive and the local messages use Android's wording.

This HTTPS service is independent from the device-location transport. The
message-board client never reads or uploads the Pairing File, DDI, Apple signing
material, CoreDevice socket data, or simulated-location state. The configured
endpoint is `GFlyerMessageBoardAPIURL` in `GFlyerIOS/Info.plist` and must remain
a public HTTPS URL.

## Privacy

收藏位置與收藏路線第一點的座標，會在 App 開啟或收藏變動時送往 OpenStreetMap 的 Nominatim 服務，反查所在的國家與城市；查到的結果只存在本機，不會放進備份檔。

The coordinates of your favorites and of the first point of each saved route
are sent to the public Nominatim service when the app starts or those lists
change, to look up their country and city. The results are stored only on the
device and are not included in backup files. Each request carries only that
coordinate, the fixed language `zh-TW` and the `GFlyer/<version> (iOS)`
User-Agent; history entries are never sent. This is the only feature that
contacts Nominatim: place search uses Apple's MapKit.

## macOS prerequisites

- A Mac with current Xcode
- Xcode command-line tools
- XcodeGen (`brew install xcodegen`)
- Rust (`rustup`)
- An Apple ID for personal signing
- An iPhone running iOS 17.4 or newer with Developer Mode enabled

## Automated macOS validation

The repository includes `.github/workflows/macos-xcode.yml`. On GitHub's
macOS runner it:

- generates the Xcode project and runs the preview scheme unit tests on an
  available iPhone simulator;
- builds the pinned `idevice` static library;
- archives the `GFlyerIOS-Idevice` scheme without code signing; and
- uploads an unsigned IPA and `.xcarchive` as a short-lived workflow artifact.

The unsigned artifact proves that the device target can be compiled and linked.
It cannot be installed on an iPhone until it is signed with the owner's Apple
development identity and provisioning profile. No Apple signing secret is
required or stored by this workflow.

The macOS validation passed on Xcode 16.4 for commit `9728992`: simulator unit
tests completed successfully and the native `GFlyerIOS-Idevice` archive produced
the unsigned `0.1.2 (3)` artifact, including retained CoreDevice sessions after
Stop/Clear. See [workflow run 31932297918](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/31932297918).
Personal signing and target-iPhone behavior remain separate verification gates.

Message-board version `0.2.0 (4)` passed both jobs for commit `1eabf69` in
[workflow run 32275792347](https://github.com/michaelcheung0125-svg/GFlyer_IOS/actions/runs/32275792347).
The run executed 15 simulator tests, including Android/Worker JSON fixtures,
unread counting, input normalization, and shared-content persistence, then
produced an unsigned arm64 device archive and IPA. Live Android/iPhone exchange
and personal signing remain separate validation gates.

## Generate and open the project

```bash
cd GFlyer_IOS
xcodegen generate
open GFlyerIOS.xcodeproj
```

Choose your personal team under **Signing & Capabilities** and install the regular `Debug` build first. It operates in preview mode and validates the map and route engine.

## Enable device-wide simulation

Build the pinned `idevice` revision on the Mac:

```bash
cd GFlyer_IOS
chmod +x scripts/build_idevice.sh
./scripts/build_idevice.sh
xcodegen generate
```

Then open the project and select the `GFlyerIOS-Idevice` scheme. The script installs:

```text
GFlyerIOS/Vendor/idevice/include/idevice.h
GFlyerIOS/Vendor/idevice/include/module.modulemap
GFlyerIOS/Vendor/idevice/lib/libidevice_ffi.a
```

These generated files are ignored by Git.

## First-time device setup

1. Install the app from Xcode or your preferred sideloading tool.
2. Generate a pairing file for this iPhone using a trusted computer workflow such as iLoader/StikDebug's pairing guide.
3. Send the file directly to the iPhone Files app. Avoid workflows that remove the extension.
4. In GFlyer, open Settings and import the pairing file.
5. Install LocalDevVPN. Keep its default device address `10.7.0.1` unless your setup uses another address. Start switches to LocalDevVPN and back by itself when the VPN is off; the Settings screen shows the VPN state, has a manual on/off button, and can still **Test LocalDevVPN tunnel**. The current raw RPPairing path connects on port `49152`.
6. Return to GFlyer, choose a point or route, and start simulation. On first device-mode use, allow the app to download and verify the pinned Personalized DDI (about 16 MB).
7. The first time you use the current-location button or start a route, grant GFlyer **While Using the App** location access. Route playback uses a visible iOS background-location activity and ends it when the route stops.
8. Press Stop before disabling LocalDevVPN so the app can call `location_simulation_clear()`. A successful Stop restores real GPS but keeps the CoreDevice transport ready for the next simulation. Changing the target IP or importing a different pairing file rebuilds that transport.

On the tested cellular path, an already-established CoreDevice socket survives
the switch from airplane mode to cellular data, while a new socket cannot be
opened over cellular. Establish the first channel in airplane mode, then enable
cellular data. Stop/Clear and a subsequent Start should reuse that channel. If
the App process, LocalDevVPN, or socket is terminated, establish it again. This
workflow is pending target-iPhone validation in the next IPA. Wi-Fi and personal
hotspot users do not need airplane mode; reconnect LocalDevVPN instead.

After this initial setup, normal use should not require the computer. A computer may be needed again when:

- iOS invalidates the pairing file after an update
- the sideloaded signing profile expires
- an iOS release changes the private developer protocol
- the app or LocalDevVPN must be reinstalled

Record the hard-gate result in
`docs/DEVICE_FEASIBILITY_CHECKLIST.md` before starting feature-parity work.

## Important limitations

- This is a research/personal-use path, not an App Store-compatible capability.
- Background route playback uses the documented iOS 17 `CLBackgroundActivitySession` and `location` background mode. iOS displays its background-location indicator; this consumes additional battery and is not a guarantee against force quit, resource termination, VPN loss, or every future iOS behavior change.
- A stale CoreDevice channel is discarded and rebuilt once after transient transport errors such as `BrokenPipe` or `Channel closed`.
- Clearing the simulation does not guarantee an immediate return to real GPS.
  On the test device iOS kept reporting the cached simulated fix even after the
  simulation session was torn down; an airplane-mode toggle was confirmed
  necessary before real GPS returned. Stop therefore keeps the session
  (cellular-friendly) and reports honestly; the Settings full-clear tears the
  session down, then verifies by requesting a fresh fix and tells the user
  whether the reported location is real, still simulated (with the
  LocalDevVPN-off / airplane-mode guidance), or unavailable.
- MapKit search and map tiles require network access. The pinned DDI is downloaded once; GPS simulation then uses the local VPN path.
- The shared message board requires Internet access and a valid, non-revoked
  invite/session. It is unavailable offline, but this does not block the local
  CoreDevice positioning path.
- Keep the pairing file private. It contains credentials that identify a trusted host for this iPhone.
- Third-party apps may reject simulated location or enforce their own terms.

## License boundary

- New GFlyer iOS source in this directory is original project code.
- `idevice` is MIT licensed and must retain its copyright/license notice when distributed.
- No StikDebug AGPL application source or binary is copied into this project.
