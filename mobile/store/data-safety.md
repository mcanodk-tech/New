# Veri güvenliği / gizlilik etiketi cevapları

Bu cevaplar uygulamanın bugünkü koduna göre hazırlandı. Formları gönderen siz
olduğunuz için son kontrol sizin sorumluluğunuzdadır; uygulamaya yeni bir SDK
(reklam, analiz, çökme raporu) eklerseniz cevaplar değişir.

Neden "Toplanan veri: e-posta adresi" işaretleniyor? Uygulamanın sunucusu yok,
ama sızıntı kontrolü açıkken e-posta adresi cihazdan Have I Been Pwned'e
gönderiliyor. İki mağaza da cihaz dışına giden veriyi, bir üçüncü tarafa gitse
bile "toplanan" sayıyor. En güvenli yol bunu beyan etmek.

## Google Play → Uygulama içeriği → Veri güvenliği

| Soru | Cevap |
|---|---|
| Uygulamanız gerekli kullanıcı veri türlerinden herhangi birini topluyor veya paylaşıyor mu? | **Evet** |
| Toplanan tüm kullanıcı verileri aktarım sırasında şifreleniyor mu? | **Evet** (TLS) |
| Kullanıcıların verilerinin silinmesini istemeleri için bir yol sağlıyor musunuz? | **Evet**: uygulama içinde "Bu cihazdaki tüm verileri sil"; sunucuda veri tutulmuyor |

**Veri türleri:**

| Kategori → Tür | Toplanıyor | Paylaşılıyor | Geçici işleme | Zorunlu mu | Amaç |
|---|---|---|---|---|---|
| Kişisel bilgiler → E-posta adresi | Evet | Hayır (kullanıcının başlattığı aktarım) | Hayır | İsteğe bağlı (yalnızca sızıntı kontrolü açıksa) | Uygulama işlevselliği |

Diğer hiçbir türü işaretlemeyin:
- **Kimlik bilgileri / şifreler:** E-posta uygulama şifresi yalnızca kullanıcının
  kendi posta sunucusuna, kullanıcının isteğiyle gider. Geliştiriciye ulaşmaz.
- **Mesajlar → SMS:** SMS yedeği yalnızca cihazda, bellekte işlenir; cihazdan
  çıkmaz.
- **Mesajlar → E-postalar:** Başlıklar yalnızca cihazda işlenir.

**Güvenlik uygulamaları:** Bağımsız güvenlik incelemesi → Hayır (yapılmadıysa).

## Google Play → Diğer beyanlar

- **Reklamlar:** Uygulama reklam içermiyor.
- **Uygulama erişimi:** "Tüm işlevler özel erişim gerektirmeden kullanılabilir"
  seçilemez, çünkü tarama için e-posta hesabı gerekiyor. "Bazı işlevler
  kısıtlı" seçin ve inceleme ekibi için **test e-posta hesabı + uygulama
  şifresi** verin (yalnızca bunun için açılmış bir Gmail hesabı; içine birkaç
  "hoş geldiniz" e-postası gelmiş olsun).
- **Hedef kitle:** 18+.
- **Haber uygulaması / COVID / finans / sağlık:** Hayır.
- **Hassas izinler:** Yok. (`READ_SMS` kullanılmıyor; Play'in SMS izni beyan
  formunu doldurmanız gerekmez.)

## App Store Connect → App Privacy

- **Veri topluyor musunuz?** → **Evet**
- **Contact Info → Email Address**
  - Kullanım: **App Functionality**
  - Kimliğe bağlı mı (Linked to the user)? → **Evet** (adresin kendisi)
  - İzleme (Tracking) için mi? → **Hayır**
- Başka kategori yok.

**App Review notları** (App Store Connect → App Review Information):

> Uygulama, kullanıcının kendi e-posta kutusundaki hesap bildirimlerini (yalnızca
> From/Subject/Date başlıkları, IMAP salt-okunur) cihaz üzerinde analiz eder.
> Sunucumuz yok. İnceleme için test hesabı: <adres> / uygulama şifresi:
> <şifre>. Ana sayfada "Ekle → Posta kutusu" ile ekleyip "Taramayı başlat"a
> dokunun. SMS yedeği içe aktarma isteğe bağlıdır; örnek dosya ekte.

**Şifreleme (Export Compliance):** Yalnızca işletim sisteminin standart TLS'i
kullanılıyor. `ITSAppUsesNonExemptEncryption = NO` Info.plist'e ekleniyor;
yükleme sırasında soru sorulmaz.
