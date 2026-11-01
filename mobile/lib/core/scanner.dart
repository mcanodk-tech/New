import 'dart:io';

import 'hibp.dart';
import 'imap.dart';
import 'models.dart';
import 'sms.dart';

class ImapAccount {
  ImapAccount({required this.address, required this.password, this.host = ''});

  final String address;
  final String password;
  final String host;

  Map<String, String> toJson() => {'address': address, 'password': password, 'host': host};

  static ImapAccount? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = j['address'];
    if (a is! String || a.isEmpty) return null;
    return ImapAccount(
        address: a, password: (j['password'] as String?) ?? '', host: (j['host'] as String?) ?? '');
  }
}

class ScanResult {
  ScanResult({
    required this.events,
    required this.inventory,
    required this.breaches,
    required this.scanned,
    required this.errors,
    required this.finishedAt,
  });

  final List<AccountEvent> events;
  final List<AccountRecord> inventory;
  final List<Breach> breaches;
  final List<String> scanned;
  final List<String> errors;
  final DateTime finishedAt;

  Map<String, Object?> toJson() => {
        'generated_at': finishedAt.toIso8601String(),
        'scanned': scanned,
        'accounts': [for (final r in inventory) r.toJson(finishedAt)],
        'breaches': [for (final b in breaches) b.toJson()],
        'events': [for (final e in events) e.toJson()],
      };
}

typedef MailboxScanner = Future<List<AccountEvent>> Function(
    ImapAccount account, DateTime? since, void Function(String) log);

Future<List<AccountEvent>> _defaultMailboxScanner(
        ImapAccount a, DateTime? since, void Function(String) log) =>
    scanMailbox(user: a.address, password: a.password, host: a.host, since: since, log: log);

/// CLI'deki run_scan ile aynı akış.
Future<ScanResult> runScan({
  List<ImapAccount> imapAccounts = const [],
  List<String> otpVerified = const [],
  List<SmsBackup> smsBackups = const [],
  DateTime? since,
  String? hibpKey,
  required void Function(String) log,
  MailboxScanner mailboxScanner = _defaultMailboxScanner,
  HibpClient? hibp,
}) async {
  final events = <AccountEvent>[];
  final verified = <String>[];
  final scanned = <String>[];
  final errors = <String>[];
  final breaches = <Breach>[];

  void err(String m) {
    errors.add(m);
    log('  ! $m');
  }

  for (final acc in imapAccounts) {
    log('[e-posta] ${acc.address}');
    try {
      events.addAll(await mailboxScanner(acc, since, log));
      // Giriş başarılı -> adresin sahibi olduğunuz kanıtlandı.
      verified.add(acc.address.toLowerCase());
      scanned.add(acc.address);
    } on ImapException catch (e) {
      err(e.authFailed
          ? '${acc.address}: giriş başarısız. Gmail/Outlook için uygulama şifresi gerekir.'
          : '${acc.address}: ${e.message}');
    } on SocketException catch (e) {
      err('${acc.address}: bağlantı hatası (${e.message})');
    } on Exception catch (e) {
      err('${acc.address}: $e');
    }
  }

  for (final a in otpVerified) {
    final addr = a.trim().toLowerCase();
    if (!verified.contains(addr)) {
      verified.add(addr);
      scanned.add('$addr (kodla doğrulandı)');
    }
  }

  for (final b in smsBackups) {
    log('[sms] ${b.phone}: ${b.fileName} (${b.messages.length} mesaj)');
    events.addAll(smsToEvents(b.messages, b.phone));
    scanned.add('${b.phone} (SMS yedeği)');
  }

  if (hibpKey != null && hibpKey.isNotEmpty) {
    final client = hibp ?? HibpClient();
    for (final addr in verified) {
      log('[sızıntı] $addr');
      try {
        breaches.addAll(await client.breachedAccount(addr, hibpKey));
      } on HibpException catch (e) {
        err('$addr: ${e.message}');
      } on Exception catch (e) {
        err('$addr: sızıntı kontrolü başarısız ($e)');
      }
    }
  }

  final inventory = buildInventory(events);
  log('${inventory.length} hesap, ${breaches.length} sızıntı bulundu.');
  return ScanResult(
    events: events,
    inventory: inventory,
    breaches: breaches,
    scanned: scanned,
    errors: errors,
    finishedAt: DateTime.now().toUtc(),
  );
}
