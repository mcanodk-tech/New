from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from .classify import DELETION, OTHER
from .services import Service, match_domain, match_text, registrable_domain


@dataclass
class Event:
    source: str            # "email" | "sms"
    account: str           # taranan posta kutusu adresi veya telefon numarası
    sender: str
    subject: str
    date: datetime | None
    event_type: str
    service: str
    category: str
    known: bool            # katalogdaki bir servise eşlendi mi

    def to_dict(self) -> dict:
        return {
            "source": self.source,
            "account": self.account,
            "sender": self.sender,
            "subject": self.subject,
            "date": self.date.isoformat() if self.date else None,
            "event_type": self.event_type,
            "service": self.service,
            "category": self.category,
            "known": self.known,
        }


def resolve_email_service(sender_domain: str) -> tuple[str, str, bool]:
    svc: Service | None = match_domain(sender_domain)
    if svc:
        return svc.name, svc.category, True
    return registrable_domain(sender_domain) or sender_domain, "other", False


def resolve_sms_service(sender: str, body: str) -> tuple[str, str, bool]:
    svc = match_text(f"{sender} {body}")
    if svc:
        return svc.name, svc.category, True
    return sender.strip() or "?", "other", False


@dataclass
class AccountRecord:
    service: str
    category: str
    known: bool
    accounts: set[str] = field(default_factory=set)
    sources: set[str] = field(default_factory=set)
    counts: dict[str, int] = field(default_factory=dict)
    first_seen: datetime | None = None
    last_seen: datetime | None = None
    last_deletion: datetime | None = None
    last_non_deletion: datetime | None = None
    samples: list[str] = field(default_factory=list)

    def add(self, ev: Event) -> None:
        self.accounts.add(ev.account)
        self.sources.add(ev.source)
        self.counts[ev.event_type] = self.counts.get(ev.event_type, 0) + 1
        if ev.date:
            d = ev.date
            self.first_seen = d if self.first_seen is None or d < self.first_seen else self.first_seen
            self.last_seen = d if self.last_seen is None or d > self.last_seen else self.last_seen
            if ev.event_type == DELETION:
                if self.last_deletion is None or d > self.last_deletion:
                    self.last_deletion = d
            elif self.last_non_deletion is None or d > self.last_non_deletion:
                self.last_non_deletion = d
        if ev.event_type != OTHER and ev.subject and len(self.samples) < 3:
            self.samples.append(ev.subject[:160])

    def status(self, now: datetime | None = None) -> str:
        now = now or datetime.now(timezone.utc)
        if self.counts.get(DELETION):
            if self.last_deletion is None or self.last_non_deletion is None \
                    or self.last_deletion >= self.last_non_deletion:
                return "deleted"
        if self.last_seen and now - self.last_seen <= timedelta(days=365):
            return "active"
        return "dormant"


STATUS_LABELS = {
    "deleted": "Silinmiş olabilir",
    "active": "Aktif olabilir (son 1 yıl)",
    "dormant": "Eski / kullanılmıyor",
}


def build_inventory(events: list[Event], include_unknown_other: bool = False) -> list[AccountRecord]:
    """Olayları servis bazında birleştirir.

    Katalogda olmayan göndericiler yalnızca hesap olayı (kayıt, silme, şifre,
    güvenlik) içeriyorsa dahil edilir; aksi halde bülten gürültüsü olur.
    """
    records: dict[str, AccountRecord] = {}
    for ev in events:
        if not ev.known and ev.event_type == OTHER and not include_unknown_other:
            continue
        key = ev.service.lower()
        rec = records.get(key)
        if rec is None:
            rec = records[key] = AccountRecord(ev.service, ev.category, ev.known)
        rec.add(ev)
    # Katalog dışı servislerde yalnızca "other" kalanları ele.
    return [r for r in records.values() if r.known or set(r.counts) - {OTHER}]
