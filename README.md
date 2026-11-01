# ayakizi — kişisel dijital ayak izi denetimi

Kendi e-posta adresinizin ve telefon numaranızın **hangi uygulama ve sitelerde
kayıtlı olduğunu** (arkadaşlık uygulamaları dahil), **hangi hesapları sildiğinizi**
ve **hangi veri sızıntılarında geçtiğinizi** çıkaran, tamamen yerel çalışan bir araç.

## Nasıl çalışır?

Bir servise kayıt olduğunuzda, hesabınızı sildiğinizde, şifre sıfırladığınızda veya
giriş yaptığınızda o servis size e-posta / SMS gönderir. `ayakizi` bu izleri
**kendi** posta kutunuzda ve SMS yedeğinizde arar:

| Kaynak | Ne bulur |
|---|---|
| E-posta kutunuz (IMAP, salt-okunur, yalnızca başlıklar) | "Tinder'a hoş geldiniz", "Hesabınız silindi", "Şifrenizi sıfırlayın" gibi mesajlardan servis listesi, ilk/son kullanım tarihi, silinmiş hesaplar |
| Android SMS yedeğiniz | "Your Bumble code is…" gibi doğrulama kodu SMS'lerinden numaranızın kayıtlı olduğu servisler |
| Have I Been Pwned | Doğrulanmış adreslerinizin geçtiği veri sızıntıları ve sızan veri türleri |
| Pwned Passwords | Bir şifrenin sızıntılarda olup olmadığı (k-anonimlik) |

Katalogda ~100 servis var (Tinder, Bumble, Hinge, Badoo, Grindr, Instagram,
Trendyol, Hepsiburada, Getir, Papara, Steam…). Katalog dışındaki servisler de
"hoş geldiniz / hesabınız silindi" gibi mesajlardan alan adına göre yakalanır.

### Tasarım gereği sınırlar

* **Yalnızca sahibi olduğunuz kaynaklar taranır.** E-posta için IMAP'e giriş
  yapabilmeniz gerekir; sızıntı kontrolü de sadece girişi başarılı olan adreslere
  yapılır. Rastgele bir e-posta/numara sorgulama özelliği yoktur ve eklenmeyecektir.
* Hiçbir servise (Tinder vb.) istek atılmaz, hesap varlığı dışarıdan yoklanmaz.
* Mesaj gövdeleri indirilmez; mesajlar okunmuş olarak işaretlenmez.
* SMS'lerdeki doğrulama kodları rapora yazılmaz; kişisel SMS'ler hiç kaydedilmez.
* Bildirim e-postasını sildiyseniz o hesap görünmez; "durum" sütunu bir tahmindir.

## Kurulum

Python 3.9+; dış bağımlılık yok.

```bash
pip install .          # ya da doğrudan: python -m ayakizi ...
```

## Kullanım

```bash
# Gmail / Outlook için normal şifre değil "uygulama şifresi" kullanın
ayakizi scan --imap ben@gmail.com

# Birden çok adres + SMS yedeği + sızıntı kontrolü
export HIBP_API_KEY=...            # https://haveibeenpwned.com/API/Key
ayakizi scan --imap ben@gmail.com --imap eski@hotmail.com \
             --sms sms-yedek.xml --phone +905551112233 --hibp

# Belirli tarihten sonrası / belirli sunucu
ayakizi scan --imap ben@firma.com.tr --imap-host mail.firma.com.tr --since 2018-01-01

# Şifre sızıntı kontrolü
ayakizi password
```

### Elinizde OTP'si olan adresler ve numaralar

**E-posta (IMAP erişimi olmayan adresler):** `--verify-email` adrese 6 haneli bir
kod gönderir. Kod doğru girilirse (10 dakika, 3 deneme) adres doğrulanmış sayılır
ve `--hibp` ile sızıntı kontrolüne dahil edilir. Kod sizin SMTP hesabınızdan gider:

```bash
export AYAKIZI_SMTP_USER=ben@gmail.com AYAKIZI_SMTP_PASSWORD=<uygulama-şifresi>
export HIBP_API_KEY=...
ayakizi scan --verify-email ben@firma.com --verify-email takma-ad@ornek.com --hibp
```

IMAP girişi yapabildiğiniz adreslerde `--imap` tercih edin: hem doğrulama sayılır
hem de kutudaki kayıt/silme mesajlarından hesap envanteri çıkarılır. OTP ile
doğrulanan adreste ise yalnızca sızıntı kontrolü yapılır.

**Telefon:** Numaraya gelen SMS'ler zaten sizin cihazınızda olduğundan, kanıt
olarak SMS yedeği kullanılır. Birden çok numara için:

```bash
ayakizi scan --sms telefon1.xml=+905551112233 --sms telefon2.xml=+905554445566
```

Have I Been Pwned API'si telefon numarasıyla sorgu desteklemez; numaralar için
envanter SMS yedeğinden çıkarılır.

Çıktı `ayakizi-rapor/rapor.html` (görsel rapor + KVKK/GDPR silme talebi
şablonları) ve `ayakizi-rapor/rapor.json` dosyalarıdır.

### Uygulama şifresi

* **Gmail:** Google Hesabı → Güvenlik → 2 Adımlı Doğrulama → Uygulama şifreleri.
  IMAP'in Gmail ayarlarında açık olması gerekir.
* **Outlook/Hotmail:** Microsoft hesabı → Güvenlik → Gelişmiş güvenlik → Uygulama parolası.
* **iCloud:** appleid.apple.com → Uygulamaya özel parolalar.

Şifre ekrandan sorulur; tek adres taranıyorsa `AYAKIZI_IMAP_PASSWORD` ortam
değişkeniyle de verilebilir. Hiçbir yere kaydedilmez.

### SMS yedeği

Android'de "SMS Backup & Restore" uygulamasıyla XML yedeği alın ve bilgisayara
aktarın. (iPhone SMS'leri şu an desteklenmiyor.)

## Geliştirme

```bash
python -m unittest discover -s tests
```

Yeni servis eklemek için `ayakizi/services.py` içindeki `CATALOG` listesine
`_s("Ad", "kategori", "alanadi.com")` satırı ekleyin.
