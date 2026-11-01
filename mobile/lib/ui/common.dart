import 'package:flutter/material.dart';

import '../core/models.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing, this.hint});

  final String title;
  final String? hint;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (trailing != null) trailing!,
              ],
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(hint!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

Color statusColor(BuildContext context, AccountStatus s) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (s) {
    AccountStatus.deleted => Theme.of(context).colorScheme.error,
    AccountStatus.active => dark ? Colors.green.shade300 : Colors.green.shade700,
    AccountStatus.dormant => dark ? Colors.orange.shade300 : Colors.orange.shade800,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.short = true});

  final AccountStatus status;
  final bool short;

  static const _short = {
    AccountStatus.deleted: 'Silinmiş',
    AccountStatus.active: 'Aktif',
    AccountStatus.dormant: 'Eski',
  };

  @override
  Widget build(BuildContext context) {
    final c = statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(short ? _short[status]! : statusLabels[status]!,
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Sil'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
