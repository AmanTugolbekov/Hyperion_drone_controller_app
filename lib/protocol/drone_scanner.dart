import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Probes a drone and reports what actually answers.
///
/// Every board in this price bracket claims to be an "E88", so rather than
/// trusting the label, this knocks on each port the family is known to use and
/// reports back. The result is what tells us which protocol to speak.
class DroneScanner {
  DroneScanner({required this.onLog});

  final void Function(String message) onLog;

  /// TCP ports worth checking, with what each one implies.
  static const Map<int, String> tcpPorts = {
    8888: 'MJPEG camera (common E58/E88)',
    7070: 'RTSP camera (E88 Pro / GL)',
    80: 'HTTP — SD card browser',
    21: 'FTP — SD card',
    554: 'RTSP (standard port)',
  };

  /// UDP probes: port to the payload that should provoke an answer.
  static final Map<int, Uint8List> udpProbes = {
    7099: Uint8List.fromList([0x01, 0x01]), // heartbeat
    8080: Uint8List.fromList([0x42, 0x76]), // Wi-Fi mode switch
    8090: Uint8List.fromList(
        [0xAA, 0x80, 0x80, 0x00, 0x80, 0x00, 0x80, 0x55]), // keepalive
    8800: Uint8List.fromList([0xEF, 0x00, 0x04, 0x00]), // E58 video start
  };

  /// Runs the whole sweep and returns a human-readable report, which is also
  /// streamed line by line through [onLog].
  Future<List<String>> scan(String host) async {
    final report = <String>[];
    void record(String line) {
      report.add(line);
      onLog(line);
    }

    record('--- Scanning $host ---');

    final InternetAddress address;
    try {
      address = InternetAddress(host);
    } on ArgumentError {
      record('Invalid address: $host');
      return report;
    }

    final reachable = await _ping(address);
    record(reachable
        ? 'Host reachable'
        : 'Host did not answer TCP — it may still speak UDP only');

    for (final entry in tcpPorts.entries) {
      final open = await _tcpOpen(address, entry.key);
      record('TCP ${entry.key}: ${open ? "OPEN" : "closed"}  (${entry.value})');
    }

    for (final entry in udpProbes.entries) {
      final answered = await _udpAnswers(address, entry.key, entry.value);
      record('UDP ${entry.key}: ${answered ? "ANSWERED" : "silent"}');
    }

    record('--- Scan finished ---');
    record('Send this report back to identify the protocol.');
    return report;
  }

  Future<bool> _ping(InternetAddress address) async {
    // Any TCP port answering at all — even with a refusal — proves the host is
    // up, which a silent UDP port never can.
    for (final port in [80, 8888, 7070]) {
      try {
        final socket = await Socket.connect(address, port,
            timeout: const Duration(milliseconds: 700));
        socket.destroy();
        return true;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 111 ||
            (e.message.toLowerCase().contains('refused'))) {
          return true; // refused means something is listening on that host
        }
      }
    }
    return false;
  }

  Future<bool> _tcpOpen(InternetAddress address, int port) async {
    try {
      final socket = await Socket.connect(address, port,
          timeout: const Duration(milliseconds: 900));
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<bool> _udpAnswers(
    InternetAddress address,
    int port,
    Uint8List payload,
  ) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException {
      return false;
    }

    var answered = false;
    socket.listen((event) {
      if (event == RawSocketEvent.read && socket?.receive() != null) {
        answered = true;
      }
    });

    for (var i = 0; i < 6 && !answered; i++) {
      try {
        socket.send(payload, address, port);
      } on SocketException {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    socket.close();
    return answered;
  }
}
