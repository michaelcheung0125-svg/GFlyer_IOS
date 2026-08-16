# GFlyer iOS personal sideload prototype

This is a separate SwiftUI prototype for personal sideloading. It does not modify the Android project.

## Current scope

- Branded MapKit home screen with place/coordinate search and map tool controls
- Current-device-location button with explicit Core Location permission handling
- Static teleport plus single-point, multi-point, and spiral exploration modes
- Multi-point route playback with a nonlinear 1.8-900 km/h speed scale
- Visible iOS 17 background location activity for route and exploration playback
- Pause, resume, stop, looping, and return behavior
- In-app foreground joystick control and reusable speed presets
- Local favorites, history, favorite folders, named routes, and route-draft recovery
- Pairing-file import and protected local storage
- Preview backend that builds without native dependencies
- Optional `idevice` backend for device-wide GPS simulation
- Retained CoreDevice sessions across Stop/Clear so a cellular interface switch
  does not require a replacement socket for every new simulation

The prototype deliberately excludes anti-detection, modified third-party clients, and App Store distribution.

The current feature UI, current-location flow, background activity, and native
archive pass the repository's macOS/Xcode CI. Target-iPhone regression and
background endurance testing remain separate gates; Windows checks do not
replace them.

## End-user guide

The complete Traditional Chinese installation and usage guide is available in
[Markdown](docs/USER_GUIDE_ZH_HK.md) and as a self-contained
[HTML document](docs/USER_GUIDE_ZH_HK.html). It covers Windows/Sideloadly
installation, device-specific remote pairing, LocalDevVPN, first-use DDI setup,
daily operation, seven-day signing refreshes, and multi-user distribution.

Public guide: https://michaelcheung0125-svg.github.io/GFlyer-updates/USER_GUIDE_ZH_HK.html

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
5. Install and connect LocalDevVPN. Keep its default device address `10.7.0.1` unless your setup uses another address. In GFlyer's device settings, use **Test LocalDevVPN tunnel** before starting simulation; the current raw RPPairing path connects on port `49152`.
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
- Stop/Clear retains a healthy CoreDevice session, but iOS process termination,
  LocalDevVPN reconnection, a transport failure, target-IP changes, and
  pairing-file replacement still require a new session. Cellular users may
  need airplane mode for that reconnection; Wi-Fi/hotspot users do not.
- MapKit search and map tiles require network access. The pinned DDI is downloaded once; GPS simulation then uses the local VPN path.
- Keep the pairing file private. It contains credentials that identify a trusted host for this iPhone.
- Third-party apps may reject simulated location or enforce their own terms.

## License boundary

- New GFlyer iOS source in this directory is original project code.
- `idevice` is MIT licensed and must retain its copyright/license notice when distributed.
- No StikDebug AGPL application source or binary is copied into this project.
