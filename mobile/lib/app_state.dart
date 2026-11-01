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

typedef SmsPicker = Future<SmsBackup?> Function(String phone);

class AppState extends ChangeNotifier {
  AppState({KeyValueStore? store, OtpStore? otp, SmsPicker? smsPicker, HibpClient? hibp})
      : _store = store ?? SecureKeyValueStore(),
        otp = otp ?? OtpStore(),
        _pickSms = smsPicker ?? pickSmsBackup,
        _hibp = hibp ?? HibpClient();

  static const _key = 'ayakizi_state_v1';

  final KeyValueStore _store;
  final OtpStore otp;
  final SmsPicker _pickSms;
  final HibpClient _hibp;

  final List<ImapAccount> accounts = [];
  final List<String> verified = [];
  SmtpConfig? smtp;
  String? hibpKey;
  /// İçe aktarılan SMS yedekleri yalnızca bellekte tutulur.
  final List<SmsBackup> smsBackups = [];
  bool consented = false;
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
        consented = (j['consented'] as bool?) ?? false;
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
          'consented': consented,
        }),
      );

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  bool get hasAnySource => accounts.isNotEmpty || verified.isNotEmpty || smsBackups.isNotEmpty;

  Future<void> acceptConsent() async {
    consented = true;
    await _changed();
  }

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

  /// SMS yedeği seçtirip içe aktarır. Hata mesajı döner; vazgeçilirse ya da
  /// başarılıysa null.
  Future<String?> importSms(String phone) async {
    final p = phone.replaceAll(' ', '');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(p)) return 'Numarayı +905551112233 biçiminde girin.';
    try {
      final b = await _pickSms(p);
      if (b == null) return null;
      smsBackups.add(b);
      notifyListeners();
      return null;
    } on SmsBackupException catch (e) {
      return e.message;
    } on Exception catch (e) {
      return 'Dosya okunamadı: $e';
    }
  }

  void removeSms(SmsBackup b) {
    smsBackups.remove(b);
    notifyListeners();
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
      result = await runScan(
        imapAccounts: List.of(accounts),
        otpVerified: List.of(verified),
        smsBackups: [
          for (final b in smsBackups)
            SmsBackup(
              phone: b.phone,
              fileName: b.fileName,
              messages: since == null
                  ? b.messages
                  : [for (final m in b.messages) if (m.date == null || !m.date!.isBefore(since)) m],
            ),
        ],
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
    smsBackups.clear();
    consented = false;
    result = null;
    log.clear();
    status = ScanStatus.idle;
    notifyListeners();
    await _store.write(_key, null);
  }
}
