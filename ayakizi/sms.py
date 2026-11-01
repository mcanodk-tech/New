"""Kullanıcının KENDİ telefonundan aldığı SMS yedeğini tarar.

Desteklenen biçim: Android "SMS Backup & Restore" XML dışa aktarımı
(<smses><sms address=".." body=".." date="epoch-ms" type="1" /></smses>).
Doğrulama kodu SMS'leri, numaranın hangi servislere kayıtlı olduğunu gösterir.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

from .classify import OTHER, classify
from .models import Event, resolve_sms_service

RECEIVED = "1"
_CODE_RE = re.compile(r"\b\d{4,8}\b")


def scan_sms_backup(path: str, phone: str) -> list[Event]:
    events: list[Event] = []
    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag != "sms":
            continue
        attrs = elem.attrib
        if attrs.get("type", RECEIVED) != RECEIVED:
            elem.clear()
            continue
        sender = attrs.get("address", "").strip()
        body = " ".join(attrs.get("body", "").split())
        when: datetime | None = None
        try:
            when = datetime.fromtimestamp(int(attrs["date"]) / 1000, tz=timezone.utc)
        except (KeyError, ValueError, OverflowError, OSError):
            pass
        service, category, known = resolve_sms_service(sender, body)
        event_type = classify(body)
        # Bilinmeyen ve hesapla ilgisiz SMS'ler (kişisel mesajlar) hiç kaydedilmez.
        if known or event_type != OTHER:
            events.append(Event(
                source="sms", account=phone, sender=sender, subject=_CODE_RE.sub("••••", body)[:160],  # kodları rapora yazma
                date=when, event_type=event_type, service=service,
                category=category, known=known,
            ))
        elem.clear()
    return events
