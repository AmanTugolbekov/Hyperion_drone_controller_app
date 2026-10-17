# Work plan

As of 2026-10-17: **control (UDP 7099) and the camera (RTSP 7070) are verified
on a real E88 and working.**

Split by whether the drone has to be in the room.

---

## A. Verify at the first opportunity (drone needed)

Code that is written but has never run against hardware.

| # | What | How to check | Where it lives |
|---|---|---|---|
| A1 | **Stills** | Press Photo, look in the "Ala-Too Drone" album | `RtspViewState.screenshot()` → `MediaService.savePhotoBytes`. The shutter asks the player, not the protocol |
| A2 | **Rotation direction** | Point the drone at something with an obvious top | If upside down, change `quarterTurns: 1` to `3` in [rtsp_view.dart](lib/widgets/rtsp_view.dart) |
| A3 | **Take-off / landing** | Take off, then land | Command bits differ per E88 variant, see `E88Protocol.takeOff()` |
| A4 | **Flip, headless, calibration** | One button at a time | Same place: bits `0x08` / `0x10` / `0x80` |
| A5 | **Emergency stop** | **On the ground, or at 20–30 cm only** — the motors cut instantly and the drone drops | — |
| A6 | **Trim** | If the drone drifts, trim it out and confirm the drift stops | — |
| A7 | **Rate switch** | 30 / 60 / 100 % | — |
| A8 | **Tilt control** | Enable it and tilt the phone | — |
| A9 | **Wi-Fi pinning** | Diagnostics → look for `Sockets pinned to Wi-Fi` | If it says `Could not pin`, MIUI is blocking `bindProcessToNetwork` and mobile data must be turned off by hand |

---

## B. Known defects (drone needed to confirm the fix)

### B1. Video recording is broken over RTSP — priority 1

[MjpegAviWriter](lib/services/mjpeg_avi_writer.dart) assembles an AVI from a
stream of complete JPEG frames. Over RTSP the frames live inside FFmpeg and
never reach Dart, so there is nothing to write.

**Fix:** libmpv records the stream itself through the `stream-record` property.
It writes exactly what arrives, with no re-encoding:

```dart
// in RtspView
native.setProperty('stream-record', '/path/to/clip.mkv');  // start
native.setProperty('stream-record', '');                   // stop
```

This also removes an older problem: recording accumulated every frame in RAM
and only wrote the file on stop.

### B2. The diagnostics port scanner lies — priority 2

[DroneScanner](lib/protocol/drone_scanner.dart) calls a port closed when the
connection times out. This drone **silently drops SYN packets** to closed
ports, so a timeout means "no answer", not "closed". The scanner reported 7070
as closed while it was serving RTSP.

**Fix:** distinguish three outcomes — answered, refused (RST), and no response
— and stop calling the third one closed. Raise the timeout to 2–3 s.

### B3. Telemetry is empty — priority 3

Battery and altitude are not shown: the reply format has not been decoded.
`E88Protocol._onSocketEvent` fills telemetry with a placeholder.

**Fix:** the drone answers heartbeats with 11-byte packets. The parser is in
`SocketClient` inside the RC UFO app — extract it the same way the protocol was
extracted (see section D). A real charge indicator matters in flight.

---

## C. New features (drone needed)

| # | What | Based on |
|---|---|---|
| C1 | **Browse the drone's SD card** | RC UFO revealed FTP (`ftp`/`ftp`) and `http://192.168.1.1/PHOTO/O/`, thumbnails at `/PHOTO/T/`. Enough to list and download what was shot |
| C2 | **Camera switching** | Commands `06 01` / `06 02`, if the drone has a downward camera |
| C3 | **Video auto-reconnect** | Call `RtspViewState.restart()` when the stream drops mid-flight, instead of showing black |
| C4 | **Latency tuning** | Currently `profile=low-latency`, `rtsp-transport=udp`. Measure the real lag and tune |
| C5 | **Flight telemetry logging** | Altitude, charge and commands to a file — useful for coursework |

---

## D. Can be done without the drone

| # | What |
|---|---|
| D1 | **Decode telemetry from the APK** — `apkanalyzer dex code --class com.cooingdv.rcufo.socket.SocketClient`, find where replies are parsed. Prepares B3 |
| D2 | **iOS `Info.plist`** — no permission strings for location or the photo library; the app will crash on the first request and the App Store will reject it |
| D3 | **Release signing** — release builds currently use the debug key and cannot be distributed |
| D4 | **Icon and app name** — still the stock Flutter icon |
| D5 | **Remove dead code** — `tcp_mjpeg_receiver.dart` and `video_receiver.dart` are no longer used by the E88 protocol |
| D6 | **Tests** — for `JpegFramer`, `MjpegAviWriter`, and protocol frame building. There are none at all |

---

## Suggested order

1. **D1** (no drone) — get the telemetry format ready so it can be tested the
   moment a drone is available
2. **B1** — video recording, the most visible gap
3. **A1–A9** — one session, the whole checklist
4. **B3** — telemetry, if D1 produced the format
5. **B2**, then **C1**

D2–D4 are prerequisites before handing the app to anyone else.
