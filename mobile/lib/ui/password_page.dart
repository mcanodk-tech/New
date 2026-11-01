import 'package:flutter/material.dart';

import '../app_state.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key, required this.state});

  final AppState state;

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _result;
  bool _bad = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_pw.text.isEmpty) return;
    setState(() => _busy = true);
    String msg;
    var bad = false;
    try {
      final n = await widget.state.checkPassword(_pw.text);
      bad = n > 0;
      msg = bad
          ? 'Bu şifre sızıntılarda $n kez görülmüş. Kullandığınız her yerde değiştirin.'
          : 'Bu şifre bilinen sızıntılarda bulunamadı.';
    } catch (e) {
      msg = 'Kontrol edilemedi: $e';
      bad = true;
    }
    _pw.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = msg;
      _bad = bad;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre sızıntı kontrolü')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Şifreniz gönderilmez: yalnızca SHA-1 özetinin ilk 5 karakteri Pwned Passwords '
            'servisine sorulur, eşleşme cihazda yapılır.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder()),
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: Text(_busy ? 'Kontrol ediliyor…' : 'Kontrol et'),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _result!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _bad ? theme.colorScheme.error : Colors.green.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
