# Work plan

As of 2026-10-22: **control (UDP 7099), the camera (RTSP 7070), stills and
video recording are all verified on a real E88.**

Split by whether the drone has to be in the room.

---

## A. Verify at the first opportunity (drone needed)

Code that is written but has never run against hardware.

| # | What | How to check | Where it lives |
|---|---|---|---|
| ~~A1~~ | ~~**Stills**~~ | **Done** — saves to the album | — |
| ~~A2~~ | ~~**Rotation direction**~~ | **Done** — 90° is the right way up | — |
| A3 | **Take-off / landing** | Take off, then land | Command bits differ per E88 variant, see `E88Protocol.takeOff()` |
| A4 | **Flip, headless, calibration** | One button at a time | Same place: bits `0x08` / `0x10` / `0x80` |
| A5 | **Emergency stop** | **On the ground, or at 20–30 cm only** — the motors cut instantly and the drone drops | — |
| A6 | **Trim** | If the drone drifts, trim it out and confirm the drift stops | — |
| A7 | **Rate switch** | 30 / 60 / 100 % | — |
| A8 | **Tilt control** | Enable it and tilt the phone | — |
| A9 | **Wi-Fi pinning** | Diagnostics → look for `Sockets pinned to Wi-Fi` | If it says `Could not pin`, MIUI is blocking `bindProcessToNetwork` and mobile data must be turned off by hand |

---

## B. Known defects (drone needed to confirm the fix)

### ~~B1. Video recording~~ — fixed and verified

Recording now pulls a JPEG frame from the player ten times a second and writes
MJPEG/AVI. Verified on hardware: 231 frames, 23 s, valid index, real 240×320
frames.

Handing recording to libmpv was tried first and does not work — that build
carries **no muxers at all** (`recorder: Output format not found`), whatever
the container. Noted in the protocol spec so nobody tries it again.

**One open question:** Android's media scanner could not probe the clip —
width, height and duration are empty in the media store, and it filed the video
under `Pictures/` rather than `Movies/`. The file itself is valid. If the stock
gallery refuses to play it, the fix is transcoding to H.264 through Android's
`MediaCodec`, which is a sizeable job.

### B2. The diagnostics port scanner lies — priority 2

[DroneScanner](lib/protocol/drone_scanner.dart) calls a port closed when the
connection times out. This drone **silently drops SYN packets** to closed
ports, so a timeout means "no answer", not "closed". The scanner reported 7070
as closed while it was serving RTSP.

**Fix:** distinguish three outcomes — answered, refused (RST), and no response
— and stop calling the third one closed. Raise the timeout to 2–3 s.

### ~~B3. Telemetry~~ — closed, not possible on this hardware

The drone replies, but every reply is the same 5-byte packet
`54 00 00 00 00`: byte 0 is the device id, the rest are always zero, with the
battery around half charge. The stock app reads battery from offsets 5 and 8
and only does so for packets of 15 bytes or more, so it cannot show a charge
level on this board either.

**There is no data to decode.** The app should keep showing no battery
indicator rather than inventing one. Hyperion's own firmware should send real
battery and altitude — a pilot who cannot see the charge discovers it was low
by watching the aircraft drop.

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
| D2 | **iOS `Info.plist`** — no permission strings for location or the photo library; the app will crash on the first request and the App Store will reject it |
| D3 | **Release signing** — release builds currently use the debug key and cannot be distributed |
| D4 | **Icon and app name** — still the stock Flutter icon |
| D5 | **Remove dead code** — `tcp_mjpeg_receiver.dart` and `video_receiver.dart` are no longer used by the E88 protocol |
| D6 | **Tests** — for `JpegFramer`, `MjpegAviWriter`, and protocol frame building. There are none at all |

---

## Suggested order

1. **A3–A9** — the flight checklist, as soon as there is space to fly
2. Check whether the recorded clip plays in the gallery; that decides whether
   H.264 transcoding has to be added
3. **D2–D4** — prerequisites before handing the app to anyone else
4. **B2**, **D5**, **D6** — cleanup, any time
5. **C1** — browsing the drone's SD card, the largest remaining feature
