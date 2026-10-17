# Hyperion — Drone Controller App

A mobile ground station for Wi-Fi quadcopters: live FPV video, dual sticks and
telemetry on a phone. Built as a replacement for the stock **RC UFO** app, in
the colours of Ala-Too International University.

Flutter · Android (iOS scaffolded) · three languages

---

## Where this fits

Part of the [**Hyperion**](https://github.com/AmanTugolbekov/Hyperion) project:
a smart drone that picks up, carries and releases lightweight objects.

| Repository | Contents |
|---|---|
| [Hyperion](https://github.com/AmanTugolbekov/Hyperion) | System overview and the radio protocol specification |
| **This one** | The ground station — the part the pilot holds |
| [Hyperion_drone_firmware](https://github.com/AmanTugolbekov/Hyperion_drone_firmware) | Flight controller and gripper firmware |
| [Hyperion_drone_hardware](https://github.com/AmanTugolbekov/Hyperion_drone_hardware) | Airframe, gripper, electronics |

The app is developed against a commercial E88 quadcopter while the Hyperion
airframe is being built. That is deliberate: a real aircraft drops packets,
stays silent, and streams its camera sideways — a simulator does none of those
things, and an app that only works against a simulator does not work.

## What it does

Cheap Wi-Fi drones ship with apps that function but are unpleasant: crowded
with ads, and silent about what the aircraft is actually doing. This one aims
to be legible — an honest link indicator, a readable log of the exchange with
the drone, and an interface worth showing.

**Flight**

- Two sticks — throttle/yaw and roll/pitch — with a switchable layout for
  Mode 1 and Mode 2 pilots
- Take-off, landing, emergency stop, 360° flip, headless mode
- Per-axis trim and gyro calibration
- Three rates: 30 / 60 / 100 %
- Tilt flying through the phone's accelerometer

The throttle stick behaves differently per aircraft, and the protocol decides
which: where the drone holds its own altitude the stick springs back to centre,
and where throttle is raw motor power it stays where the pilot left it and
starts at the bottom. Otherwise a centred stick would mean half power the
instant the motors arm.

**Camera**

- Full-screen live view
- Stills to the phone's gallery, album "Ala-Too Drone"
- Automatic frame rotation — the drone reports its stream as portrait because
  the camera is mounted sideways

**Telemetry and diagnostics**

- Battery, altitude, link state
- Diagnostics screen: manual address and ports, live exchange log
- A warning when traffic is escaping to mobile data (see below)

**Other**

- Russian, English, Kyrgyz
- Screen stays awake in flight, forced landscape
- Leaving the cockpit lands the drone first, then drops the link

## Supported aircraft

The protocol layer is pluggable — [`lib/protocol/`](lib/protocol/). Adding a
family means one class and one line in the registry.

| Protocol | Transport | Status |
|---|---|---|
| **E88 / E58 / LSRC** | UDP 7099, RTSP video on 7070 | **Verified on hardware** |
| Generic Wi-Fi UAV | UDP 8080/8888 | Untested |
| DJI Tello | UDP 8889 | Untested |
| Simulator | — | For development without a drone |

The protocol is chosen from the drone's Wi-Fi network name, or by hand in
settings.

## How the E88 protocol was found

Community write-ups for this drone family contradict each other — the control
port is given as 7099, 8090 or 8800, and the video as either RTSP or a bespoke
UDP stream. Their authors state plainly that they never verified against
hardware. Two implementations built from those descriptions did not work.

Reading the manufacturer's own app settled it:

```bash
adb shell pm path com.cooingdv.rcufo
adb pull <base.apk>
apkanalyzer dex code --class com.cooingdv.rcufo.socket.Config base.apk
```

The constants were in plain sight:

```
SERVER_IP             = "192.168.1.1"
PREVIEW_ADDRESS       = "rtsp://192.168.1.1:7070/webcam"
SEND_COMMAND_INTERVAL = 40        // 25 Hz
UdpComm.getInstance("192.168.1.1", 7099)
```

Confirmed against live traffic: while the stock app was connected,
`/proc/net/tcp` showed an established session to `192.168.1.1:7070`, with video
arriving over RTP on a pair of UDP ports.

**Result:** control over UDP 7099, one frame every 40 ms; camera over RTSP,
MJPEG, 240×320, decoded with FFmpeg. The full specification lives in
[the umbrella repository](https://github.com/AmanTugolbekov/Hyperion/blob/main/docs/PROTOCOL.md).

## Two things without which nothing works

**Android routes the traffic away.** The drone's access point offers no
internet, so the system treats it as dead and quietly sends every packet over
mobile data — the drone receives nothing, and no error is raised. The app pins
its sockets with `ConnectivityManager.bindProcessToNetwork` through a
[MethodChannel](android/app/src/main/kotlin/kg/edu/alatoo/alatoo_drone/MainActivity.kt).
The network request deliberately omits `NET_CAPABILITY_INTERNET` — with it, the
request would never match.

**Some boards ignore Wi-Fi until switched.** They boot bound to the physical
remote and discard commands until they receive a mode-switch packet.

## Architecture

```
lib/
├── protocol/     drone dialects behind one DroneProtocol interface
├── services/     link state, settings, media, Wi-Fi pinning
├── screens/      splash, connect, cockpit, settings, diagnostics
├── widgets/      joystick, HUD, RTSP player
├── theme/        Ala-Too palette and typography
└── l10n/         three languages
```

The control stream runs continuously at the rate the protocol specifies —
drones in this class stop obeying if it pauses. One-shot commands such as
take-off are repeated across several frames, because UDP packets are lost
constantly.

## Build

Flutter 3.19+ and JDK 17.

```bash
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release
```

Android permissions are already declared. The Wi-Fi network name is only
readable with location permission, which is why the app asks for it on launch.

## Design

Palette taken from [alatoo.edu.kg](https://alatoo.edu.kg): navy `#001F5B`,
navy-2 `#19316A`, crimson `#C70017`, ink `#1F1F1F`, mist `#F7F8FA`. Poppins for
headings, Inter for body text. The cockpit is dark so the video reads clearly;
emergency stop is the only red control on it.

## Not there yet

- **Video recording over RTSP** — the AVI writer expects a stream of JPEG
  frames, which RTSP does not provide. Stills work, recording does not
- **Battery and altitude telemetry on E88** — the reply format is not decoded
- **The diagnostics port scanner is unreliable** — the drone silently drops
  requests to closed ports, making a timeout indistinguishable from a refusal
- **iOS is unconfigured** — no permission strings in `Info.plist`
- **Release builds are signed with the debug key** — not distributable

The full work plan is in [NEXT_STEPS.md](NEXT_STEPS.md).

## Status

Control and camera are verified on a real E88. The other protocols compile but
have never been flown.

Coursework at Ala-Too International University.
