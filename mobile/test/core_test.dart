import 'dart:convert';

import 'package:ayakizi/core/classify.dart';
import 'package:ayakizi/core/headers.dart';
import 'package:ayakizi/core/hibp.dart';
import 'package:ayakizi/core/imap.dart';
import 'package:ayakizi/core/models.dart';
import 'package:ayakizi/core/otp.dart';
import 'package:ayakizi/core/scanner.dart';
import 'package:ayakizi/core/services.dart';
import 'package:ayakizi/core/sms.dart';
import 'package:ayakizi/core/smtp.dart';
import 'package:flutter_test/flutter_test.dart';

AccountEvent ev(String service, EventType type, int daysAgo, {bool known = true, String cat = 'dating'}) =>
    AccountEvent(
      source: 'email',
      account: 'me@x.com',
      sender: 'a@b.com',
      subject: 'subj',
      date: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
      type: type,
      service: service,
      category: cat,
      known: known,
    );

void main() {
  group('classify', () {
    test('English', () {
      expect(classify('Welcome to Tinder!'), EventType.signup);
      expect(classify('Please verify your email address'), EventType.signup);
      expect(classify('Your account has been deleted'), EventType.deletion);
      expect(classify("We're sorry to see you go"), EventType.deletion);
      expect(classify('Reset your password'), EventType.passwordReset);
      expect(classify('New sign-in from Chrome on Windows'), EventType.security);
      expect(classify('123456 is your Tinder code'), EventType.security);
      expect(classify('Your Tinder code is 123456'), EventType.security);
      expect(classify('50% off this weekend'), EventType.other);
    });

    test('Turkish, including upper case and ASCII spelling', () {
      expect(classify("Trendyol'a hoş geldin!"), EventType.signup);
      expect(classify('HESABINIZ OLUŞTURULDU'), EventType.signup);
      expect(classify('Hesabınız başarıyla silindi'), EventType.deletion);
      expect(classify('Getir hesabiniz silindi.'), EventType.deletion);
      expect(classify('ÜYELİĞİNİZ SONLANDIRILDI'), EventType.deletion);
      expect(classify('Şifrenizi sıfırlayın'), EventType.passwordReset);
      expect(classify('Doğrulama kodunuz: 482913'), EventType.security);
      expect(classify('Yeni sezon ürünleri'), EventType.other);
    });

    test('deletion beats signup', () {
      expect(classify('Welcome back - your account was deleted'), EventType.deletion);
    });
  });

  group('services', () {
    test('domain matching with subdomains', () {
      expect(matchDomain('mail.gotinder.com')?.name, 'Tinder');
      expect(matchDomain('info.trendyol.com')?.name, 'Trendyol');
      expect(matchDomain('example.org'), isNull);
    });

    test('registrable domain', () {
      expect(registrableDomain('news.shop.example.com.tr'), 'example.com.tr');
      expect(registrableDomain('a.b.example.com'), 'example.com');
    });

    test('text matching uses word boundaries and longest keyword', () {
      expect(matchText('Your Bumble code is 1234')?.name, 'Bumble');
      expect(matchText('Trendyol Yemek siparişin yolda')?.name, 'Trendyol Yemek');
      expect(matchText('tindering around'), isNull);
    });
  });

  group('inventory', () {
    test('status', () {
      final inv = {
        for (final r in buildInventory([
          ev('Tinder', EventType.signup, 900),
          ev('Tinder', EventType.deletion, 800),
          ev('Bumble', EventType.signup, 30),
          ev('Hinge', EventType.signup, 900),
          ev('Badoo', EventType.deletion, 500),
          ev('Badoo', EventType.security, 10),
        ]))
          r.service: r
      };
      expect(inv['Tinder']!.status(), AccountStatus.deleted);
      expect(inv['Bumble']!.status(), AccountStatus.active);
      expect(inv['Hinge']!.status(), AccountStatus.dormant);
      expect(inv['Badoo']!.status(), AccountStatus.active);
    });

    test('unknown newsletters are dropped', () {
      final inv = buildInventory([
        ev('shop.com', EventType.other, 5, known: false, cat: 'other'),
        ev('forum.net', EventType.signup, 5, known: false, cat: 'other'),
      ]);
      expect(inv.map((r) => r.service), ['forum.net']);
    });
  });

  group('headers', () {
    test('parses folded, encoded headers', () {
      final subject = base64.encode(utf8.encode('Hesabınız silindi'));
      final raw = latin1.encode('From: "Bumble" <Hello@Bumble.com>\r\n'
          'Subject: =?utf-8?B?$subject?=\r\n'
          'Date: Wed, 2 Jan 2019 13:00:00\r\n +0300\r\n\r\n');
      final h = parseHeaders(raw);
      expect(h.from, 'hello@bumble.com');
      expect(h.domain, 'bumble.com');
      expect(h.subject, 'Hesabınız silindi');
      expect(h.date, DateTime.utc(2019, 1, 2, 10));
    });

    test('Q encoding, Turkish charset and adjacent words', () {
      expect(decodeHeaderValue('=?iso-8859-9?Q?=DDyi_g=FCnler?= =?utf-8?Q?_d=C3=BCnya?='), 'İyi günler dünya');
    });

    test('raw 8-bit UTF-8 subject', () {
      final raw = latin1.decode(utf8.encode('Hoş geldiniz'));
      expect(decodeHeaderValue(raw), 'Hoş geldiniz');
    });

    test('dates', () {
      expect(parseRfc2822Date('1 Jan 2019 10:00:00 GMT'), DateTime.utc(2019, 1, 1, 10));
      expect(parseRfc2822Date('Mon, 05 Feb 24 08:30 -0500'), DateTime.utc(2024, 2, 5, 13, 30));
      expect(parseRfc2822Date('garbage'), isNull);
    });

    test('format date', () {
      expect(formatRfc2822Date(DateTime.utc(2026, 11, 1, 9, 5, 7)), 'Sun, 01 Nov 2026 09:05:07 +0000');
    });
  });

  group('imap helpers', () {
    test('choose folders on Gmail', () {
      final folders = ImapClient.chooseFolders([
        ImapFolder({r'\hasnochildren'}, 'INBOX'),
        ImapFolder({r'\all'}, '[Gmail]/All Mail'),
        ImapFolder({r'\trash'}, '[Gmail]/Trash'),
      ]);
      expect(folders, ['[Gmail]/All Mail', '[Gmail]/Trash']);
    });

    test('choose folders elsewhere', () {
      expect(
          ImapClient.chooseFolders([ImapFolder({}, 'INBOX'), ImapFolder({r'\junk'}, 'Spam')]),
          ['INBOX', 'Spam']);
    });

    test('guess host', () {
      expect(guessImapHost('a@hotmail.com'), 'outlook.office365.com');
      expect(guessImapHost('a@firma.com.tr'), 'imap.firma.com.tr');
    });
  });

  group('sms', () {
    test('keeps account messages, drops personal ones, masks codes', () {
      final events = smsToEvents([
        SmsMessage('TINDER', 'Your Tinder code is 123456', DateTime.utc(2020)),
        SmsMessage('+905551112233', 'akşam görüşürüz', DateTime.utc(2020)),
        SmsMessage('ACME', 'Doğrulama kodunuz: 9911', DateTime.utc(2020)),
      ], '+90555');
      expect(events.map((e) => (e.service, e.type)), [
        ('Tinder', EventType.security),
        ('ACME', EventType.security),
      ]);
      expect(events.first.subject, isNot(contains('123456')));
      expect(events.first.subject, contains('••••'));
    });
  });

  group('sms backup parsing', () {
    Stream<String> chunks(String s, int n) async* {
      for (var i = 0; i < s.length; i += n) {
        yield s.substring(i, i + n > s.length ? s.length : i + n);
      }
    }

    test('parses received messages across chunk boundaries and unescapes entities', () async {
      const xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<smses count="3">\n'
          '  <sms protocol="0" address="TINDER" date="1600000000000" type="1" '
          'body="Your Tinder code is 123456 &amp; welcome&#10;!" read="1" />\n'
          '  <sms address="+905551112233" date="1600000000000" type="2" body="giden" />\n'
          '  <sms address="GETIR" date="1650000000000" type="1" body="Hesabınız silindi" />\n'
          '</smses>';
      final msgs = await parseSmsBackup(chunks(xml, 7));
      expect(msgs.map((m) => m.address), ['TINDER', 'GETIR']);
      expect(msgs.first.body, 'Your Tinder code is 123456 & welcome\n!');
      expect(msgs.first.date, DateTime.fromMillisecondsSinceEpoch(1600000000000, isUtc: true));
      expect(msgs.last.body, 'Hesabınız silindi');
    });

    test('rejects files that are not SMS backups', () async {
      await expectLater(parseSmsBackup(Stream.value('<html><body/></html>')),
          throwsA(isA<SmsBackupException>()));
      await expectLater(parseSmsBackup(Stream.value('<smses><sms address=a /></smses>')),
          throwsA(isA<SmsBackupException>()));
    });
  });

  group('otp', () {
    final cfg = SmtpConfig(user: 'me@gmail.com', password: 'x', host: 'h', port: 465);

    test('correct code verifies once', () async {
      String? sent;
      final store = OtpStore(sender: (c, to, code) async { sent = code; });
      await store.issue('Me@X.com', cfg);
      expect(store.check('me@x.com', sent!).ok, isTrue);
      expect(store.check('me@x.com', sent!).ok, isFalse); // tek kullanımlık
    });

    test('limited attempts', () async {
      final store = OtpStore(sender: (c, to, code) async {});
      await store.issue('a@x.com', cfg);
      for (var i = 0; i < maxAttempts; i++) {
        expect(store.check('a@x.com', 'nope').ok, isFalse);
      }
      expect(store.hasPending('a@x.com'), isFalse);
    });

    test('expiry', () async {
      var now = DateTime(2026);
      String? sent;
      final store = OtpStore(sender: (c, to, code) async { sent = code; }, clock: () => now);
      await store.issue('a@x.com', cfg);
      now = now.add(codeTtl + const Duration(seconds: 1));
      expect(store.check('a@x.com', sent!).ok, isFalse);
    });

    test('smtp config guess', () {
      final c = SmtpConfig.forUser('me@outlook.com', 'x');
      expect((c.host, c.port), ('smtp.office365.com', 587));
      expect(SmtpConfig.forUser('me@firma.com', 'x').host, 'smtp.firma.com');
    });
  });

  group('hibp', () {
    test('range parsing', () {
      const text = '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\nABCDEF:42\r\n';
      expect(parseRangeResponse(text, 'ABCDEF'), 42);
      expect(parseRangeResponse(text, 'FFFF'), 0);
    });

    test('password check sends only the 5-char prefix', () async {
      Uri? seen;
      final client = HibpClient(get: (uri, headers) async {
        seen = uri;
        return (status: 200, body: '1E4C9B93F3F0682250B6CF8331B7EE68FD8:3861493\r\n', headers: <String, String>{});
      });
      expect(await client.pwnedPasswordCount('password'), 3861493);
      expect(seen.toString(), endsWith('/range/5BAA6'));
    });

    test('breach parsing and 404', () async {
      final client = HibpClient(get: (uri, headers) async {
        expect(headers['hibp-api-key'], 'k');
        if (uri.path.contains('clean')) {
          return (status: 404, body: '', headers: <String, String>{});
        }
        return (
          status: 200,
          body: jsonEncode([
            {'Name': 'Adobe', 'Title': 'Adobe', 'Domain': 'adobe.com', 'BreachDate': '2013-10-04',
              'DataClasses': ['Email addresses', 'Passwords']}
          ]),
          headers: <String, String>{},
        );
      });
      final b = await client.breachedAccount('me@x.com', 'k');
      expect(b.single.title, 'Adobe');
      expect(b.single.dataClasses, ['Email addresses', 'Passwords']);
      expect(await client.breachedAccount('clean@x.com', 'k'), isEmpty);
    });
  });

  group('scanner', () {
    test('HIBP only for verified addresses; failed logins are not verified', () async {
      final checked = <String>[];
      final hibp = HibpClient(get: (uri, headers) async {
        checked.add(Uri.decodeComponent(uri.pathSegments.last));
        return (status: 404, body: '', headers: <String, String>{});
      });
      final res = await runScan(
        imapAccounts: [
          ImapAccount(address: 'ok@x.com', password: 'p'),
          ImapAccount(address: 'bad@x.com', password: 'p'),
        ],
        otpVerified: ['otp@x.com'],
        smsBackups: [
          SmsBackup(phone: '+90555', fileName: 'y.xml', messages: [
            SmsMessage('GETIR', 'Getir hesabiniz silindi.', DateTime.utc(2022)),
          ]),
        ],
        hibpKey: 'k',
        hibp: hibp,
        log: (_) {},
        mailboxScanner: (a, since, log) async {
          if (a.address.startsWith('bad')) throw ImapException('no', authFailed: true);
          return [ev('Tinder', EventType.signup, 10)];
        },
      );
      expect(checked, ['ok@x.com', 'otp@x.com']);
      expect(res.errors.single, contains('bad@x.com'));
      expect(res.inventory.map((r) => r.service).toSet(), {'Tinder', 'Getir'});
      expect(jsonDecode(jsonEncode(res.toJson()))['accounts'], hasLength(2));
    });
  });
}
