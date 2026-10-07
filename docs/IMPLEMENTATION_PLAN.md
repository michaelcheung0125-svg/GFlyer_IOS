# GFlyer iOS implementation plan

## Objective

Build a personal, sideloaded iOS version of GFlyer that can control device-wide simulated GPS without a computer connected during normal use.

The accepted operating model is:

1. A computer may be used for the initial build, install, signing, Developer Mode setup, and pairing-file generation.
2. The iPhone imports and stores its pairing file locally.
3. LocalDevVPN exposes the same iPhone through a local loopback path.
4. GFlyer verifies and mounts a pinned Personalized Developer Disk Image when required.
5. GFlyer connects to Apple developer services through `idevice` and sends location updates.
6. Normal teleport and route playback do not require a connected computer. Route and exploration playback use a visible iOS background-location activity while active.

## Hard feasibility gate

Do not expand the full feature set until all of these pass on the owner's target iPhone and iOS version:

- The `GFlyerIOS-Idevice` scheme installs through personal signing.
- A current pairing file can establish the CoreDevice/RPPairing tunnel through LocalDevVPN.
- The pinned DDI downloads, passes SHA-256 verification, and mounts when developer services are unavailable.
- Sending one coordinate changes the location shown by Apple Maps.
- Sending a second coordinate reuses the active connection.
- Stop calls `location_simulation_clear()`, Apple Maps returns to real location,
  and the healthy CoreDevice session remains available for a subsequent Start.
- Disconnecting the computer does not affect the above workflow.

If this gate fails, capture the iOS version, device model, pairing method, LocalDevVPN version, and backend error stage before changing UI code.

## Architecture

```text
SwiftUI / MapKit
  -> SimulationController
     -> GeoMath and route playback
     -> DeviceLocationService
        -> current-device location
        -> CLBackgroundActivitySession while a route is active
     -> LocationSimulationBackend
        -> PreviewLocationSimulationBackend
        -> IdeviceLocationSimulationBackend
           -> pairing file
           -> LocalDevVPN 10.7.0.1:49152 (raw RPPairing)
           -> CoreDevice/RPPairing
           -> Personalized DDI mount when required
           -> RemoteXPC
           -> location_simulation
  -> MessageBoardController
     -> Keychain session token
     -> HTTPS Cloudflare Worker / D1
        <-> GFlyer Android message board
```

The platform boundary must remain narrow. Route planning, GPX, favorites, history, speed, cooldown, and joystick behavior must not call `idevice` directly.
The message-board client is a separate Internet boundary: it receives only its
own authentication and post payloads and must never receive Pairing File, DDI,
signing, CoreDevice, or location-transport secrets.

## Milestones

### M0: Device-location spike

