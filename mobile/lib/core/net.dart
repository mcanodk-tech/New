import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Soket akışı üzerinde satır (CRLF) ve sabit uzunluklu okuma yapar.
class ByteReader {
  ByteReader(Stream<List<int>> stream) : _it = StreamIterator(stream);

  final StreamIterator<List<int>> _it;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  Uint8List _buf = Uint8List(0);
  int _pos = 0;
  int _scan = 0;

  Future<bool> _fill(Duration timeout) async {
    final ok = await _it.moveNext().timeout(timeout);
    if (!ok) return false;
    _pending
      ..add(_buf.sublist(_pos))
      ..add(_it.current);
    _buf = _pending.takeBytes();
    _scan = _scan - _pos < 0 ? 0 : _scan - _pos;
    _pos = 0;
    return true;
  }

  Future<Uint8List> readLine({Duration timeout = const Duration(seconds: 60)}) async {
    while (true) {
      for (var i = _scan > _pos ? _scan : _pos; i < _buf.length - 1; i++) {
        if (_buf[i] == 13 && _buf[i + 1] == 10) {
          final line = Uint8List.sublistView(_buf, _pos, i);
          _pos = i + 2;
          _scan = _pos;
          return Uint8List.fromList(line);
        }
      }
      _scan = _buf.length > 0 ? _buf.length - 1 : 0;
      if (!await _fill(timeout)) {
        throw const SocketException('Sunucu bağlantıyı kapattı');
      }
    }
  }

  Future<Uint8List> readBytes(int n, {Duration timeout = const Duration(seconds: 60)}) async {
    while (_buf.length - _pos < n) {
      if (!await _fill(timeout)) {
        throw const SocketException('Sunucu bağlantıyı kapattı');
      }
    }
    final out = Uint8List.fromList(Uint8List.sublistView(_buf, _pos, _pos + n));
    _pos += n;
    _scan = _pos;
    return out;
  }

  Future<void> cancel() => _it.cancel();
}

/// Testlerde sahte sunucuya düz soketle bağlanabilmek için enjekte edilebilir.
typedef Connector = Future<Socket> Function(String host, int port, {required bool tls});

Future<Socket> defaultConnector(String host, int port, {required bool tls}) {
  const timeout = Duration(seconds: 20);
  return tls
      ? SecureSocket.connect(host, port, timeout: timeout)
      : Socket.connect(host, port, timeout: timeout);
}
