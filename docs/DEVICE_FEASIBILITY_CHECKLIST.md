# Device feasibility checklist

Use this record for the hard device-location gate. Do not add pairing files,
signing material, device identifiers, private keys, provisioning profiles, or
downloaded DDI files to this document or the repository.

## Environment

| Item | Value |
|---|---|
| Test date | |
| iPhone model | |
| iOS version | |
| Xcode version | |
| GFlyer commit | |
| `idevice` revision | `37ee77cf713f483551f3cf33ea8b2087a40058ca` |
| LocalDevVPN version | |
| LocalDevVPN target IP | `10.7.0.1` |
| Pairing-file generation method | |
| Computer disconnected during final pass | Yes / No |

## Gate results

| Step | Result | Evidence or error |
|---|---|---|
| Personal signing and IPA installation | Pass / Fail | |
| Pairing file imports successfully | Pass / Fail | |
| LocalDevVPN tunnel connects | Pass / Fail | |
| Personalized DDI downloads and verifies | Pass / Fail | |
| Personalized DDI mounts when required | Pass / Fail | |
| First coordinate appears in Apple Maps | Pass / Fail | |
| Second coordinate reuses the active connection | Pass / Fail | |
| Stop clears simulation and restores real GPS | Pass / Fail | |
| Full sequence works without a connected computer | Pass / Fail | |
| Current-location button returns the real location while simulation is off | Pass / Fail | |

## Failure classification

When a step fails, record the first relevant stage and the exact user-visible
error. Do not paste sensitive log contents.

- `signing`
- `pairing`
- `tunnel`
- `DDI download`
- `DDI verification`
- `DDI mount`
- `RemoteXPC`
- `location set`
- `location clear`

## Extended route run

Complete this only after every hard gate item passes.

| Scenario | Result | Notes |
|---|---|---|
| 30-minute foreground route | Pass / Fail | |
| Route continues for 1 minute with another App in foreground | Pass / Fail | |
| Route continues for 30 minutes with another App in foreground | Pass / Fail | |
| Returning to GFlyer does not show `BrokenPipe` / `Channel closed` | Pass / Fail | |
| Stop ends the background-location indicator | Pass / Fail | |
| Pause and resume | Pass / Fail | |
| Loop with walk-back | Pass / Fail | |
| Loop with instant return | Pass / Fail | |
| Force-quit recovery clear | Pass / Fail | |
