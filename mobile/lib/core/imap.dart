import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'classify.dart';
import 'headers.dart';
import 'models.dart';
import 'net.dart';

/// Kullanıcının KENDİ posta kutusunu IMAP ile salt-okunur tarar.
/// Yalnızca başlıklar okunur (BODY.PEEK + EXAMINE): mesajlar okunmuş işaretlenmez.

const Map<String, String> knownImapHosts = {
  'gmail.com': 'imap.gmail.com',
  'googlemail.com': 'imap.gmail.com',
  'outlook.com': 'outlook.office365.com',
  'hotmail.com': 'outlook.office365.com',
  'live.com': 'outlook.office365.com',
  'msn.com': 'outlook.office365.com',
  'yahoo.com': 'imap.mail.yahoo.com',
  'yandex.com': 'imap.yandex.com',
  'yandex.com.tr': 'imap.yandex.com',
  'icloud.com': 'imap.mail.me.com',
  'me.com': 'imap.mail.me.com',
  'gmx.com': 'imap.gmx.com',
  'aol.com': 'imap.aol.com',
  'zoho.com': 'imap.zoho.com',
};

String guessImapHost(String address) {
  final domain = address.split('@').last.toLowerCase();
  return knownImapHosts[domain] ?? 'imap.$domain';
}

class ImapException implements Exception {
  ImapException(this.message, {this.authFailed = false});
  final String message;
  final bool authFailed;
  @override
  String toString() => message;
}

class ImapLine {
  ImapLine(this.text, this.literals);
  final String text;
  final List<Uint8List> literals;
}

class ImapFolder {
  ImapFolder(this.flags, this.name);
  final Set<String> flags;
  final String name;
}

class ImapClient {
  ImapClient(this._socket) : _reader = ByteReader(_socket);

  final Socket _socket;
  final ByteReader _reader;
  int _tagNo = 0;

  static Future<ImapClient> connect(String host, int port,
      {Connector connector = defaultConnector}) async {
    final socket = await connector(host, port, tls: true);
    final client = ImapClient(socket);
    final greeting = await client._readLine();
    if (!greeting.text.startsWith('* OK') && !greeting.text.startsWith('* PREAUTH')) {
      await client.close();
      throw ImapException('Beklenmeyen sunucu yanıtı: ${greeting.text}');
    }
    return client;
  }

  Future<void> close() async {
    try {
      await _reader.cancel();
    } catch (_) {}
    _socket.destroy();
  }

  Future<ImapLine> _readLine() async {
    final text = StringBuffer();
    final literals = <Uint8List>[];
    while (true) {
      final line = latin1.decode(await _reader.readLine());
      text.write(line);
      final m = RegExp(r'\{(\d+)\}$').firstMatch(line);
      if (m == null) break;
      literals.add(await _reader.readBytes(int.parse(m[1]!)));
    }
    return ImapLine(text.toString(), literals);
  }

  static bool _needsLiteral(String s) =>
      s.codeUnits.any((c) => c > 126 || c < 32) || s.length > 200;

  static String quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Komut gönderir. [args] içindeki değerler gerekiyorsa literal olarak yollanır.
  Future<List<ImapLine>> command(String verb, [List<String> args = const [], List<String> raw = const []]) async {
    final tag = 'A${++_tagNo}';
    final segments = <Object>['$tag $verb'];
    for (final a in args) {
      if (_needsLiteral(a)) {
        segments.add(Uint8List.fromList(utf8.encode(a)));
      } else {
        segments.add(' ${quote(a)}');
      }
    }
    for (final r in raw) {
      segments.add(' $r');
    }
    // Literal içermeyen kısımları birleştirip gönder; literal öncesi devam satırı bekle.
    final out = StringBuffer();
    for (final seg in segments) {
      if (seg is String) {
        out.write(seg);
      } else {
        final bytes = seg as Uint8List;
        out.write(' {${bytes.length}}\r\n');
        _socket.add(latin1.encode(out.toString()));
        await _socket.flush();
        out.clear();
        final cont = await _readLine();
        if (!cont.text.startsWith('+')) {
          throw ImapException('Sunucu literal kabul etmedi: ${cont.text}');
        }
        _socket.add(bytes);
      }
    }
    out.write('\r\n');
    _socket.add(latin1.encode(out.toString()));
    await _socket.flush();

    final untagged = <ImapLine>[];
    while (true) {
      final line = await _readLine();
      if (line.text.startsWith('$tag ')) {
        final status = line.text.substring(tag.length + 1);
        if (status.startsWith('OK')) return untagged;
        throw ImapException(status, authFailed: verb == 'LOGIN');
      }
      untagged.add(line);
    }
  }

