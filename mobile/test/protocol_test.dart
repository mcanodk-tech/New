import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ayakizi/core/classify.dart';
import 'package:ayakizi/core/imap.dart';
import 'package:ayakizi/core/net.dart';
import 'package:ayakizi/core/smtp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testte çalışan küçük sahte IMAP sunucusu.
class FakeImapServer {
  FakeImapServer(this.password);

  final String password;
  late ServerSocket _server;
  final List<String> commands = [];
  String? loginUser;
  String? loginPassword;

  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close();

  static List<int> _fetch(int seq, String headers) {
    final body = utf8.encode(headers);
    return [
      ...latin1.encode('* $seq FETCH (UID $seq BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {${body.length}}\r\n'),
      ...body,
      ...latin1.encode(')\r\n'),
    ];
  }

  Future<void> _handle(Socket s) async {
    final r = ByteReader(s);
    s.add(latin1.encode('* OK fake ready\r\n'));
    try {
      while (true) {
        var line = utf8.decode(await r.readLine());
        // Literal argümanları topla.
        final literals = <String>[];
        while (RegExp(r'\{(\d+)\}$').hasMatch(line)) {
          final n = int.parse(RegExp(r'\{(\d+)\}$').firstMatch(line)![1]!);
          s.add(latin1.encode('+ go ahead\r\n'));
          literals.add(utf8.decode(await r.readBytes(n)));
          line = '${line.replaceFirst(RegExp(r'\{\d+\}$'), '<lit${literals.length - 1}>')}'
              '${utf8.decode(await r.readLine())}';
        }
        commands.add(line);
        final sp = line.indexOf(' ');
        final tag = line.substring(0, sp);
        final rest = line.substring(sp + 1);
        if (rest.startsWith('LOGIN')) {
          final args = RegExp(r'"((?:[^"\\]|\\.)*)"|<lit(\d+)>')
              .allMatches(rest)
              .map((m) => m[1] ?? literals[int.parse(m[2]!)])
              .toList();
          loginUser = args[0];
          loginPassword = args[1];
          s.add(latin1.encode(args[1] == password
              ? '$tag OK LOGIN completed\r\n'
              : '$tag NO [AUTHENTICATIONFAILED] Invalid credentials\r\n'));
        } else if (rest.startsWith('LIST')) {
          s.add(latin1.encode('* LIST (\\HasNoChildren) "/" "INBOX"\r\n'
              '* LIST (\\HasNoChildren \\All) "/" "[Gmail]/All Mail"\r\n'
              '* LIST (\\HasNoChildren \\Trash) "/" "[Gmail]/Trash"\r\n'
              '$tag OK LIST done\r\n'));
        } else if (rest.startsWith('EXAMINE')) {
          s.add(latin1.encode('* 2 EXISTS\r\n$tag OK [READ-ONLY] EXAMINE done\r\n'));
        } else if (rest.startsWith('UID SEARCH')) {
          s.add(latin1.encode('* SEARCH 1 2\r\n$tag OK SEARCH done\r\n'));
        } else if (rest.startsWith('UID FETCH')) {
          final subj = base64.encode(utf8.encode('Hesabınız silindi'));
          s.add(_fetch(1, 'From: Tinder <no-reply@mail.gotinder.com>\r\n'
              'Subject: =?utf-8?q?Welcome_to_Tinder!?=\r\n'
              'Date: Tue, 1 Jan 2019 10:00:00 +0000\r\n\r\n'));
          s.add(_fetch(2, 'From: Bumble <hello@bumble.com>\r\n'
              'Subject: =?utf-8?B?$subj?=\r\n'
              'Date: Wed, 2 Jan 2019 10:00:00 +0000\r\n\r\n'));
          s.add(latin1.encode('$tag OK FETCH done\r\n'));
        } else if (rest.startsWith('LOGOUT')) {
          s.add(latin1.encode('* BYE\r\n$tag OK LOGOUT done\r\n'));
          await s.flush();
          s.destroy();
          return;
        } else {
          s.add(latin1.encode('$tag BAD unknown\r\n'));
        }
        await s.flush();
      }
    } catch (_) {
      s.destroy();
    }
  }
}

