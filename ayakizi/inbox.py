"""Kullanıcının KENDİ posta kutusunu IMAP ile salt-okunur tarar.

Yalnızca başlıklar (From / Subject / Date) okunur; mesaj gövdeleri indirilmez,
hiçbir mesaj okunmuş olarak işaretlenmez (BODY.PEEK + readonly SELECT).
"""

from __future__ import annotations

import imaplib
import re
from datetime import date, datetime, timezone
from email.header import decode_header, make_header
from email.parser import BytesHeaderParser
from email.utils import parseaddr, parsedate_to_datetime
from typing import Callable, Iterable

from .classify import classify
from .models import Event, resolve_email_service

KNOWN_IMAP_HOSTS = {
    "gmail.com": "imap.gmail.com",
    "googlemail.com": "imap.gmail.com",
    "outlook.com": "outlook.office365.com",
    "hotmail.com": "outlook.office365.com",
    "live.com": "outlook.office365.com",
    "msn.com": "outlook.office365.com",
    "yahoo.com": "imap.mail.yahoo.com",
    "yandex.com": "imap.yandex.com",
    "yandex.com.tr": "imap.yandex.com",
    "icloud.com": "imap.mail.me.com",
    "me.com": "imap.mail.me.com",
    "gmx.com": "imap.gmx.com",
    "aol.com": "imap.aol.com",
    "zoho.com": "imap.zoho.com",
}

_LIST_RE = re.compile(rb'\((?P<flags>[^)]*)\) (?P<delim>"[^"]*"|NIL) (?P<name>.+)$')
_UID_RE = re.compile(rb"UID (\d+)")
_INTERESTING_FLAGS = {b"\\all", b"\\archive", b"\\junk", b"\\trash"}
BATCH = 400


def guess_imap_host(address: str) -> str:
    domain = address.rsplit("@", 1)[-1].lower()
    return KNOWN_IMAP_HOSTS.get(domain, f"imap.{domain}")


def _decode(value: object) -> str:
    if value is None:
        return ""
    text = str(value)
    try:
        return str(make_header(decode_header(text)))
    except Exception:
        return text


def _parse_list_line(line: bytes) -> tuple[set[bytes], str] | None:
    m = _LIST_RE.match(line)
    if not m:
        return None
    flags = {f.lower() for f in m.group("flags").split()}
    name = m.group("name").strip()
    if name.startswith(b'"') and name.endswith(b'"'):
        name = name[1:-1].replace(b'\\"', b'"').replace(b"\\\\", b"\\")
    # Klasör adları "modified UTF-7" olarak gelir; SELECT için aynen geri gönderilir.
    return flags, name.decode("ascii", "replace")


def choose_folders(list_lines: Iterable[bytes]) -> list[str]:
    """Gmail'de "Tüm Postalar" yeterli; diğerlerinde INBOX + arşiv/spam/çöp."""
    parsed = [p for p in (_parse_list_line(l) for l in list_lines if l) if p]
    all_mail = [name for flags, name in parsed if b"\\all" in flags]
    if all_mail:
        extra = [name for flags, name in parsed if flags & {b"\\junk", b"\\trash"}]
        return all_mail + extra
    folders = ["INBOX"]
    folders += [name for flags, name in parsed
                if flags & _INTERESTING_FLAGS and name.upper() != "INBOX"]
    return folders


def _parse_header_block(raw: bytes) -> tuple[str, str, str, datetime | None]:
    msg = BytesHeaderParser().parsebytes(raw)
    _, addr = parseaddr(_decode(msg.get("From")))
    subject = _decode(msg.get("Subject")).replace("\r", " ").replace("\n", " ").strip()
    when: datetime | None = None
    try:
        raw_date = msg.get("Date")
        if raw_date:
            when = parsedate_to_datetime(str(raw_date))
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
    except Exception:
        when = None
    domain = addr.rsplit("@", 1)[-1].lower() if "@" in addr else ""
    return addr.lower(), domain, subject, when


def scan_mailbox(
    user: str,
    password: str,
    host: str | None = None,
    port: int = 993,
    folders: list[str] | None = None,
    since: date | None = None,
    progress: Callable[[str], None] | None = None,
) -> list[Event]:
    host = host or guess_imap_host(user)
    log = progress or (lambda _msg: None)
    events: list[Event] = []
    seen_ids: set[tuple[str, str, str]] = set()

    imap = imaplib.IMAP4_SSL(host, port)
    try:
        imap.login(user, password)
        if not folders:
            typ, lines = imap.list()
            folders = choose_folders(lines if typ == "OK" else [])
        for folder in folders:
            quoted = folder.replace("\\", "\\\\").replace('"', '\\"')
            typ, _ = imap.select(f'"{quoted}"', readonly=True)
            if typ != "OK":
                log(f"  ! klasör açılamadı: {folder}")
                continue
            criteria = ["SINCE", since.strftime("%d-%b-%Y")] if since else ["ALL"]
            typ, data = imap.uid("SEARCH", None, *criteria)
            uids = data[0].split() if typ == "OK" and data and data[0] else []
            log(f"  {folder}: {len(uids)} mesaj")
            for i in range(0, len(uids), BATCH):
                chunk = b",".join(uids[i:i + BATCH]).decode()
                typ, resp = imap.uid(
                    "FETCH", chunk, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])")
                if typ != "OK":
                    continue
                for part in resp:
                    if not isinstance(part, tuple) or len(part) < 2:
                        continue
                    sender, domain, subject, when = _parse_header_block(part[1])
                    if not domain:
                        continue
                    # Gmail'de aynı mesaj birden çok klasörde olabilir.
                    dedup = (sender, subject, when.isoformat() if when else "")
                    if dedup in seen_ids:
                        continue
                    seen_ids.add(dedup)
                    service, category, known = resolve_email_service(domain)
                    events.append(Event(
                        source="email", account=user.lower(), sender=sender,
                        subject=subject, date=when, event_type=classify(subject),
                        service=service, category=category, known=known,
                    ))
                log(f"    {min(i + BATCH, len(uids))}/{len(uids)}")
    finally:
        try:
            imap.logout()
        except Exception:
            pass
    return events