Status: implementation and macOS CI passed on Xcode 16.4. Since `0.4.0` the
app has been installed and updated on the target iPhone through the SideStore
source (re-signed with the owner's Apple ID), the `0.4.x` clear-simulation
behaviour was device-confirmed, and on 2026-10-01 the owner reported that
`0.6.9` passed device testing (not itemized). The hard-gate rows, including
the pass without a connected computer, are still not recorded in
`docs/DEVICE_FEASIBILITY_CHECKLIST.md`.

- Run preview scheme unit tests on a GitHub Actions macOS runner.
- Build and link the pinned `idevice` library in an unsigned device archive.
- Import a pairing file.
- Set and clear one coordinate.
- Translate backend failures into distinct stages: pairing, tunnel, RemoteXPC, service, set, and clear.
- Retain a healthy CoreDevice session after tunnel tests and Stop/Clear; rebuild
  it after transport failure, target-IP change, or pairing-file replacement.

Exit criterion: the hard feasibility gate passes.

The CI artifact is deliberately unsigned. The green workflow is a compilation
gate only and does not satisfy the personal-signing or device-location exit
criteria. Record target-device evidence in `docs/DEVICE_FEASIBILITY_CHECKLIST.md`.

### M1: Foreground MVP

Status: feature implementation complete and passing macOS/Xcode CI; distributed
through SideStore and device-tested by the owner up to `0.6.9` (reported
passing on 2026-10-01, not itemized). The 30-minute foreground route in the
exit criterion has not been recorded.

- Branded map home, search, map tools, and collapsible controls
- Map selection and static teleport
- Single-point and multi-point straight-line routes
- Nonlinear 1.8-900 km/h speed scale and reusable presets (at most 6 after
  `0.6.8`, aligned with Android; existing lists above 6 are kept). For `0.6.9`:
  speed comparisons use Android's 0.01 km/h tolerance (built-in preset
  recognition, flower warning with Android's text), and the old Android walk
  preset restores as 5.0 km/h (GFlyer-Suite `speed/preset-speed-values.json`,
  `backup/legacy-walk-preset.json`; covered by `SharedContractTests`)
- Pause, resume, stop
- Loop route with walk-back or instant return (for `0.6.9`, like Android:
  multi-point routes only, and the instant return is labelled 「瞬間跳轉」)
- Foreground joystick and exploration (Android's serpentine pattern from
  `0.6.9`, replacing the spiral)
- Visible backend and connection state

Exit criterion: a 30-minute foreground route completes without losing the tunnel or leaving simulated GPS active after Stop.

### M2: GFlyer feature parity

- Android-compatible private message board for coordinates, routes,
  announcements, replies, tags, expiry and pinning (implemented in `0.2.0 (4)`;
  macOS CI passed at `1eabf69`; cross-device validation pending)
- Invite/admin authentication, Keychain session storage, unread badge and
  member/invitation administration (implemented; macOS CI passed, live backend
  administration validation pending)
- Preview, start and save Android-shared coordinates/routes in the iOS local
  library (implemented; target-iPhone validation pending)
- Place and coordinate search (implemented; validation pending)
- Favorites, favorite folders, and local history (implemented; validation pending).
  For `0.6.9`: favorite names follow `docs/features/name-limits.md` (N2 on add
  and rename, blank rename refused), and the star button follows Android
  (「收藏 <座標>」 default, no duplicate favorites). Also for `0.6.9`: country ·
  city labels per `docs/features/region-labels.md`. `RegionLabel` holds the
  pure logic (cache key `%.2f,%.2f`, the Nominatim request, response → label);
  `RegionLookup`, owned by `SimulationController`, is Android's queue (one
  request at a time, FIFO, 1.1 s after every real request, per-run queued and
  failed sets, no retry until the next launch) with a cache under the new key
  `gflyer.region-labels.v1` that is never expired and never in the backup.
  Favorites and then the first point of each saved route are requested at
  start and on every `refreshStoredData()`; history never is. Since 0.6.11 the
  ☆ name sheet also sends an urgent lookup for an unlooked-up area (front of the
  queue, same 1.1 s spacing). Favorite and history rows show the label on the
  date line (「收藏於／定位於 <date>  ·  <label>」, at most two lines); saved
  routes show it after 「N 個點 · 循環|單程」 (`" · "`) above a 「儲存於」 date line. `RegionLabelTests` copies
  `region/nominatim-labels.json` and tests the queue with a fake transport
  and clock. Device validation pending
- Named routes and route-draft recovery after relaunch (implemented; validation pending)
- GPX import and export (implemented in `0.3.0 (5)`: multi-track import into
  saved routes with unique naming, all-routes export; device validation
  pending). For `0.6.9` the batch flow follows GFlyer-Suite
  `docs/features/gpx-import.md` and Android: unreadable files are skipped, one
  message per batch, import allowed while simulating, the loop setting is left
  alone when the first route is loaded
- Route playback options ported from Android (implemented in `0.3.0 (5)`:
  per-point teleport travel mode, dwell seconds, orbit (skippable) and
  micro-move arrival actions, manual advance, start countdown, auto-stop
  timer; device validation pending). For `0.6.9` they follow GFlyer-Suite
  `docs/features/route-arrival-actions.md` and Android exactly: the options
  used by a run come from `RoutePlaybackOptions.effective` (arrival actions,
  manual advance and dwell only for multi-point 「定點傳送」, countdown only for
  multi-point starts, board routes started directly walk plainly), each
  arrival from `RouteArrivalSteps`, orbit and micro-move steps from
  `OrbitPlanner.lap` / `MicroMovePlanner`; Android's status texts, dwell
  1-300 s, orbit-radius cleanup and editor (±5, delete any lap, add 40 m),
  no 0.5 m per-step walking minimum. 0.6.8 settings are migrated once
  (`PlaybackSettings.migratedToArrivalRulesV2`, spec §5.3) with a one-time
  notice for 「模擬移動」 users who lose an arrival action or manual advance.
  The stored arrival action is never rewritten, so a rollback to 0.6.8 (which
  runs arrival actions in both travel modes) keeps walking straight; fresh
  installs and 「模擬移動」 + no action store 「無」 with
  `preselectsOrbitForTeleport`, and `selectTravelMode` pre-selects 繞圈 once
  on the first switch to 「定點傳送」.
  The whole `route/arrival-actions.json` fixture is copied into
  `SharedContractTests`; the migration rows are in `PlaybackFeatureTests`

  The `0.3.0 (5)` additions above and below passed both macOS CI jobs at
  commit `ada19c5` (workflow run 33500571429: 38 simulator unit tests with 0
  failures, unsigned arm64 archive/IPA). Target-iPhone regression and live
  Android interoperability remain open.
