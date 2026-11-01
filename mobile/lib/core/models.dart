import 'classify.dart';
import 'services.dart';

class AccountEvent {
  AccountEvent({
    required this.source,
    required this.account,
    required this.sender,
    required this.subject,
    required this.date,
    required this.type,
    required this.service,
    required this.category,
    required this.known,
  });

  final String source; // 'email' | 'sms'
  final String account; // taranan adres veya telefon
  final String sender;
  final String subject;
  final DateTime? date;
  final EventType type;
  final String service;
  final String category;
  final bool known;

  Map<String, Object?> toJson() => {
        'source': source,
        'account': account,
        'sender': sender,
        'subject': subject,
        'date': date?.toIso8601String(),
        'event_type': type.name,
        'service': service,
        'category': category,
        'known': known,
      };
}

({String service, String category, bool known}) resolveEmailService(String senderDomain) {
  final svc = matchDomain(senderDomain);
  if (svc != null) return (service: svc.name, category: svc.category, known: true);
  final reg = registrableDomain(senderDomain);
  return (service: reg.isEmpty ? senderDomain : reg, category: 'other', known: false);
}

({String service, String category, bool known}) resolveSmsService(String sender, String body) {
  final svc = matchText('$sender $body');
  if (svc != null) return (service: svc.name, category: svc.category, known: true);
  final s = sender.trim();
  return (service: s.isEmpty ? '?' : s, category: 'other', known: false);
}

enum AccountStatus { active, dormant, deleted }

const Map<AccountStatus, String> statusLabels = {
  AccountStatus.deleted: 'Silinmiş olabilir',
  AccountStatus.active: 'Aktif olabilir (son 1 yıl)',
  AccountStatus.dormant: 'Eski / kullanılmıyor',
};

class AccountRecord {
  AccountRecord(this.service, this.category, this.known);

  final String service;
  final String category;
  final bool known;
  final Set<String> accounts = {};
  final Set<String> sources = {};
  final Map<EventType, int> counts = {};
  final List<String> samples = [];
  DateTime? firstSeen;
  DateTime? lastSeen;
  DateTime? lastDeletion;
  DateTime? lastNonDeletion;

  void add(AccountEvent ev) {
    accounts.add(ev.account);
    sources.add(ev.source);
    counts[ev.type] = (counts[ev.type] ?? 0) + 1;
    final d = ev.date;
    if (d != null) {
      if (firstSeen == null || d.isBefore(firstSeen!)) firstSeen = d;
      if (lastSeen == null || d.isAfter(lastSeen!)) lastSeen = d;
      if (ev.type == EventType.deletion) {
        if (lastDeletion == null || d.isAfter(lastDeletion!)) lastDeletion = d;
      } else if (lastNonDeletion == null || d.isAfter(lastNonDeletion!)) {
        lastNonDeletion = d;
      }
    }
    if (ev.type != EventType.other && ev.subject.isNotEmpty && samples.length < 3) {
      samples.add(ev.subject.length > 160 ? ev.subject.substring(0, 160) : ev.subject);
    }
  }

  AccountStatus status([DateTime? now]) {
    now ??= DateTime.now().toUtc();
    if ((counts[EventType.deletion] ?? 0) > 0) {
      if (lastDeletion == null ||
          lastNonDeletion == null ||
          !lastDeletion!.isBefore(lastNonDeletion!)) {
        return AccountStatus.deleted;
      }
    }
    if (lastSeen != null && now.difference(lastSeen!) <= const Duration(days: 365)) {
      return AccountStatus.active;
    }
    return AccountStatus.dormant;
  }

  Map<String, Object?> toJson([DateTime? now]) => {
        'service': service,
        'category': category,
        'known_service': known,
        'status': status(now).name,
        'first_seen': firstSeen?.toIso8601String(),
        'last_seen': lastSeen?.toIso8601String(),
        'event_counts': {for (final e in counts.entries) e.key.name: e.value},
        'linked_identities': accounts.toList()..sort(),
        'sources': sources.toList()..sort(),
        'sample_subjects': samples,
      };
}

/// Olayları servis bazında birleştirir. Katalog dışındaki göndericiler yalnızca
/// hesap olayı (kayıt, silme, şifre, güvenlik) içeriyorsa dahil edilir.
List<AccountRecord> buildInventory(List<AccountEvent> events) {
  final records = <String, AccountRecord>{};
  for (final ev in events) {
    if (!ev.known && ev.type == EventType.other) continue;
    final key = ev.service.toLowerCase();
    records.putIfAbsent(key, () => AccountRecord(ev.service, ev.category, ev.known)).add(ev);
  }
  final list = records.values.toList()
    ..sort((a, b) {
      int idx(String c) {
        final i = categoryOrder.indexOf(c);
        return i < 0 ? 99 : i;
      }

      final c = idx(a.category).compareTo(idx(b.category));
      return c != 0 ? c : a.service.toLowerCase().compareTo(b.service.toLowerCase());
    });
  return list;
}
