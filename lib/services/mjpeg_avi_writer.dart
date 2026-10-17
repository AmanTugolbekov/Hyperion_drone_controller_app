import 'dart:io';
import 'dart:typed_data';

/// Writes recorded JPEG frames into a Motion-JPEG AVI file.
///
/// The drone hands us a stream of standalone JPEGs, and MJPEG/AVI is the one
/// container that wraps them without re-encoding — so recording costs no CPU
/// and needs no native codec. Android's gallery and every desktop player
/// handle it.
class MjpegAviWriter {
  MjpegAviWriter({required this.width, required this.height, this.fps = 20});

  final int width;
  final int height;
  final int fps;

  final List<Uint8List> _frames = [];

  int get frameCount => _frames.length;

  void addFrame(Uint8List jpeg) => _frames.add(jpeg);

  void clear() => _frames.clear();

  Future<File> writeTo(String path) async {
    final file = File(path);
    await file.writeAsBytes(_build(), flush: true);
    return file;
  }

  Uint8List _build() {
    // Each frame becomes a `00dc` chunk, padded to an even length.
    final chunks = <Uint8List>[];
    final offsets = <int>[];
    final sizes = <int>[];

    var moviSize = 4; // the 'movi' FourCC itself
    for (final frame in _frames) {
      final padded = frame.length + (frame.length.isOdd ? 1 : 0);
      final chunk = Uint8List(8 + padded);
      final view = ByteData.sublistView(chunk);
      chunk.setRange(0, 4, _fourCC('00dc'));
      view.setUint32(4, frame.length, Endian.little);
      chunk.setRange(8, 8 + frame.length, frame);

      // Offsets in the index are relative to the start of the 'movi' FourCC.
      offsets.add(moviSize);
      sizes.add(frame.length);
      moviSize += chunk.length;
      chunks.add(chunk);
    }

    final indexSize = 8 + _frames.length * 16;
    final headerList = _buildHeaderList();
    // RIFF payload: 'AVI ' + hdrl + 'LIST'+size+'movi'+data + idx1
    final riffSize = 4 + headerList.length + 8 + moviSize + indexSize;

    final out = BytesBuilder(copy: false);
    out.add(_fourCC('RIFF'));
    out.add(_u32(riffSize));
    out.add(_fourCC('AVI '));
    out.add(headerList);

    out.add(_fourCC('LIST'));
    out.add(_u32(moviSize));
    out.add(_fourCC('movi'));
    for (final c in chunks) {
      out.add(c);
    }

    out.add(_fourCC('idx1'));
    out.add(_u32(_frames.length * 16));
    for (var i = 0; i < _frames.length; i++) {
      out.add(_fourCC('00dc'));
      out.add(_u32(0x10)); // AVIIF_KEYFRAME
      out.add(_u32(offsets[i]));
      out.add(_u32(sizes[i]));
    }

    return out.toBytes();
  }

  Uint8List _buildHeaderList() {
    final microsPerFrame = (1000000 / fps).round();

    final avih = BytesBuilder(copy: false)
      ..add(_fourCC('avih'))
      ..add(_u32(56))
      ..add(_u32(microsPerFrame))
      ..add(_u32(0)) // max bytes per second
      ..add(_u32(0)) // padding granularity
      ..add(_u32(0x10)) // AVIF_HASINDEX
      ..add(_u32(_frames.length))
      ..add(_u32(0)) // initial frames
      ..add(_u32(1)) // streams
      ..add(_u32(0)) // suggested buffer size
      ..add(_u32(width))
      ..add(_u32(height))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0));

    final strh = BytesBuilder(copy: false)
      ..add(_fourCC('strh'))
      ..add(_u32(56))
      ..add(_fourCC('vids'))
      ..add(_fourCC('MJPG'))
      ..add(_u32(0)) // flags
      ..add(_u32(0)) // priority + language
      ..add(_u32(0)) // initial frames
      ..add(_u32(1)) // scale
      ..add(_u32(fps)) // rate
      ..add(_u32(0)) // start
      ..add(_u32(_frames.length)) // length
      ..add(_u32(0)) // suggested buffer size
      ..add(_u32(0xFFFFFFFF)) // quality: default
      ..add(_u32(0)) // sample size
      ..add(_u32(0)) // rcFrame left/top
      ..add(_u32(width | (height << 16)));

    final strf = BytesBuilder(copy: false)
      ..add(_fourCC('strf'))
      ..add(_u32(40))
      ..add(_u32(40)) // biSize
      ..add(_u32(width))
      ..add(_u32(height))
      ..add(_u32(1 | (24 << 16))) // planes + bit count
      ..add(_fourCC('MJPG'))
      ..add(_u32(width * height * 3))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0))
      ..add(_u32(0));

    final strl = BytesBuilder(copy: false)
      ..add(_fourCC('LIST'))
      ..add(_u32(4 + strh.length + strf.length))
      ..add(_fourCC('strl'))
      ..add(strh.toBytes())
      ..add(strf.toBytes());

    final hdrl = BytesBuilder(copy: false)
      ..add(_fourCC('LIST'))
      ..add(_u32(4 + avih.length + strl.length))
      ..add(_fourCC('hdrl'))
      ..add(avih.toBytes())
      ..add(strl.toBytes());

    return hdrl.toBytes();
  }

  static Uint8List _fourCC(String s) =>
      Uint8List.fromList(s.codeUnits.take(4).toList());

  static Uint8List _u32(int v) {
    final b = Uint8List(4);
    ByteData.sublistView(b).setUint32(0, v, Endian.little);
    return b;
  }
}
