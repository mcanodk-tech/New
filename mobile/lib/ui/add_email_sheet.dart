import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/scanner.dart';
import 'common.dart';
import 'settings_page.dart';

Future<void> showAddEmailSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AddEmailSheet(state: state),
  );
}

class AddEmailSheet extends StatefulWidget {
  const AddEmailSheet({super.key, required this.state});

  final AppState state;

  @override
  State<AddEmailSheet> createState() => _AddEmailSheetState();
}

class _AddEmailSheetState extends State<AddEmailSheet> {
  int _mode = 0;
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _host = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _message;
  bool _messageOk = false;

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    _host.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _validAddress => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_address.text.trim());

  void _say(String? m, {bool ok = false}) => setState(() {
        _message = m;
        _messageOk = ok;
      });

  Future<void> _saveImap() async {
    if (!_validAddress) return _say('Geçerli bir e-posta adresi girin.');
    if (_password.text.isEmpty) return _say('Uygulama şifresini girin.');
    await widget.state.addAccount(ImapAccount(
      address: _address.text.trim(),
      password: _password.text,
      host: _host.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _sendCode() async {
    setState(() => _busy = true);
    final err = await widget.state.sendOtp(_address.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codeSent = err == null;
    });
    _say(err ?? 'Kod ${_address.text.trim()} adresine gönderildi. Spam klasörüne de bakın.', ok: err == null);
  }

  Future<void> _checkCode() async {
    final r = await widget.state.checkOtp(_address.text, _code.text);
    if (!mounted) return;
    if (r.ok) {
      toast(context, '${_address.text.trim()} doğrulandı');
      Navigator.pop(context);
    } else {
      _say(r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final noSmtp = widget.state.smtp == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('E-posta adresi ekle', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.inbox_outlined), label: Text('Posta kutusu')),
                ButtonSegment(value: 1, icon: Icon(Icons.pin_outlined), label: Text('Kodla doğrula')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _message = null;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == 0
                  ? 'Önerilen. Posta kutunuz salt-okunur taranır (yalnızca başlıklar); '
                      'kayıtlı ve silinmiş hesaplar bildirimlerden çıkarılır.'
                  : 'Giriş yapamadığınız adresler için: adrese 6 haneli kod gönderilir, '
                      'doğrulanırsa sızıntı kontrolüne dahil edilir.',
              style: muted,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enabled: !_codeSent,
              decoration: const InputDecoration(labelText: 'E-posta adresi', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (_mode == 0) ...[
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Uygulama şifresi', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _host,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'IMAP sunucusu (isteğe bağlı)',
                  hintText: 'otomatik',
                  border: OutlineInputBorder(),
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Uygulama şifresi nasıl alınır?'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gmail: Google Hesabı → Güvenlik → 2 Adımlı Doğrulama → Uygulama şifreleri.\n'
                    'Outlook/Hotmail: Microsoft hesabı → Güvenlik → Gelişmiş güvenlik → Uygulama parolası.\n'
                    'iCloud: appleid.apple.com → Uygulamaya özel parolalar.\n\n'
                    'Şifre bu cihazın şifreli deposunda saklanır.',
                    style: muted,
                  ),
                ],
              ),
              FilledButton(onPressed: _saveImap, child: const Text('Kaydet')),
            ] else ...[
              if (noSmtp) ...[
                Text('Kod göndermek için önce Ayarlar\'da gönderen e-posta hesabını girin.',
                    style: muted),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(state: widget.state),
                  )).then((_) => setState(() {})),
                  child: const Text('Ayarları aç'),
                ),
              ] else if (!_codeSent)
                FilledButton(
                  onPressed: _busy ? null : _sendCode,
                  child: Text(_busy ? 'Gönderiliyor…' : 'Kod gönder'),
                )
              else ...[
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 7,
                  decoration: const InputDecoration(labelText: 'Gelen 6 haneli kod', border: OutlineInputBorder()),
                  onSubmitted: (_) => _checkCode(),
                ),
                FilledButton(onPressed: _checkCode, child: const Text('Doğrula')),
                TextButton(
                  onPressed: () => setState(() {
                    _codeSent = false;
                    _message = null;
                  }),
                  child: const Text('Adresi değiştir / yeniden gönder'),
                ),
              ],
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message!,
                  style: TextStyle(color: _messageOk ? Colors.green.shade600 : theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
