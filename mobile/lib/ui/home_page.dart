import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/imap.dart';
import 'add_email_sheet.dart';
import 'common.dart';
import 'password_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime? _since;
  bool _useHibp = true;

  AppState get s => widget.state;

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _pickSince() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _since ?? DateTime(now.year - 3),
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Bu tarihten sonraki mesajlar',
    );
    if (d != null) setState(() => _since = d);
  }

  Future<void> _importSms(BuildContext context) async {
    final ctrl = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS yedeği içe aktar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yedeğin ait olduğu kendi numaranızı girin; ardından XML dosyasını seçin.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numaranız',
                hintText: '+905551112233',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Dosya seç')),
        ],
      ),
    );
    if (phone == null) return;
    final err = await s.importSms(phone);
    if (err != null && context.mounted) toast(context, err);
  }

  void _startScan() {
    s.startScan(since: _since, useHibp: _useHibp && s.hibpKey != null);
    _open(ScanPage(state: s));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ayakizi'),
        actions: [
          IconButton(
            tooltip: 'Şifre sızıntı kontrolü',
            icon: const Icon(Icons.password),
            onPressed: () => _open(PasswordPage(state: s)),
          ),
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(SettingsPage(state: s)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          if (!s.loaded) return const Center(child: CircularProgressIndicator());
          final theme = Theme.of(context);
          final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Kendi e-posta kutunuzu ve SMS\'lerinizi tarayarak hangi uygulamalarda '
                  'hesabınız olduğunu, hangilerini sildiğinizi ve hangi sızıntılarda '
                  'geçtiğinizi gösterir. Her şey bu cihazda çalışır.',
                  style: muted,
                ),
              ),
              SectionCard(
                title: 'E-posta adresleri',
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ekle'),
                  onPressed: () => showAddEmailSheet(context, s),
                ),
                children: [
                  if (s.accounts.isEmpty && s.verified.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Henüz adres eklenmedi.', style: muted),
                    ),
                  for (final a in s.accounts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mail_outline),
                      title: Text(a.address),
                      subtitle: Text('Posta kutusu taranır · ${a.host.isEmpty ? guessImapHost(a.address) : a.host}'),
                      trailing: IconButton(
                        tooltip: 'Kaldır',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(context, 'Adres kaldırılsın mı?',
                              '${a.address} ve kayıtlı uygulama şifresi bu cihazdan silinir.')) {
                            await s.removeAccount(a);
                          }
                        },
                      ),
                    ),
                  for (final v in s.verified)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_outlined),
                      title: Text(v),
                      subtitle: const Text('Kodla doğrulandı · yalnızca sızıntı kontrolü'),
                      trailing: IconButton(
                        tooltip: 'Kaldır',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => s.removeVerified(v),
                      ),
                    ),
                ],
              ),
              SectionCard(
                title: 'Telefon numaraları (SMS yedeği)',
                hint: 'Numaranıza gelen doğrulama kodu SMS\'lerinden kayıtlı olduğu servisleri bulur. '
                    'Android\'de "SMS Backup & Restore" ile aldığınız XML yedeğini seçin. '
                    'Kodlar maskelenir, kişisel mesajlar saklanmaz; yedek yalnızca bellekte işlenir.',
                trailing: TextButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('İçe aktar'),
                  onPressed: () => _importSms(context),
                ),
                children: [
                  for (final b in s.smsBackups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sms_outlined),
                      title: Text(b.phone),
                      subtitle: Text('${b.fileName} · ${b.messages.length} mesaj'),
                      trailing: IconButton(
                        tooltip: 'Kaldır',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => s.removeSms(b),
                      ),
                    ),
                ],
              ),
              SectionCard(
                title: 'Tarama seçenekleri',
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Şu tarihten sonrası'),
                    subtitle: Text(_since == null ? 'Tüm geçmiş' : fmtDate(_since)),
                    trailing: _since == null
                        ? null
                        : IconButton(
                            tooltip: 'Temizle',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _since = null),
                          ),
                    onTap: _pickSince,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.shield_outlined),
                    title: const Text('Veri sızıntısı kontrolü'),
                    subtitle: Text(s.hibpKey == null
                        ? 'Ayarlar\'dan Have I Been Pwned anahtarı girin'
                        : 'Doğrulanmış adresler kontrol edilir'),
                    value: _useHibp && s.hibpKey != null,
                    onChanged: s.hibpKey == null ? null : (v) => setState(() => _useHibp = v),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.search),
                label: Text(s.status == ScanStatus.running ? 'Taranıyor…' : 'Taramayı başlat'),
                onPressed: !s.hasAnySource
                    ? null
                    : s.status == ScanStatus.running
                        ? () => _open(ScanPage(state: s))
                        : _startScan,
              ),
              if (s.result != null && s.status != ScanStatus.running)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Son sonuçları gör'),
                    onPressed: () => _open(ScanPage(state: s)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
