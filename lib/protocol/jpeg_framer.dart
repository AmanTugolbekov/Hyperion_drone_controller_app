import 'dart:typed_data';

/// Reassembles JPEG frames out of a UDP stream.
///
/// A 640×480 frame does not fit in one datagram, so drones split it across
/// several — and different clones prepend their own little headers, drop
/// packets, or restart a frame midway. Rather than trust any particular
/// layout, this scans the buffer for the JPEG markers themselves:
/// `FF D8` opens an image and `FF D9` closes it.
class JpegFramer {
  JpegFramer({this.maxBufferBytes = 512 * 1024});

  /// Safety valve: if an end marker never arrives (a dropped tail packet),
  /// the buffer is discarded instead of growing without bound.
  final int maxBufferBytes;

  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Feeds one datagram in and returns any complete frames it produced.
  List<Uint8List> add(List<int> datagram) {
    _buffer.add(datagram);
    if (_buffer.length > maxBufferBytes) {
      _buffer.clear();
      return const [];
    }

    var bytes = _buffer.takeBytes();
    final frames = <Uint8List>[];

    while (true) {
      final start = _indexOfMarker(bytes, 0xD8, 0);
      if (start < 0) {
        // No image has begun yet. Keep only the last byte, which may be the
        // leading FF of a marker split across two datagrams.
        bytes = bytes.isEmpty
            ? bytes
            : Uint8List.sublistView(bytes, bytes.length - 1);
        break;
      }

      final end = _indexOfMarker(bytes, 0xD9, start + 2);
      if (end < 0) {
        // Frame still arriving: keep everything from its start marker.
        bytes = Uint8List.sublistView(bytes, start);
        break;
      }

      frames.add(Uint8List.sublistView(bytes, start, end + 2));
      bytes = Uint8List.sublistView(bytes, end + 2);
    }

    _buffer
      ..clear()
      ..add(bytes);
    return frames;
  }

  void reset() => _buffer.clear();

  /// Finds `FF <code>` at or after [from].
  static int _indexOfMarker(Uint8List bytes, int code, int from) {
    for (var i = from; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == code) return i;
    }
    return -1;
  }
}