- Joystick movement (implemented for foreground use; `0.3.0 (5)` adds the
  Android displacement-based speed dynamics, edge continuous acceleration and
  an independent joystick speed cap; validation pending)
- Exploration (spiral implemented earlier; validation pending). For `0.6.9`
  it becomes Android's serpentine exploration per GFlyer-Suite
  `docs/features/serpentine-exploration.md`: `SerpentinePath` ports Android's
  geometry line by line, Y (200-5,000 m, step 100) and the direction live in
  `PlaybackSettings`, a run is an `ExplorationRun`, pressing 「開始探索」 while
  exploring restarts from the current position, there is no 0.5 m per-tick
  minimum, and the map preview is cached. While not exploring, the camera fits
  the whole preview (between the search bar and the control panel,
  `ExplorationCamera`) whenever the preview start changes, like Android's
  `newLatLngBounds` fit (spec §3.5). Interrupted explorations resume from
  the interruption point with the saved progress; `ActiveSessionSnapshot`
  decodes 0.6.8 spiral snapshots and resumes them as a fresh serpentine. The
  whole `explore/serpentine-path.json` fixture is copied into
  `SharedContractTests`; the snapshot migration and settings are in
  `PlaybackFeatureTests`. Device validation pending
- Cross-date teleport warning (implemented in `0.3.0 (5)` with the Android
  longitude-based offline estimate; validation pending)
- Cross-platform backup/restore in the Android `GFlyer Backup` v1 JSON format
  (implemented in `0.3.0 (5)`; cross-platform restore validation pending).
  Unknown `settings` keys are preserved and written back on export (after
  `0.6.8`; covered by `TransferTests`, device round-trip validation pending).
  Also after `0.6.8`: import rules aligned with Android per GFlyer-Suite
  `docs/DRIFT.md` D4 and D12-D15 (skip bad items one at a time, strict
  boolean/number types, code-point name truncation, missing shared settings
  reset to defaults, auto-stop rounds to the nearest option with ties going
  up); covered by `TransferTests` and `SharedContractTests`
