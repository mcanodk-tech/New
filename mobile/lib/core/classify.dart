/// Mesaj konusu / SMS gövdesinden hesap olayı türünü çıkarır (TR + EN).
library;

enum EventType { deletion, signup, passwordReset, security, other }

const Map<EventType, String> eventLabels = {
  EventType.signup: 'Kayıt / hoş geldiniz',
  EventType.deletion: 'Hesap silme / kapatma',
  EventType.passwordReset: 'Şifre sıfırlama',
  EventType.security: 'Giriş / doğrulama kodu',
  EventType.other: 'Diğer',
};

/// Türkçe karakterleri ASCII'ye indirger ve küçük harfe çevirir; böylece
/// "HESABINIZ SİLİNDİ", "hesabınız silindi" ve "hesabiniz silindi" aynı eşleşir.
String normalize(String text) {
  const map = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g',
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c', '̇': '',
  };
  final b = StringBuffer();
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch);
  }
  return b.toString().toLowerCase();
}

final Map<EventType, List<RegExp>> _patterns = {
  EventType.deletion: _re([
    r'account (has been |was |is being )?(deleted|closed|deactivated|removed|terminated|cancell?ed)',
    r'(deleted|closed|deactivated) your account',
    r'(account|data) deletion',
    r'sorry to see you go',
    r'goodbye from',
    r'hesabiniz ?i?( basariyla)? (silindi|silinmistir|kapatildi|kapatilmistir|dondurul)',
    r'hesap (silme|kapatma)',
    r'uyeliginiz (sonlandirildi|iptal|silindi)',
  ]),
  EventType.signup: _re([
    r'welcome( to|,|!|\b)',
    r'(verify|confirm) your (e-?mail|email address|account|registration|sign-?up)',
    r'activate your account',
    r'account (has been |was )?created',
    r'thanks? (you )?for (signing up|joining|registering|creating)',
    r'complete your (registration|sign-?up|profile)',
    r"you('re| are) (in|registered)",
    r'hos ?geldin',
    r'hesabinizi? ?(olusturuldu|dogrula|onayla|aktif)',
    r'e-?posta adresinizi (dogrula|onayla)',
    r'uyeliginizi? ?(olusturuldu|basladi|onayla|tamamla|aktif)',
    r'kaydinizi? ?(tamamla|olusturuldu|alindi|onayla)',
    r'aramiza hos',
  ]),
  EventType.passwordReset: _re([
    r'(reset|change|recover) your password',
    r'password (reset|change|recovery)',
    r'forgot (your )?password',
    r'sifre(nizi)? ?(sifirla|yenile|degis|hatirlat)',
    r'parola(nizi)? ?(sifirla|yenile|degis)',
  ]),
  EventType.security: _re([
    r'new (sign-?in|login|device)',
    r'(security|login|sign-?in) (alert|code|notification)',
    r'(verification|confirmation|one-?time|security|login) (code|pin)',
    r'\b(otp|2fa|two-factor)\b',
    r'\bis your .{0,20}code\b',
    r'\bcode( is)?[: ]+\d{4,8}\b',
    r'\byour \w+( \w+)? code\b',
    r'giris (yapildi|kodu|uyarisi|bildirim)',
    r'(dogrulama|onay|guvenlik|tek kullanimlik) (kodu|sifre)',
    r'\bkod(unuz|u)?[: ]+\d{4,8}\b',
  ]),
};

List<RegExp> _re(List<String> ps) => [for (final p in ps) RegExp(p)];

/// Metni en yüksek öncelikli olay türüne sınıflar (silme > kayıt > şifre > güvenlik).
EventType classify(String text) {
  if (text.isEmpty) return EventType.other;
  final t = normalize(text);
  for (final entry in _patterns.entries) {
    if (entry.value.any((p) => p.hasMatch(t))) return entry.key;
  }
  return EventType.other;
}
