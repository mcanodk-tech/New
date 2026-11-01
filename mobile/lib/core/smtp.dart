import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'headers.dart';
import 'net.dart';

class SmtpConfig {
  SmtpConfig({required this.user, required this.password, required this.host, required this.port});

  factory SmtpConfig.forUser(String user, String password, {String? host, int? port}) {
    final domain = user.split('@').last.toLowerCase();
    final known = knownSmtpHosts[domain];
    return SmtpConfig(
      user: user,
      password: password,
      host: (host != null && host.isNotEmpty) ? host : (known?.$1 ?? 'smtp.$domain'),
      port: port ?? known?.$2 ?? 587,
    );
  }

  final String user;
  final String password;
  final String host;
  final int port;

  Map<String, Object> toJson() => {'user': user, 'password': password, 'host': host, 'port': port};

  static SmtpConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    return SmtpConfig(
      user: j['user'] as String? ?? '',
      password: j['password'] as String? ?? '',
      host: j['host'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 587,
    );
  }
}

const Map<String, (String, int)> knownSmtpHosts = {
  'gmail.com': ('smtp.gmail.com', 465),
  'googlemail.com': ('smtp.gmail.com', 465),
  'outlook.com': ('smtp.office365.com', 587),
  'hotmail.com': ('smtp.office365.com', 587),
  'live.com': ('smtp.office365.com', 587),
  'yahoo.com': ('smtp.mail.yahoo.com', 465),
  'yandex.com': ('smtp.yandex.com', 465),
  'yandex.com.tr': ('smtp.yandex.com', 465),
  'icloud.com': ('smtp.mail.me.com', 587),
  'me.com': ('smtp.mail.me.com', 587),
};

class SmtpException implements Exception {
  SmtpException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef TlsUpgrader = Future<Socket> Function(Socket socket, String host);

Future<Socket> defaultUpgrader(Socket socket, String host) => SecureSocket.secure(socket, host: host);

/// Basit SMTP istemcisi: 465 (doğrudan TLS) veya 587 (STARTTLS).
class SmtpSender {
  SmtpSender({this.connector = defaultConnector, this.upgrader = defaultUpgrader});

  final Connector connector;
  final TlsUpgrader upgrader;

  Future<void> send(SmtpConfig cfg, String to, String subject, String body) async {
    final implicitTls = cfg.port == 465;
    Socket socket;
    try {
      socket = await connector(cfg.host, cfg.port, tls: implicitTls);
    } on SocketException catch (e) {
      throw SmtpException('${cfg.host}:${cfg.port} bağlantısı kurulamadı (${e.message})');
    }
    var reader = ByteReader(socket);
    Future<(int, List<String>)> reply() async {
      final lines = <String>[];
      while (true) {
        final l = utf8.decode(await reader.readLine(timeout: const Duration(seconds: 30)), allowMalformed: true);
        lines.add(l);
        if (l.length < 4 || l[3] != '-') {
          return (int.tryParse(l.length >= 3 ? l.substring(0, 3) : '') ?? 0, lines);
        }
      }
    }

    Future<List<String>> cmd(String line, Set<int> ok) async {
      socket.add(utf8.encode('$line\r\n'));
      await socket.flush();
      final (code, lines) = await reply();
      if (!ok.contains(code)) {
        final shown = line.startsWith('AUTH') ? 'AUTH' : line.split(' ').first;
        throw SmtpException('SMTP $shown reddedildi: ${lines.join(' ')}');
      }
      return lines;
    }

    try {
      final (code, greet) = await reply();
      if (code != 220) throw SmtpException('SMTP karşılama hatası: ${greet.join(' ')}');
      var caps = await cmd('EHLO ayakizi.local', {250});
      if (!implicitTls) {
        await cmd('STARTTLS', {220});
        socket = await upgrader(socket, cfg.host);
        reader = ByteReader(socket);
        caps = await cmd('EHLO ayakizi.local', {250});
      }
      final authLine = caps.firstWhere((l) => l.toUpperCase().contains('AUTH'), orElse: () => '');
      if (authLine.toUpperCase().contains('PLAIN') || authLine.isEmpty) {
        final token = base64.encode(utf8.encode('\u0000${cfg.user}\u0000${cfg.password}'));
        await cmd('AUTH PLAIN $token', {235});
      } else {
        await cmd('AUTH LOGIN', {334});
        await cmd(base64.encode(utf8.encode(cfg.user)), {334});
        await cmd(base64.encode(utf8.encode(cfg.password)), {235});
      }
      await cmd('MAIL FROM:<${cfg.user}>', {250});
      await cmd('RCPT TO:<$to>', {250, 251});
      await cmd('DATA', {354});
      socket.add(utf8.encode(buildMessage(cfg.user, to, subject, body)));
      await cmd('.', {250});
      try {
        await cmd('QUIT', {221});
      } catch (_) {}
    } on SocketException catch (e) {
      throw SmtpException('SMTP bağlantı hatası: ${e.message}');
    } finally {
      socket.destroy();
    }
  }
}

String buildMessage(String from, String to, String subject, String body) {
  final rnd = Random.secure();
  final id = List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  final encSubject = '=?utf-8?B?${base64.encode(utf8.encode(subject))}?=';
  final b64 = base64.encode(utf8.encode(body));
  final wrapped = StringBuffer();
  for (var i = 0; i < b64.length; i += 76) {
    wrapped.write('${b64.substring(i, min(i + 76, b64.length))}\r\n');
  }
  final domain = from.split('@').last;
  return 'From: <$from>\r\n'
      'To: <$to>\r\n'
      'Subject: $encSubject\r\n'
      'Date: ${formatRfc2822Date(DateTime.now())}\r\n'
      'Message-ID: <$id@$domain>\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      '$wrapped';
}
