import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/hibp.dart';
import 'core/otp.dart';
import 'core/scanner.dart';
import 'core/sms.dart';
import 'core/smtp.dart';

/// Kalıcı ayarlar için soyutlama (testlerde bellek içi sürüm kullanılır).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureKeyValueStore implements KeyValueStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

enum ScanStatus { idle, running, done, failed }

class AppState extends ChangeNotifier {
  AppState({KeyValueStore? store, OtpStore? otp, SmsSource? sms, HibpClient? hibp})
      : _store = store ?? SecureKeyValueStore(),
        otp = otp ?? OtpStore(),
        _sms = sms ?? SmsSource(),
        _hibp = hibp ?? HibpClient();

  static const _key = 'ayakizi_state_v1';

  final KeyValueStore _store;
  final OtpStore otp;
  final SmsSource _sms;
  final HibpClient _hibp;

  final List<ImapAccount> accounts = [];
  final List<String> verified = [];
  SmtpConfig? smtp;
  String? hibpKey;
  bool includeSms = SmsSource.supported;
  String phoneLabel = '';
  bool loaded = false;

  ScanStatus status = ScanStatus.idle;
  final List<String> log = [];
  ScanResult? result;

  Future<void> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        accounts.addAll((j['accounts'] as List? ?? const [])
            .map(ImapAccount.fromJson)
            .whereType<ImapAccount>());
        verified.addAll((j['verified'] as List? ?? const []).whereType<String>());
        smtp = SmtpConfig.fromJson(j['smtp']);
        hibpKey = j['hibpKey'] as String?;
        includeSms = (j['includeSms'] as bool?) ?? includeSms;
        phoneLabel = (j['phoneLabel'] as String?) ?? '';
      }
    } catch (e) {
      debugPrint('ayarlar okunamadı: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() => _store.write(
        _key,
        jsonEncode({
          'accounts': [for (final a in accounts) a.toJson()],
          'verified': verified,
          'smtp': smtp?.toJson(),
          'hibpKey': hibpKey,
          'includeSms': includeSms,
          'phoneLabel': phoneLabel,
        }),
      );

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  bool get hasAnySource => accounts.isNotEmpty || verified.isNotEmpty || (includeSms && SmsSource.supported);

  Future<void> addAccount(ImapAccount a) async {
    accounts.removeWhere((x) => x.address.toLowerCase() == a.address.toLowerCase());
    accounts.add(a);
    await _changed();
  }

  Future<void> removeAccount(ImapAccount a) async {
    accounts.remove(a);
    await _changed();
  }

  Future<void> removeVerified(String address) async {
    verified.remove(address);
    await _changed();
  }

  Future<void> setSmtp(SmtpConfig? cfg) async {
    smtp = cfg;
    await _changed();
  }

  Future<void> setHibpKey(String? key) async {
    hibpKey = (key == null || key.trim().isEmpty) ? null : key.trim();
    await _changed();
  }

  Future<void> setSms({bool? include, String? label}) async {
    if (include != null) includeSms = include;
    if (label != null) phoneLabel = label.trim();
    await _changed();
  }

  /// Kod gönderir. Hata mesajı döner; başarılıysa null.
  Future<String?> sendOtp(String address) async {
    final a = address.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(a)) return 'Geçerli bir e-posta adresi girin.';
    final cfg = smtp;
    if (cfg == null) return 'Önce Ayarlar\'dan kod gönderecek e-posta hesabını girin.';
    try {
      await otp.issue(a, cfg);
      return null;
    } on SmtpException catch (e) {
      return e.message;
    } on Exception catch (e) {
      return 'Kod gönderilemedi: $e';
    }
  }

  Future<({bool ok, String message})> checkOtp(String address, String code) async {
    final r = otp.check(address, code);
    if (r.ok) {
      final a = address.trim().toLowerCase();
      if (!verified.contains(a)) verified.add(a);
      await _changed();
    }
    return r;
  }

  Future<int> checkPassword(String password) => _hibp.pwnedPasswordCount(password);

  Future<void> startScan({DateTime? since, bool useHibp = true}) async {
    if (status == ScanStatus.running) return;
    status = ScanStatus.running;
    log.clear();
    notifyListeners();
    void say(String m) {
      log.add(m);
      notifyListeners();
    }

    try {
      List<SmsMessage>? messages;
      if (includeSms && SmsSource.supported) {
        if (await _sms.requestPermission()) {
          say('[sms] gelen kutusu okunuyor…');
          messages = await _sms.readInbox(since: since);
        } else {
          say('  ! SMS izni verilmedi; SMS taraması atlandı.');
        }
      }
      result = await runScan(
        imapAccounts: List.of(accounts),
        otpVerified: List.of(verified),
        smsMessages: messages,
        phoneLabel: phoneLabel.isEmpty ? 'Bu telefon' : phoneLabel,
        since: since,
        hibpKey: useHibp ? hibpKey : null,
        hibp: _hibp,
        log: say,
      );
      status = ScanStatus.done;
    } catch (e) {
      say('! Tarama durdu: $e');
      status = ScanStatus.failed;
    }
    notifyListeners();
  }

  String resultJson() => const JsonEncoder.withIndent('  ').convert(result?.toJson());

  Future<void> wipeAll() async {
    accounts.clear();
    verified.clear();
    smtp = null;
    hibpKey = null;
    phoneLabel = '';
    result = null;
    log.clear();
    status = ScanStatus.idle;
    notifyListeners();
    await _store.write(_key, null);
  }
}
