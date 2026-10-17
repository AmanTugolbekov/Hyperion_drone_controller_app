import 'dart:async';

/// One control frame. All axes are normalised to -1.0 .. 1.0 except
/// [throttle], which is 0.0 .. 1.0 for throttle-stick drones and -1..1 when
/// the drone has altitude hold.
class ControlInput {
  final double roll;
  final double pitch;
  final double yaw;
  final double throttle;

  final double rollTrim;
  final double pitchTrim;
  final double yawTrim;

  /// 0 = low, 1 = mid, 2 = high rate.
  final int speedRate;
  final bool headless;

  const ControlInput({
    this.roll = 0,
    this.pitch = 0,
    this.yaw = 0,
    this.throttle = 0,
    this.rollTrim = 0,
    this.pitchTrim = 0,
    this.yawTrim = 0,
    this.speedRate = 1,
    this.headless = false,
  });

  ControlInput copyWith({
    double? roll,
    double? pitch,
    double? yaw,
    double? throttle,
    double? rollTrim,
    double? pitchTrim,
    double? yawTrim,
    int? speedRate,
    bool? headless,
  }) =>
      ControlInput(
        roll: roll ?? this.roll,
        pitch: pitch ?? this.pitch,
        yaw: yaw ?? this.yaw,
        throttle: throttle ?? this.throttle,
        rollTrim: rollTrim ?? this.rollTrim,
        pitchTrim: pitchTrim ?? this.pitchTrim,
        yawTrim: yawTrim ?? this.yawTrim,
        speedRate: speedRate ?? this.speedRate,
        headless: headless ?? this.headless,
      );
}

/// What the drone tells us back. Cheap toy drones report almost nothing, so
/// every field is optional and the UI hides what is null.
class Telemetry {
  final int? batteryPercent;
  final double? heightMeters;
  final bool? flying;
  final int? signalPercent;

  const Telemetry({
    this.batteryPercent,
    this.heightMeters,
    this.flying,
    this.signalPercent,
  });

  Telemetry merge(Telemetry other) => Telemetry(
        batteryPercent: other.batteryPercent ?? batteryPercent,
        heightMeters: other.heightMeters ?? heightMeters,
        flying: other.flying ?? flying,
        signalPercent: other.signalPercent ?? signalPercent,
      );
}

enum LinkState { idle, connecting, connected, failed }

/// Network coordinates of a drone. Defaults differ per protocol but the user
/// can override them on the Diagnostics screen.
class DroneEndpoint {
  final String host;
  final int commandPort;
  final int videoPort;

  const DroneEndpoint({
    required this.host,
    required this.commandPort,
    required this.videoPort,
  });

  DroneEndpoint copyWith({String? host, int? commandPort, int? videoPort}) =>
      DroneEndpoint(
        host: host ?? this.host,
        commandPort: commandPort ?? this.commandPort,
        videoPort: videoPort ?? this.videoPort,
      );

  @override
  String toString() => '$host:$commandPort (video $videoPort)';
}

/// How the drone delivers its camera feed, so the video widget knows what to
/// build without knowing the protocol.
enum VideoTransport {
  /// No camera at all.
  none,

  /// Raw JPEG frames pushed over the control socket or a sibling UDP port.
  udpJpeg,

  /// `multipart/x-mixed-replace` over HTTP.
  mjpegHttp,

  /// An RTSP server on the drone, played through FFmpeg. Frames never reach
  /// Dart, so the player widget owns the stream rather than the protocol.
  rtsp,
}

/// A drone dialect. Implementations own their sockets; the service above only
/// opens, feeds and closes them.
abstract class DroneProtocol {
  /// Stable id persisted in settings.
  String get id;

  /// Human-readable name shown in Settings.
  String get displayName;

  /// Wi-Fi SSID fragments that hint at this protocol, lower-cased.
  List<String> get ssidHints;

  DroneEndpoint get defaultEndpoint;

  VideoTransport get videoTransport;

  /// The stream URL, when [videoTransport] is [VideoTransport.rtsp]. Null
  /// until the drone is connected, since it is built from its address.
  String? get videoUrl => null;

  /// True when the drone holds its own altitude, so the throttle stick means
  /// "climb / descend" and must spring back to centre. False when throttle is
  /// raw motor power, which must stay where the pilot left it.
  bool get throttleIsBidirectional;

  /// Frames per second the drone expects on its control channel.
  int get controlHz;

  Stream<Telemetry> get telemetry;

  /// JPEG frames, when [videoTransport] is [VideoTransport.udpJpeg].
  Stream<List<int>> get videoFrames;

  /// Diagnostic lines surfaced on the Diagnostics screen.
  Stream<String> get log;

  /// Opens sockets and verifies the drone answers. Returns false on timeout.
  Future<bool> connect(DroneEndpoint endpoint);

  Future<void> disconnect();

  /// Called [controlHz] times per second while connected.
  void sendControl(ControlInput input);

  Future<void> takeOff();
  Future<void> land();

  /// Cuts the motors immediately. Must never be queued behind other commands.
  Future<void> emergencyStop();

  Future<void> calibrateGyro();

  /// Does a 360° roll. No-op on drones that cannot flip.
  Future<void> flip();

  /// Asks the drone to start or stop its own camera stream, if it needs asking.
  Future<void> setVideoEnabled(bool enabled);
}
