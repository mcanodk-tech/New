# Mağazada yayınlama rehberi

Kod tarafı hazır; aşağıdaki adımlar hesap sahibinin (sizin) yapması gereken
işlerdir. Sıra önemlidir.

## 0. Bir kez yapılacaklar

1. **Gizlilik politikası adresi:** `docs/privacy.html` içindeki
   `ILETISIM_EPOSTASI` yazan iki yeri kendi iletişim adresinizle değiştirin.
   Sonra GitHub → **Settings → Pages → Branch: `main`, klasör: `/docs`**.
   Adres şöyle olur: `https://<kullanıcı>.github.io/<repo>/privacy.html`.
   (Repo gizliyse Pages ücretli plan ister; o durumda sayfayı herhangi bir
   statik barındırmaya koyabilirsiniz.)
2. **Uygulama kimliği:** Şu an `com.ayakizi.ayakizi`. Mağazaya ilk
   yüklemeden sonra **değiştirilemez**. Kendi alan adınıza göre değiştirmek
   isterseniz `tool/setup.sh` içindeki `--org` ve `--project-name`
   değerlerini ve `overrides/` altındaki yolları güncelleyin.

## 1. Google Play

### Hesap
- https://play.google.com/console → geliştirici hesabı (tek seferlik 25 USD,
  kimlik doğrulaması birkaç gün sürebilir).
- **Önemli:** 2023 sonrasında açılan *kişisel* hesaplarda üretime çıkmadan önce
  **en az 12 test kullanıcısıyla 14 gün kapalı test** zorunludur. Kuruluş
  hesaplarında bu şart yoktur.

### Yükleme anahtarı (bir kez)
```bash
cd mobile
./tool/make_upload_key.sh            # ~/ayakizi-upload-keystore.jks oluşturur
```
Betiğin yazdırdığı üç değeri GitHub → **Settings → Secrets and variables →
Actions** altına ekleyin: `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`. Anahtar dosyasını ve şifreyi
bir parola yöneticisinde yedekleyin.

### Paket
- Sırlar eklendikten sonra `mobile/` altında yapılan her değişiklikte (veya
  **Actions → mobile → Run workflow**) imzalı paket üretilir.
- **Actions → son çalışma → Artifacts → `ayakizi-android`** içindeki
  `app-release.aab` mağaza paketidir. Sürüm kodu (versionCode) her derlemede
  otomatik artar.
- Sırlar yoksa iş akışı uyarı verir ve paket hata ayıklama anahtarıyla imzalanır;
  bu paket Play Console'a **yüklenemez**.

### Play Console'da
1. **Uygulama oluştur** → ad: *ayakizi – Dijital Ayak İzi*, varsayılan dil
   Türkçe, Uygulama, Ücretsiz.
2. **Uygulama içeriği** (sol menü) → her başlığı `data-safety.md` ve
   `listing.md` içindeki cevaplarla doldurun: Gizlilik politikası adresi,
   Uygulama erişimi (test hesabı), Reklamlar (yok), İçerik derecelendirmesi,
   Hedef kitle (18+), Veri güvenliği.
3. **Mağaza girişi** → metinler `listing.md`, ikon
   `graphics/play-icon-512.png`, öne çıkan görsel
   `graphics/feature-graphic-1024x500.png`, en az 2 ekran görüntüsü.
4. **Test → Kapalı test** → yeni sürüm → `app-release.aab` yükleyin. İlk
   yüklemede **Play App Signing**'i kabul edin (Google kendi uygulama imzalama
   anahtarını tutar; sizinki yalnızca yükleme anahtarıdır).
5. Test kullanıcılarını ekleyin. Kişisel hesapsa 14 gün bekleyin.
6. **Üretim** → sürümü üretime taşı → incelemeye gönder (genelde 1–7 gün).

## 2. App Store

### Gerekenler
- Apple Developer Program üyeliği (yıllık 99 USD).
- Xcode yüklü bir Mac **ya da** Mac olmadan bulut derleme (ör. Codemagic,
  Xcode Cloud, ya da imza sertifikalarıyla GitHub Actions macOS).

### Mac ile
```bash
cd mobile
./tool/setup.sh
open ios/Runner.xcworkspace
```
1. Xcode → Runner → **Signing & Capabilities** → Team: kendi ekibiniz.
   Bundle Identifier: `com.ayakizi.ayakizi` (ya da sizin seçtiğiniz).
2. https://appstoreconnect.apple.com → **Uygulamalar → +** → aynı bundle ID.
3. `flutter build ipa --release` → `build/ios/ipa/*.ipa` dosyasını
   **Transporter** uygulamasıyla yükleyin (ya da Xcode → Product → Archive →
   Distribute).
4. App Store Connect'te: metinler (`listing.md`), ekran görüntüleri, gizlilik
   politikası adresi, **App Privacy** (`data-safety.md`), App Review notları ve
   test hesabı → **İncelemeye gönder**.

İmzasız bir iOS derlemesiyle kodun derlendiğini kontrol etmek için:
**Actions → mobile → Run workflow → "iOS derlemesini de çalıştır"** (macOS
dakikası harcar).

## 3. Bilinen inceleme riskleri ve cevaplar

| Risk | Durum |
|---|---|
| Play SMS/Arama Kaydı izinleri politikası | `READ_SMS` kaldırıldı; SMS yalnızca kullanıcının seçtiği dosyadan okunuyor. |
| Kimlik bilgisi isteyen uygulamalar | İlk açılışta belirgin açıklama + onay ekranı var; şifreler yalnızca kullanıcının kendi posta sunucusuna gidiyor. |
| "Gözetleme/izleme" (stalkerware) politikası | Uygulama yalnızca kullanıcının giriş yapabildiği ya da koda erişebildiği adresleri tarıyor; başkası sorgulanamıyor. Mağaza metinlerinde bu açıkça yazıyor. |
| İnceleme ekibinin uygulamayı deneyememesi | Test e-posta hesabı + `sample-sms-backup.xml` verin. |
| Gmail/Outlook uygulama şifresi | Outlook.com'da Microsoft temel kimlik doğrulamasını kısıtlıyor; inceleme hesabı olarak Gmail kullanın. |

## 4. Güncelleme yayınlamak

1. `mobile/pubspec.yaml` içindeki `version: 1.0.0+1` satırında **ilk kısmı**
   artırın (ör. `1.0.1`). Derleme numarası CI'da otomatik artar.
2. Değişikliği gönderin → CI imzalı `app-release.aab` üretir.
3. Play Console → Üretim → Yeni sürüm → yükle. iOS'ta `flutter build ipa` ve
   Transporter.