- Coordinate library (座標圖鑑) downloaded from the GFlyer-updates Pages JSON
  with favorites, visit reminders, and anonymous stale-data reports
  (implemented in `0.3.0 (5)`; unlike Android there is no bundled seed, the
  first load requires network; validation pending). For `0.6.9`: strict JSON
  types (`coordinate-library/type-strictness.*`), and the stale-data report
  follows Android (`docs/features/coordinate-stale-report.md`: postcards only,
  Android's reasons, request body and single failure message). Also for
  `0.6.9`: teleport history and 「隱藏已前往」 per
  `docs/features/library-teleport-history.md`. `LibraryTeleportHistory` holds
  the pure logic (Android's storage shape, lenient decoding, en_US_POSIX /
  Gregorian time text, the listing with counts taken before hiding);
  `CoordinateMarkStore` keeps it under the new keys
  `gflyer.coordinate-teleports.v1` and `gflyer.coordinate-hide-teleported.v1`
  and leaves the `gflyer.coordinate-marks.v1` snapshot unchanged; only an
  accepted 「傳送」 with a valid coordinate records; the hide does not apply on
  「⏲ 提醒中」. `SharedContractTests` copies
  `coordinate-library/teleport-history.json`; `CoordinateLibraryTests` covers
  0.6.8 data, a corrupt history and the controller listing. Device validation
  pending. Not released yet (2026-10-08): once the library has been opened in
  this launch, becoming active re-downloads it in the background when the last
  successful check is at least 24 hours old (`CLOCK_MONOTONIC`, includes
  sleep), silently, per `docs/features/coordinate-library-refresh.md`; the
  online JSON itself is regenerated every day by GFlyer-updates.
  `SharedContractTests` copies `coordinate-library/refresh-interval.json`;
  `CoordinateLibraryTests` stubs the download to check the 24-hour rule
- Message-board length limits counted in Unicode code points with Android's
  local messages (`0.6.9`, `docs/features/message-board-limits.md`; the Worker
  with the same limits was deployed on 2026-10-01; covered by
  `SharedContractTests` and `MessageBoardTests`)
- Interrupted-session resume: periodic active-session snapshots with a
  10-minute expiry and a relaunch resume prompt (implemented in `0.3.0 (5)`;
  validation pending)
- Cooldown timer
- Route polyline editing and waypoint reorder

Exit criterion: behavior matches the existing Android model tests where the platform does not impose a different constraint.

### M3: Computer-free maintenance

Status: partly implemented. Installs and updates go through the SideStore
source in `GFlyer-updates` (the owner updated the target iPhone to `0.6.9` this
way on 2026-10-01), and the app has the in-app update check, the LocalDevVPN
hand-off with its state and manual switch, the in-app tunnel test, and the
force-clear path after a relaunch. There is no separate pairing-file health
check (only import and removal), and neither the exit check below nor an
iOS-version compatibility record has been recorded.

- Sideload/refresh workflow using SideStore or another personal method
- Pairing-file health check with a clear replacement flow
- LocalDevVPN connection checklist
- In-app tunnel test that distinguishes a loaded native backend from a verified CoreDevice connection and preserves the native `idevice` error code/message
- Recovery after app termination, device reboot, and VPN reconnect
- iOS-version compatibility record

Exit criterion: the owner can reboot the iPhone, reconnect LocalDevVPN, reopen GFlyer, and start a simulation without connecting a computer.

### M4: Background evaluation

Status: legitimate background-location implementation, retained-session recovery,
and macOS/Xcode compilation complete; distributed through SideStore and
device-tested by the owner up to `0.6.9` (reported passing on 2026-10-01, not
itemized), but the 30-minute background endurance run and the cellular
Stop/Clear restart are still not recorded.

- Request **While Using the App** location permission before route or exploration playback.
- Use `UIBackgroundModes=location`, continuous Core Location updates, and iOS 17 `CLBackgroundActivitySession` only while movement is active.
- Keep the system background-location indicator visible and release the session on Stop, completion, or failure.
- Rebuild the CoreDevice session once after a transient `BrokenPipe`, `Channel closed`, connection-reset, or not-connected failure.
- Stop clears the set point and keeps the session; the full-clear action tears
  the session down and verifies the reported fix. Device finding: iOS keeps
  serving the cached simulated fix until a new real fix arrives, even after the
  session is torn down, so no path may claim real GPS is restored without
  verifying.
- Measure foreground-to-background survival, battery use, and recovery on the target iOS version.
- Document that force quit, resource termination, LocalDevVPN loss, and future iOS changes can still end playback.

Exit criterion: a 30-minute route continues while another App is in the foreground, returns without a transport error, and Stop restores real GPS and ends the background indicator.

## Test matrix

| Scenario | Expected result |
|---|---|
| No pairing file | Start is blocked with an import instruction |
| Invalid/expired pairing file | Existing file remains private and user is told to replace it |
| LocalDevVPN off | Tunnel-stage error; no false active state |
| LocalDevVPN off, Start pressed, LocalDevVPN installed | GFlyer switches to LocalDevVPN, which connects and returns within about a second; simulation then starts without a second tap |
| LocalDevVPN does not return by itself | After the user taps Connect and switches back manually, the pending Start continues; if the VPN is still off after ~10 s, an error names the 「連線」 button |
| Full clear with "also switch off LocalDevVPN" | VPN is switched off only after the clear succeeded; a failed clear keeps the VPN for a retry |
| Manual VPN off while simulating | Blocked with a "press Stop first" message |
| Static teleport | Apple Maps reports the selected coordinate |
| Route update every 250 ms | Active connection is reused |
| Current-location button, simulation inactive | Permission is requested if needed and the map moves to the iPhone's reported location without adding a route point |
| Route moved to background | The system location indicator remains visible and route updates continue |
| Stale channel after foreground return | `BrokenPipe`/`Channel closed` causes one clean reconnect before an error is shown |
| Pause | Coordinate stops changing without clearing simulation |
| Stop | Route task ends, the set point is cleared, the session is kept for the next Start, and an in-flight setLocation cannot land after the clear |
| Airplane mode to cellular, then Clear and Start | The retained session accepts a new coordinate without another airplane-mode cycle |
| Airplane mode to cellular, then route Stop and Start | The retained session starts the next route without opening a replacement socket |
| Transport failure on cellular | Error tells cellular users to rebuild in airplane mode |
| Transport failure on Wi-Fi/hotspot | Error says airplane mode is unnecessary and asks the user to reconnect LocalDevVPN |
| App killed during simulation | Recovery path can clear stale simulation after relaunch |
| Device reboot | Pairing file remains, VPN can reconnect, simulation restarts |
| iOS update | Pairing/tunnel failure is identified without deleting user data |
| No Internet | Existing coordinates work through the local VPN path; map/search availability is reported separately |
| Android creates coordinate, route, announcement and reply | iOS decodes every payload, preserves fractional ISO-8601 dates, and displays matching content |
| iOS shares a coordinate or route | Android can refresh and use the new item through the same Worker/D1 backend |
| Teleport crosses the estimated date line | A confirmation dialog appears before the location is sent; cancel keeps the current location |
| Multi-point route with teleport travel mode | Each point is jumped to, dwell/arrival actions run, and manual advance waits for the user |
| Auto-stop timer elapses | Simulation clears with the auto-stop message; the session is kept like a normal Stop |
| Full clear from Settings | Session torn down, then the app requests a fresh fix and reports real / still-simulated (with recovery guidance) / unavailable |
| Full clear after simulating far away | The location is first set to the last known real position on the same connection, then cleared; Google Maps shows the real position again without airplane mode |
| Multi-point mode, first tap | The tapped point is route point 1; the previous selection is not added; removing points can empty the route |
| Tap the map, then immediately drag vertically | The map pans instead of zooming; pinch and double-tap zoom still work |
| GPX file with tracks, routes, and loose waypoints | Tracks/routes with two or more points import as saved routes with unique names |
| Android `gflyer-backup.json` imported on iOS | Folders, favorites, history, routes, and presets restore with folder links preserved |
| Android backup restored on iOS, exported again, then restored on Android | Android-only settings (floating status bar, map provider, loop transition, manual step count) come back unchanged |
| Backup whose `autoStopMinutes` is 15 (hand-edited) restored | Auto-stop shows 30 minutes, not Off |
| Backup without a `settings` object restored | Cross-date warning is on and auto-stop is Off, whatever the device had before |
| App killed during route playback | Relaunch within 10 minutes offers to resume from the interrupted position |
| Message board visible during refresh | Visible foreign posts/replies remain read; after leaving, later foreign activity increments the badge |
| Session revoked by administrator | The next API request clears the local Keychain session and returns to the join screen |
| Save shared route with a duplicate name | iOS adds the author and a numeric suffix without replacing an existing local route |
| Favorites and saved routes exist, app opened online | Country · city labels appear one by one without opening a list; an open list updates in place |
| Same, in airplane mode | No label, no error; reopening the app online fills them in; deleting and re-adding a favorite sends nothing |

## Data and security rules

- Store the pairing file only in Application Support with complete file protection and owner-only permissions.
- Never log pairing-file contents, host identifiers, private keys, or certificates.
- Never upload or synchronize the pairing file to a backend.
- Store the message-board bearer token in iOS Keychain, never logs or
  `UserDefaults`.
- Keep the public HTTPS message-board API independent from LocalDevVPN and the
  CoreDevice transport; never attach Pairing File or signing material to board
  requests.
- Send only favorite coordinates and the first point of each saved route to
  OpenStreetMap Nominatim for the country · city labels, one request at a time
  with at least 1.1 s between requests and the `GFlyer/<version> (iOS)`
  User-Agent; never send history. Keep the results only in
  `gflyer.region-labels.v1`, never in the backup file, and keep README's
  privacy sentence (GFlyer-Suite `docs/features/region-labels.md` §3.9) true.
- Do not include anti-detection or third-party client modification features.
- Always expose an explicit Stop action that clears device simulation.

## When a computer is still required

Normal use is designed to be computer-free after setup, but a computer may still be required when:

- the personal signing profile expires and the chosen sideload method cannot refresh on-device;
- an iOS update invalidates the pairing file;
- a new iOS protocol requires rebuilding the `idevice` library or app;
- Developer Mode, the app, or LocalDevVPN must be installed again.

This limitation must remain visible in project documentation and should not be marketed as permanent zero-computer operation.