  Future<void> login(String user, String password) async {
    try {
      await command('LOGIN', [user, password]);
    } on ImapException catch (e) {
      throw ImapException('Giriş başarısız: ${e.message}', authFailed: true);
    }
  }

  Future<List<ImapFolder>> list() async {
    final lines = await command('LIST', ['', '*']);
    final re = RegExp(r'^\* LIST \(([^)]*)\) ("(?:[^"\\]|\\.)*"|NIL) (.+)$');
    final out = <ImapFolder>[];
    for (final l in lines) {
      final m = re.firstMatch(l.text);
      if (m == null) continue;
      final flags = m[1]!.split(' ').where((f) => f.isNotEmpty).map((f) => f.toLowerCase()).toSet();
      var name = m[3]!.trim();
      if (RegExp(r'^\{\d+\}$').hasMatch(name) && l.literals.isNotEmpty) {
        name = latin1.decode(l.literals.last);
      } else if (name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      out.add(ImapFolder(flags, name));
    }
    return out;
  }

  /// Gmail'de "Tüm Postalar" + spam/çöp yeterli; diğerlerinde INBOX + arşiv/spam/çöp.
  static List<String> chooseFolders(List<ImapFolder> folders) {
    final all = folders.where((f) => f.flags.contains(r'\all')).map((f) => f.name).toList();
    if (all.isNotEmpty) {
      return [
        ...all,
        ...folders
            .where((f) => f.flags.contains(r'\junk') || f.flags.contains(r'\trash'))
            .map((f) => f.name),
      ];
    }
    const interesting = {r'\archive', r'\junk', r'\trash'};
    return [
      'INBOX',
      ...folders
          .where((f) => f.flags.any(interesting.contains) && f.name.toUpperCase() != 'INBOX')
          .map((f) => f.name),
    ];
  }

  Future<void> examine(String folder) => command('EXAMINE', [folder]);

  Future<List<int>> searchUids({DateTime? since}) async {
    final criteria = since == null ? ['ALL'] : ['SINCE', _imapDate(since)];
    final lines = await command('UID SEARCH', const [], criteria);
    final uids = <int>[];
    for (final l in lines) {
      if (l.text.startsWith('* SEARCH')) {
        uids.addAll(l.text.substring(8).trim().split(' ').map(int.tryParse).whereType<int>());
      }
    }
    return uids;
  }

  Future<List<ParsedHeaders>> fetchHeaders(List<int> uids) async {
    final lines = await command(
        'UID FETCH', const [], [uids.join(','), '(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])']);
    return [
      for (final l in lines)
        if (l.text.contains(' FETCH ') && l.literals.isNotEmpty) parseHeaders(l.literals.first),
    ];
  }

  Future<void> logout() async {
    try {
      await command('LOGOUT');
    } catch (_) {}
    await close();
  }

  static String _imapDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day}-${m[d.month - 1]}-${d.year}';
  }
}

const int fetchBatch = 300;

Future<List<AccountEvent>> scanMailbox({
  required String user,
  required String password,
  String? host,
  int port = 993,
  DateTime? since,
  void Function(String)? log,
  Connector connector = defaultConnector,
}) async {
  final h = (host == null || host.isEmpty) ? guessImapHost(user) : host;
  final say = log ?? (_) {};
  final client = await ImapClient.connect(h, port, connector: connector);
  final events = <AccountEvent>[];
  final seen = <String>{};
  try {
    await client.login(user, password);
    final folders = ImapClient.chooseFolders(await client.list());
    for (final folder in folders) {
      try {
        await client.examine(folder);
      } on ImapException {
        say('  ! klasör açılamadı: $folder');
        continue;
      }
      final uids = await client.searchUids(since: since);
      say('  $folder: ${uids.length} mesaj');
      for (var i = 0; i < uids.length; i += fetchBatch) {
        final chunk = uids.sublist(i, i + fetchBatch > uids.length ? uids.length : i + fetchBatch);
        for (final hdr in await client.fetchHeaders(chunk)) {
          if (hdr.domain.isEmpty) continue;
          // Gmail'de aynı mesaj birden çok klasörde olabilir.
          final key = '${hdr.from}|${hdr.subject}|${hdr.date?.toIso8601String() ?? ''}';
          if (!seen.add(key)) continue;
          final svc = resolveEmailService(hdr.domain);
          events.add(AccountEvent(
            source: 'email',
            account: user.toLowerCase(),
            sender: hdr.from,
            subject: hdr.subject,
            date: hdr.date,
            type: classify(hdr.subject),
            service: svc.service,
            category: svc.category,
            known: svc.known,
          ));
        }
        say('    ${i + chunk.length}/${uids.length}');
      }
    }
  } finally {
    await client.logout();
  }
  return events;
}
