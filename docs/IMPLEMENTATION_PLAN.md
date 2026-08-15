# GFlyer iOS implementation plan

## Objective

Build a personal, sideloaded iOS version of GFlyer that can control device-wide simulated GPS without a computer connected during normal use.

The accepted operating model is:

1. A computer may be used for the initial build, install, signing, Developer Mode setup, and pairing-file generation.
2. The iPhone imports and stores its pairing file locally.
3. LocalDevVPN exposes the same iPhone through a local loopback path.
4. GFlyer verifies and mounts a pinned Personalized Developer Disk Image when required.
5. GFlyer connects to Apple developer services through `idevice` and sends location updates.
6. Normal teleport and foreground route playback do not require a connected computer.

## Hard feasibility gate

Do not expand the full feature set until all of these pass on the owner's target iPhone and iOS version:

- The `GFlyerIOS-Idevice` scheme installs through personal signing.
- A current pairing file can establish the CoreDevice/RPPairing tunnel through LocalDevVPN.
- The pinned DDI downloads, passes SHA-256 verification, and mounts when developer services are unavailable.
- Sending one coordinate changes the location shown by Apple Maps.
- Sending a second coordinate reuses the active connection.
- Stop calls `location_simulation_clear()` and Apple Maps returns to real location.
- Disconnecting the computer does not affect the above workflow.

If this gate fails, capture the iOS version, device model, pairing method, LocalDevVPN version, and backend error stage before changing UI code.

## Architecture

```text
SwiftUI / MapKit
  -> SimulationController
     -> GeoMath and route playback
     -> LocationSimulationBackend
        -> PreviewLocationSimulationBackend
        -> IdeviceLocationSimulationBackend
           -> pairing file
           -> LocalDevVPN 10.7.0.1:49152 (raw RPPairing)
           -> CoreDevice/RPPairing
           -> Personalized DDI mount when required
           -> RemoteXPC
           -> location_simulation
```

The platform boundary must remain narrow. Route planning, GPX, favorites, history, speed, cooldown, and joystick behavior must not call `idevice` directly.

## Milestones

### M0: Device-location spike

Status: implementation and macOS CI passed on Xcode 16.4; requires personal
signing and target iPhone verification.

- Run preview scheme unit tests on a GitHub Actions macOS runner.
- Build and link the pinned `idevice` library in an unsigned device archive.
- Import a pairing file.
- Set and clear one coordinate.
- Translate backend failures into distinct stages: pairing, tunnel, RemoteXPC, service, set, and clear.

Exit criterion: the hard feasibility gate passes.

The CI artifact is deliberately unsigned. The green workflow is a compilation
gate only and does not satisfy the personal-signing or device-location exit
criteria. Record target-device evidence in `docs/DEVICE_FEASIBILITY_CHECKLIST.md`.

### M1: Foreground MVP

Status: feature implementation complete; macOS/Xcode and target-iPhone regression pending.

- Branded map home, search, map tools, and collapsible controls
- Map selection and static teleport
- Single-point and multi-point straight-line routes
- Nonlinear 1.8-900 km/h speed scale and reusable presets
- Pause, resume, stop
- Loop route with walk-back or instant return
- Foreground joystick and spiral exploration
- Visible backend and connection state

Exit criterion: a 30-minute foreground route completes without losing the tunnel or leaving simulated GPS active after Stop.

### M2: GFlyer feature parity

- Place and coordinate search (implemented; validation pending)
- Favorites, favorite folders, and local history (implemented; validation pending)
- Named routes and route-draft recovery after relaunch (implemented; validation pending)
- GPX import and export
- Joystick movement (implemented for foreground use; validation pending)
- Spiral exploration (implemented; validation pending)
- Cooldown timer and cross-date warning
- Route polyline editing and waypoint reorder

Exit criterion: behavior matches the existing Android model tests where the platform does not impose a different constraint.

### M3: Computer-free maintenance

- Sideload/refresh workflow using SideStore or another personal method
- Pairing-file health check with a clear replacement flow
- LocalDevVPN connection checklist
- In-app tunnel test that distinguishes a loaded native backend from a verified CoreDevice connection and preserves the native `idevice` error code/message
- Recovery after app termination, device reboot, and VPN reconnect
- iOS-version compatibility record

Exit criterion: the owner can reboot the iPhone, reconnect LocalDevVPN, reopen GFlyer, and start a simulation without connecting a computer.

### M4: Background evaluation

Background route playback is explicitly deferred. iOS may suspend the app, and background modes must not be misrepresented merely to keep a timer alive.

- Measure foreground-to-background survival on the target version.
- Confirm whether location simulation remains active when GFlyer is suspended.
- Prefer a documented foreground-only limit if reliable background operation cannot be achieved legitimately.

Exit criterion: either a repeatable background design exists or the UI clearly enforces foreground-only playback.

## Test matrix

| Scenario | Expected result |
|---|---|
| No pairing file | Start is blocked with an import instruction |
| Invalid/expired pairing file | Existing file remains private and user is told to replace it |
| LocalDevVPN off | Tunnel-stage error; no false active state |
| Static teleport | Apple Maps reports the selected coordinate |
| Route update every 250 ms | Active connection is reused |
| Pause | Coordinate stops changing without clearing simulation |
| Stop | Route task ends and real location is restored |
| App killed during simulation | Recovery path can clear stale simulation after relaunch |
| Device reboot | Pairing file remains, VPN can reconnect, simulation restarts |
| iOS update | Pairing/tunnel failure is identified without deleting user data |
| No Internet | Existing coordinates work through the local VPN path; map/search availability is reported separately |

## Data and security rules

- Store the pairing file only in Application Support with complete file protection and owner-only permissions.
- Never log pairing-file contents, host identifiers, private keys, or certificates.
- Never upload or synchronize the pairing file to a backend.
- Do not include anti-detection or third-party client modification features.
- Always expose an explicit Stop action that clears device simulation.

## When a computer is still required

Normal use is designed to be computer-free after setup, but a computer may still be required when:

- the personal signing profile expires and the chosen sideload method cannot refresh on-device;
- an iOS update invalidates the pairing file;
- a new iOS protocol requires rebuilding the `idevice` library or app;
- Developer Mode, the app, or LocalDevVPN must be installed again.

This limitation must remain visible in project documentation and should not be marketed as permanent zero-computer operation.
