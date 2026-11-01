import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/smtp.dart';
import 'common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _user = TextEditingController(text: widget.state.smtp?.user ?? '');
  late final _pass = TextEditingController(text: widget.state.smtp?.password ?? '');
  late final _host = TextEditingController(text: widget.state.smtp?.host ?? '');
  late final _port = TextEditingController(text: widget.state.smtp?.port.toString() ?? '');
  late final _hibp = TextEditingController(text: widget.state.hibpKey ?? '');

  @override
  void dispose() {
    for (final c in [_user, _pass, _host, _port, _hibp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final user = _user.text.trim();
    if (user.isEmpty) {
      await widget.state.setSmtp(null);
    } else {
      if (!user.contains('@') || _pass.text.isEmpty) {
        toast(context, 'Gönderen adres ve uygulama şifresi gerekli.');
        return;
      }
      final port = int.tryParse(_port.text.trim());
      // Adres değiştiyse sunucuyu yeniden tahmin et.
      final sameUser = widget.state.smtp?.user == user;
      await widget.state.setSmtp(SmtpConfig.forUser(
        user,
        _pass.text,
        host: sameUser ? _host.text.trim() : null,
        port: sameUser ? port : null,
      ));
    }
    await widget.state.setHibpKey(_hibp.text);
    if (!mounted) return;
    toast(context, 'Kaydedildi');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bilgiler bu cihazın şifreli deposunda (Android Keystore / iOS Keychain) '
              'saklanır ve hiçbir sunucuya gönderilmez.', style: muted),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Kod gönderecek e-posta hesabı',
            hint: 'Kodla doğrulamada kod bu hesaptan gönderilir. Gmail için uygulama şifresi kullanın.',
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _user,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Adres', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Uygulama şifresi', border: OutlineInputBorder()),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Gelişmiş (SMTP sunucusu)'),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _host,
                          autocorrect: false,
                          decoration: const InputDecoration(
                              labelText: 'Sunucu', hintText: 'otomatik', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
          SectionCard(
            title: 'Have I Been Pwned API anahtarı',
            hint: 'Sızıntı kontrolü için gerekli (haveibeenpwned.com/API/Key, ücretli).',
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _hibp,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'API anahtarı', border: OutlineInputBorder()),
              ),
            ],
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _save,
            child: const Text('Kaydet'),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Bu cihazdaki tüm verileri sil'),
            onPressed: () async {
              if (await confirm(context, 'Tüm veriler silinsin mi?',
                  'Kayıtlı adresler, şifreler, anahtarlar ve sonuçlar bu cihazdan silinir.')) {
                await widget.state.wipeAll();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
