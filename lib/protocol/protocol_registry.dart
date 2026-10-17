import 'drone_protocol.dart';
import 'e88_protocol.dart';
import 'generic_wifi_uav.dart';
import 'mock_protocol.dart';
import 'tello_protocol.dart';

/// Every dialect the app can speak. Adding a drone family means adding one
/// class and one line here.
class ProtocolRegistry {
  static const autoId = 'auto';

  /// Order matters: auto-detection takes the first protocol whose SSID hints
  /// match, and E88 is both the most specific and the most common here.
  static List<DroneProtocol> build() => [
        E88Protocol(),
        GenericWifiUavProtocol(),
        TelloProtocol(),
        MockProtocol(),
      ];

  /// Picks a protocol from the Wi-Fi network name. Falls back to the generic
  /// dialect, which covers most RC UFO-compatible drones.
  static DroneProtocol pickForSsid(String? ssid, List<DroneProtocol> all) {
    final name = (ssid ?? '').toLowerCase().replaceAll('"', '');
    if (name.isNotEmpty) {
      for (final p in all) {
        if (p.ssidHints.any(name.contains)) return p;
      }
    }
    // E88-family boards are by far the most common drones in this price
    // bracket, so they are the better blind guess than the generic dialect.
    return all.firstWhere((p) => p.id == 'e88');
  }

  static DroneProtocol byId(String id, List<DroneProtocol> all) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}
