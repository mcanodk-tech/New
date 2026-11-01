import 'package:flutter/material.dart';

import '../app_state.dart';

/// İlk açılışta gösterilen açıklama ve onay ekranı (mağazaların "belirgin
/// açıklama ve onay" şartı).
class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Text('ayakizi', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Dijital ayak izinizi görün, kullanmadığınız hesapları silin.',
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 28),
                  item(Icons.inbox_outlined, 'Kendi e-posta kutunuz',
                      'Eklediğiniz adreslere uygulama şifresiyle bağlanır ve yalnızca gönderen, '
                      'konu ve tarih başlıklarını okur. Mesaj içerikleri indirilmez, okunmuş '
                      'olarak işaretlenmez.'),
                  item(Icons.sms_outlined, 'Seçtiğiniz SMS yedeği',
                      'Uygulama SMS\'lerinize erişmez. Yalnızca sizin seçtiğiniz yedek dosyası '
                      'bellekte işlenir; doğrulama kodları maskelenir, kişisel mesajlar atılır.'),
                  item(Icons.phone_android, 'Her şey bu cihazda',
                      'Şifreler ve ayarlar cihazın şifreli deposunda tutulur. Sonuçlar hiçbir '
                      'sunucuya gönderilmez. Reklam ya da analiz aracı yoktur.'),
                  item(Icons.public, 'Dışarıya giden istekler',
                      'Yalnızca sizin bağlandığınız e-posta sunucusu, açarsanız Have I Been '
                      'Pwned (doğrulanmış adresleriniz için sızıntı kontrolü) ve Pwned '
                      'Passwords (şifrenin yalnızca özetinin ilk 5 karakteri).'),
                  item(Icons.verified_user_outlined, 'Yalnızca size ait hesaplar',
                      'Uygulama başkalarını sorgulamak için değildir: yalnızca giriş '
                      'yapabildiğiniz ya da koda erişebildiğiniz adresler taranır.'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: state.acceptConsent,
                child: const Text('Anladım, devam et'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
