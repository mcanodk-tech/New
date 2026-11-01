import 'dart:math';

import 'smtp.dart';

const Duration codeTtl = Duration(minutes: 10);
const int maxAttempts = 3;

typedef CodeSender = Future<void> Function(SmtpConfig cfg, String to, String code);

Future<void> sendCodeEmail(SmtpConfig cfg, String to, String code) => SmtpSender().send(
      cfg,
      to,
      'ayakizi doğrulama kodu: $code',
      'Bu adresin size ait olduğunu doğrulamak için kod: $code\n\n'
          'Kod ${codeTtl.inMinutes} dakika geçerlidir. Bu isteği siz yapmadıysanız '
          'bu e-postayı yok sayın.\n',
    );

String generateCode([Random? rnd]) =>
    (rnd ?? Random.secure()).nextInt(1000000).toString().padLeft(6, '0');

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

class _Pending {
  _Pending(this.code, this.deadline);
  final String code;
  final DateTime deadline;
  int attempts = 0;
}

/// İki adımlı e-posta sahipliği doğrulaması: [issue] kodu gönderir, [check] doğrular.
class OtpStore {
  OtpStore({CodeSender? sender, DateTime Function()? clock})
      : _sender = sender ?? sendCodeEmail,
        _clock = clock ?? DateTime.now;

  final CodeSender _sender;
  final DateTime Function() _clock;
  final Map<String, _Pending> _pending = {};

  Future<void> issue(String address, SmtpConfig cfg) async {
    final a = address.trim().toLowerCase();
    final code = generateCode();
    await _sender(cfg, a, code);
    _pending[a] = _Pending(code, _clock().add(codeTtl));
  }

  bool hasPending(String address) => _pending.containsKey(address.trim().toLowerCase());

  ({bool ok, String message}) check(String address, String entered) {
    final a = address.trim().toLowerCase();
    final p = _pending[a];
    if (p == null) return (ok: false, message: 'Bu adres için gönderilmiş bir kod yok.');
    if (_clock().isAfter(p.deadline)) {
      _pending.remove(a);
      return (ok: false, message: 'Kodun süresi doldu; yeniden gönderin.');
    }
    if (_constantTimeEquals(entered.replaceAll(' ', '').trim(), p.code)) {
      _pending.remove(a);
      return (ok: true, message: 'Doğrulandı.');
    }
    p.attempts++;
    if (p.attempts >= maxAttempts) {
      _pending.remove(a);
      return (ok: false, message: 'Deneme hakkı bitti; yeniden kod gönderin.');
    }
    return (ok: false, message: 'Kod hatalı (${maxAttempts - p.attempts} deneme kaldı).');
  }
}
