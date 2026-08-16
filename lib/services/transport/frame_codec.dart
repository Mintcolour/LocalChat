import 'dart:async';
import 'dart:typed_data';

import 'package:localchat/services/security_service.dart';

/// LCF2（encrypted_stream_v2）加密流帧格式：
/// 24 字节头（魔数 + 帧序号 + 明文长度 + nonce/MAC/密文长度）后依次拼接
/// nonce、MAC、密文。每帧独立 AES-GCM 加密。
const int streamFrameMagic = 0x4C434632; // LCF2
const int streamFrameHeaderLength = 24;

/// 将单个加密块编码为一帧完整二进制。
Uint8List encodeFrame(EncryptedFileChunk chunk) {
  final output = BytesBuilder(copy: false);
  final header = ByteData(streamFrameHeaderLength)
    ..setUint32(0, streamFrameMagic)
    ..setUint32(4, chunk.index)
    ..setUint32(8, chunk.plainLength)
    ..setUint32(12, chunk.nonce.length)
    ..setUint32(16, chunk.mac.length)
    ..setUint32(20, chunk.cipherText.length);
  output
    ..add(header.buffer.asUint8List())
    ..add(chunk.nonce)
    ..add(chunk.mac)
    ..add(chunk.cipherText);
  return output.takeBytes();
}

/// 从字节流中逐帧解码 [EncryptedFileChunk]，校验魔数并在流意外截断时抛错。
class FrameReader {
  FrameReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;
  var _done = false;

  Future<EncryptedFileChunk?> next() async {
    final header = await _readExact(streamFrameHeaderLength);
    if (header == null) return null;
    final data = ByteData.sublistView(header);
    if (data.getUint32(0) != streamFrameMagic) {
      throw const FormatException('Invalid stream frame magic.');
    }
    final index = data.getUint32(4);
    final plainLength = data.getUint32(8);
    final nonceLength = data.getUint32(12);
    final macLength = data.getUint32(16);
    final cipherLength = data.getUint32(20);
    final nonce = await _readRequired(nonceLength);
    final mac = await _readRequired(macLength);
    final cipherText = await _readRequired(cipherLength);
    return EncryptedFileChunk(
      index: index,
      plainLength: plainLength,
      nonce: nonce,
      mac: mac,
      cipherText: cipherText,
    );
  }

  Future<Uint8List> _readRequired(int length) async {
    final bytes = await _readExact(length);
    if (bytes == null) {
      throw const FormatException('Unexpected end of stream.');
    }
    return bytes;
  }

  Future<Uint8List?> _readExact(int length) async {
    final output = BytesBuilder(copy: false);
    while (output.length < length) {
      final available = _buffer.length - _offset;
      if (available > 0) {
        final needed = length - output.length;
        final take = available < needed ? available : needed;
        output.add(Uint8List.sublistView(_buffer, _offset, _offset + take));
        _offset += take;
        if (_offset == _buffer.length) {
          _buffer = Uint8List(0);
          _offset = 0;
        }
      } else {
        if (_done) {
          if (output.length == 0) return null;
          throw const FormatException('Unexpected partial stream frame.');
        }
        if (await _iterator.moveNext()) {
          _buffer = Uint8List.fromList(_iterator.current);
          _offset = 0;
        } else {
          _done = true;
        }
      }
    }
    return output.takeBytes();
  }
}