Connector plainTo(int port) => (host, p, {required bool tls}) => Socket.connect(InternetAddress.loopbackIPv4, port);

void main() {
  group('IMAP', () {
    late FakeImapServer server;

    tearDown(() => server.stop());

    test('scans headers read-only and dedups across folders', () async {
      server = FakeImapServer('app-pass');
      await server.start();
      final events = await scanMailbox(
        user: 'me@gmail.com',
        password: 'app-pass',
        connector: plainTo(server.port),
      );
      expect(events, hasLength(2));
      final by = {for (final e in events) e.service: e};
      expect(by['Tinder']!.type, EventType.signup);
      expect(by['Tinder']!.subject, 'Welcome to Tinder!');
      expect(by['Bumble']!.type, EventType.deletion);
      expect(by['Bumble']!.subject, 'Hesabınız silindi');
      expect(by['Bumble']!.date, DateTime.utc(2019, 1, 2, 10));
      // Salt-okunur: SELECT değil EXAMINE, BODY değil BODY.PEEK.
      expect(server.commands.any((c) => c.contains(' SELECT ')), isFalse);
      expect(server.commands.where((c) => c.contains(' EXAMINE ')), hasLength(2));
      expect(server.commands.firstWhere((c) => c.contains('UID FETCH')), contains('BODY.PEEK'));
    });

    test('non-ASCII password is sent as a literal', () async {
      server = FakeImapServer('şifre"1');
      await server.start();
      await scanMailbox(user: 'me@gmail.com', password: 'şifre"1', connector: plainTo(server.port));
      expect(server.loginPassword, 'şifre"1');
    });

    test('wrong password raises auth error', () async {
      server = FakeImapServer('right');
      await server.start();
      await expectLater(
        scanMailbox(user: 'me@gmail.com', password: 'wrong', connector: plainTo(server.port)),
        throwsA(isA<ImapException>().having((e) => e.authFailed, 'authFailed', isTrue)),
      );
    });
  });

  group('SMTP', () {
    test('sends a UTF-8 message with AUTH PLAIN', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<Map<String, Object>>();
      server.listen((s) async {
        final r = ByteReader(s);
        String? auth;
        final data = StringBuffer();
        void send(String l) => s.add(utf8.encode('$l\r\n'));
        send('220 fake ESMTP');
        try {
          while (true) {
            final line = utf8.decode(await r.readLine());
            if (line.startsWith('EHLO')) {
              send('250-fake\r\n250-AUTH LOGIN PLAIN\r\n250 OK');
            } else if (line.startsWith('AUTH PLAIN ')) {
              auth = utf8.decode(base64.decode(line.substring(11)));
              send('235 ok');
            } else if (line.startsWith('MAIL') || line.startsWith('RCPT')) {
              send('250 ok');
            } else if (line == 'DATA') {
              send('354 go');
              while (true) {
                final l = utf8.decode(await r.readLine());
                if (l == '.') break;
                data.writeln(l);
              }
              send('250 queued');
            } else if (line == 'QUIT') {
              send('221 bye');
              await s.flush();
              s.destroy();
              received.complete({'auth': auth!, 'data': data.toString()});
              return;
            }
          }
        } catch (e) {
          if (!received.isCompleted) received.completeError(e);
        }
      });

      await SmtpSender(connector: plainTo(server.port)).send(
        SmtpConfig(user: 'me@gmail.com', password: 'pw', host: 'smtp.gmail.com', port: 465),
        'you@x.com',
        'ayakizi doğrulama kodu: 123456',
        'Kod: 123456',
      );
      final got = await received.future.timeout(const Duration(seconds: 5));
      await server.close();
      expect(got['auth'], '\u0000me@gmail.com\u0000pw');
      final data = got['data']! as String;
      expect(data, contains('To: <you@x.com>'));
      expect(data, contains('Subject: =?utf-8?B?'));
      final bodyB64 = data.split('\n\n').last.replaceAll(RegExp(r'\s'), '');
      expect(utf8.decode(base64.decode(bodyB64)), 'Kod: 123456');
    });
  });
}
