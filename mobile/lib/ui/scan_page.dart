import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/classify.dart';
import '../core/hibp.dart';
import '../core/models.dart';
import '../core/scanner.dart';
import '../core/services.dart';
import '../core/templates.dart';
import 'common.dart';

class ScanPage extends StatelessWidget {
  const ScanPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final result = state.result;
        final running = state.status == ScanStatus.running;
        return Scaffold(
          appBar: AppBar(
            title: Text(running ? 'Taranıyor…' : 'Sonuçlar'),
            actions: [
              if (!running && result != null)
                IconButton(
                  tooltip: 'Sonuçları JSON olarak kopyala',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: state.resultJson()));
                    if (context.mounted) toast(context, 'JSON panoya kopyalandı');
                  },
                ),
            ],
          ),
          body: running || result == null || state.status == ScanStatus.failed
              ? _LogView(state: state)
              : ResultsView(result: result),
        );
      },
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final running = state.status == ScanStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            reverse: true,
            itemCount: state.log.length,
            itemBuilder: (_, i) {
              final line = state.log[state.log.length - 1 - i];
              return Text(
                line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: line.trimLeft().startsWith('!') ? Theme.of(context).colorScheme.error : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final inv = result.inventory;
    final now = result.finishedAt;
    final theme = Theme.of(context);
    final stats = [
      (inv.length, 'hesap'),
      (inv.where((r) => r.category == 'dating').length, 'arkadaşlık'),
      (inv.where((r) => r.status(now) == AccountStatus.deleted).length, 'silinmiş'),
      (result.breaches.length, 'sızıntı'),
    ];
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final (n, label) in stats)
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.all(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        child: Column(
                          children: [
                            Text('$n', style: theme.textTheme.headlineSmall),
                            Text(label, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (result.errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(result.errors.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          TabBar(tabs: [
            Tab(text: 'Hesaplar (${inv.length})'),
            Tab(text: 'Sızıntılar (${result.breaches.length})'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _AccountsTab(result: result),
              _BreachesTab(breaches: result.breaches),
            ]),
          ),
        ],
      ),
    );
  }
}

class _AccountsTab extends StatefulWidget {
  const _AccountsTab({required this.result});

  final ScanResult result;

  @override
  State<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<_AccountsTab> {
  String _q = '';
  String? _cat;
  AccountStatus? _status;

  @override
  Widget build(BuildContext context) {
    final now = widget.result.finishedAt;
    final all = widget.result.inventory;
    final cats = <String>{for (final r in all) r.category}.toList()
      ..sort((a, b) => categoryOrder.indexOf(a).compareTo(categoryOrder.indexOf(b)));
    final rows = all.where((r) {
      if (_q.isNotEmpty && !r.service.toLowerCase().contains(_q.toLowerCase())) return false;
      if (_cat != null && r.category != _cat) return false;
      if (_status != null && r.status(now) != _status) return false;
      return true;
    }).toList();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Servis ara',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final st in AccountStatus.values)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilterChip(
                    label: Text(statusLabels[st]!.split(' (').first),
                    selected: _status == st,
                    onSelected: (v) => setState(() => _status = v ? st : null),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilterChip(
                    label: Text(categoryLabels[c] ?? c),
                    selected: _cat == c,
                    onSelected: (v) => setState(() => _cat = v ? c : null),
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Sonuç yok.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ),
        for (final r in rows)
          ListTile(
            title: Text(r.service, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${categoryLabels[r.category] ?? r.category} · son: ${fmtDate(r.lastSeen)}'
              '${r.known ? '' : ' · katalog dışı'}',
            ),
            trailing: StatusPill(r.status(now)),
            onTap: () => showAccountSheet(context, r, now),
          ),
      ],
    );
  }
}

Future<void> showAccountSheet(BuildContext context, AccountRecord r, DateTime now) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final identity = (r.accounts.toList()..sort()).join(', ');
      Widget row(String k, String v) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 120, child: Text(k, style: theme.textTheme.bodySmall)),
                Expanded(child: Text(v)),
              ],
            ),
          );
      Future<void> copy(String text, String what) async {
        await Clipboard.setData(ClipboardData(text: text));
        if (ctx.mounted) toast(ctx, '$what panoya kopyalandı');
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text(r.service, style: theme.textTheme.titleLarge)),
                StatusPill(r.status(now), short: false),
              ],
            ),
            const SizedBox(height: 12),
            row('Kategori', categoryLabels[r.category] ?? r.category),
            row('İlk görülme', fmtDate(r.firstSeen)),
            row('Son görülme', fmtDate(r.lastSeen)),
            row('Bağlı kimlik', identity),
            row('Kaynak', r.sources.map((s) => s == 'sms' ? 'SMS' : 'E-posta').join(', ')),
            row('Olaylar',
                r.counts.entries.map((e) => '${eventLabels[e.key]}: ${e.value}').join('\n')),
            if (r.samples.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Örnek bildirimler', style: theme.textTheme.titleSmall),
              for (final s in r.samples)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $s', style: theme.textTheme.bodySmall),
                ),
            ],
            const SizedBox(height: 20),
            Text('Bu hesabı kullanmıyorsanız', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Servisin gizlilik / KVKK iletişim adresine silme talebi gönderin.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('KVKK talebini kopyala'),
                  onPressed: () => copy(kvkkTemplate(r.service, identity), 'KVKK talebi'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('GDPR talebini kopyala'),
                  onPressed: () => copy(gdprTemplate(r.service, identity), 'GDPR talebi'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _BreachesTab extends StatelessWidget {
  const _BreachesTab({required this.breaches});

  final List<Breach> breaches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (breaches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Sızıntı bulunamadı ya da kontrol yapılmadı.\n\n'
          'Sızıntı kontrolü için Ayarlar\'a Have I Been Pwned anahtarı girin.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: breaches.length,
      itemBuilder: (_, i) {
        final b = breaches[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.title, style: theme.textTheme.titleMedium),
                Text('${b.domain.isEmpty ? '' : '${b.domain} · '}${b.breachDate} · ${b.account}',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text('Sızan veri: ${b.dataClasses.join(', ')}'),
              ],
            ),
          ),
        );
      },
    );
  }
}
