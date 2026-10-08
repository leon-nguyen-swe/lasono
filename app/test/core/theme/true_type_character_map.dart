import 'dart:typed_data';

/// Reads the character map ("cmap" table) of a TrueType font, to answer one question: does this font
/// have a glyph for this character? Enough of the format for that, not a font library.
/// Format: https://learn.microsoft.com/typography/opentype/spec/cmap
class TrueTypeCharacterMap {
  TrueTypeCharacterMap._(this._data, this._subtableOffset, this._format);

  final ByteData _data;
  final int _subtableOffset;
  final int _format;

  factory TrueTypeCharacterMap.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final tableCount = data.getUint16(4);

    int? cmapOffset;
    for (var i = 0; i < tableCount; i++) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      if (tag == 'cmap') cmapOffset = data.getUint32(record + 8);
    }
    if (cmapOffset == null) throw const FormatException('The font has no cmap table');

    // Prefer a Unicode subtable that can hold every character (format 12), else the usual BMP one (format 4).
    final subtableCount = data.getUint16(cmapOffset + 2);
    int? best;
    int? bestFormat;
    for (var i = 0; i < subtableCount; i++) {
      final record = cmapOffset + 4 + i * 8;
      final platform = data.getUint16(record);
      final encoding = data.getUint16(record + 2);
      final offset = cmapOffset + data.getUint32(record + 4);
      final format = data.getUint16(offset);
      final isUnicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (isUnicode && (format == 12 || format == 4) && (bestFormat == null || format == 12)) {
        best = offset;
        bestFormat = format;
      }
    }
    if (best == null) throw const FormatException('The font has no Unicode cmap subtable');
    return TrueTypeCharacterMap._(data, best, bestFormat!);
  }

  bool hasGlyph(int codePoint) =>
      _format == 12 ? _glyphInFormat12(codePoint) != 0 : _glyphInFormat4(codePoint) != 0;

  int _glyphInFormat12(int c) {
    final groupCount = _data.getUint32(_subtableOffset + 12);
    for (var i = 0; i < groupCount; i++) {
      final group = _subtableOffset + 16 + i * 12;
      final start = _data.getUint32(group);
      final end = _data.getUint32(group + 4);
      if (c >= start && c <= end) return _data.getUint32(group + 8) + (c - start);
    }
    return 0;
  }

  int _glyphInFormat4(int c) {
    if (c > 0xFFFF) return 0;
    final segmentCount = _data.getUint16(_subtableOffset + 6) ~/ 2;
    final endCodes = _subtableOffset + 14;
    final startCodes = endCodes + segmentCount * 2 + 2;
    final deltas = startCodes + segmentCount * 2;
    final rangeOffsets = deltas + segmentCount * 2;

    for (var i = 0; i < segmentCount; i++) {
      if (c > _data.getUint16(endCodes + i * 2)) continue;
      final start = _data.getUint16(startCodes + i * 2);
      if (c < start) return 0;
      final delta = _data.getInt16(deltas + i * 2);
      final rangeOffset = _data.getUint16(rangeOffsets + i * 2);
      if (rangeOffset == 0) return (c + delta) & 0xFFFF;
      final glyphAddress = rangeOffsets + i * 2 + rangeOffset + (c - start) * 2;
      final glyph = _data.getUint16(glyphAddress);
      return glyph == 0 ? 0 : (glyph + delta) & 0xFFFF;
    }
    return 0;
  }
}
