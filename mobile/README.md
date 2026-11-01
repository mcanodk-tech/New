# ayakizi — mobil uygulama (Flutter, Android + iOS)

Kendi e-posta kutunuzu ve seçtiğiniz SMS yedeğini tarayarak hangi uygulamalarda
hesabınız olduğunu, hangilerini sildiğinizi ve hangi veri sızıntılarında
geçtiğinizi gösterir. Her şey cihazda çalışır; uygulamanın sunucusu yoktur.

Mağaza yayını için hazırlandı:
* Hassas izin yok (SMS'e doğrudan erişmez; kullanıcı yedek dosyasını seçer).
* İlk açılışta belirgin açıklama ve onay ekranı.
* İmzalı AAB (Play) üretimi, iOS şifreleme beyanı, uygulama ikonları.

**Yayınlama adımları:** [`store/PUBLISHING.md`](store/PUBLISHING.md)
**Mağaza metinleri:** [`store/listing.md`](store/listing.md) ·
**Veri güvenliği cevapları:** [`store/data-safety.md`](store/data-safety.md) ·
**Gizlilik politikası:** [`../docs/privacy.html`](../docs/privacy.html)

## Derlenmiş paketler

Her `mobile/` değişikliğinde GitHub Actions testleri çalıştırır ve
**Actions → mobile → Artifacts → `ayakizi-android`** altında `app-release.aab`
(Play Store) ve `app-release.apk` (doğrudan kurulum) üretir.

## Kendiniz derlemek

```bash
cd mobile
./tool/setup.sh                 # android/ ve ios/ klasörlerini üretir, ikonları oluşturur
flutter test
flutter build appbundle --release   # Play Store
flutter build ipa --release         # App Store (macOS + Xcode)
```

## Yapı

* `lib/core/` — tarama çekirdeği (Python sürümü `../ayakizi/` ile aynı mantık):
  servis kataloğu, TR/EN sınıflandırıcı, IMAP (salt-okunur) ve SMTP
  istemcileri, Have I Been Pwned, SMS yedeği çözümleyici.
* `lib/ui/` — ekranlar. `lib/app_state.dart` — durum ve şifreli depolama.
* `overrides/` — `flutter create` çıktısının üzerine yazılan dosyalar;
  `tool/patch_platforms.py` imzalama ve iOS ayarlarını ekler.
* `store/` — mağaza metinleri, grafikler, örnek SMS yedeği, yayın rehberi.
