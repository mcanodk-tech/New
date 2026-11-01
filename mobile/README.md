# ayakizi — mobil uygulama (Flutter)

Kendi e-posta kutunuzu ve (Android'de) telefonunuzun SMS gelen kutusunu tarayarak
hangi uygulamalarda hesabınız olduğunu, hangilerini sildiğinizi ve hangi veri
sızıntılarında geçtiğinizi gösterir. Her şey cihazda çalışır.

## APK'yı indirme

Her `mobile/` değişikliğinde GitHub Actions APK üretir:
**Actions → mobile → son çalışma → Artifacts → `ayakizi-apk`**. ZIP'i açıp
`app-release.apk` dosyasını telefona kurun (Ayarlar'da "bilinmeyen kaynaklar"a
izin vermeniz gerekir).

## Kendiniz derlemek

```bash
cd mobile
./tool/setup.sh            # android/ ve ios/ klasörlerini üretir
flutter test
flutter build apk --release
```

iOS için macOS + Xcode gerekir: `flutter build ios`. iPhone uygulamaların SMS
okumasına izin vermediği için iOS'ta yalnızca e-posta tarafı çalışır.

## Notlar

* SMS okuma (`READ_SMS`) izni Google Play'de yalnızca varsayılan SMS
  uygulamalarına verilir; bu uygulama Play Store'a değil, doğrudan APK ile
  kurulmak üzere tasarlanmıştır.
* Şifreler ve API anahtarları Android Keystore / iOS Keychain ile şifrelenerek
  saklanır; "Ayarlar → Bu cihazdaki tüm verileri sil" ile temizlenir.
* Çekirdek mantık (`lib/core/`) Python sürümündeki (`../ayakizi/`) ile aynıdır.
