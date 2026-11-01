"""CLI ve uygulamanın ortak kullandığı tarama akışı."""

from __future__ import annotations

import imaplib
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import date
from typing import IO, Callable, Union

from .hibp import HIBPError, breached_account
from .inbox import guess_imap_host, scan_mailbox
from .models import AccountRecord, Event, build_inventory
from .sms import scan_sms_backup

Log = Callable[[str], None]


@dataclass
class ImapAccount:
    address: str
    password: str
    host: str | None = None
    folders: list[str] | None = None


@dataclass
class SmsBackup:
    source: Union[str, IO[bytes]]   # dosya yolu ya da açık dosya
    phone: str
    label: str = ""


@dataclass
class ScanResult:
    events: list[Event] = field(default_factory=list)
    inventory: list[AccountRecord] = field(default_factory=list)
    breaches: list[dict] = field(default_factory=list)
    scanned: list[str] = field(default_factory=list)
    verified_emails: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def run_scan(
    imap_accounts: list[ImapAccount] = (),
    otp_verified_emails: list[str] = (),
    sms_backups: list[SmsBackup] = (),
    since: date | None = None,
    hibp_key: str | None = None,
    log: Log = lambda _m: None,
) -> ScanResult:
    res = ScanResult()

    def err(msg: str) -> None:
        res.errors.append(msg)
        log(f"  ! {msg}")

    for acc in imap_accounts:
        host = acc.host or guess_imap_host(acc.address)
        log(f"[e-posta] {acc.address} @ {host}")
        try:
            evs = scan_mailbox(acc.address, acc.password, host=host, folders=acc.folders,
                               since=since, progress=log)
        except imaplib.IMAP4.error as e:
            err(f"{acc.address}: giriş başarısız ({e}). Gmail/Outlook için uygulama şifresi gerekir.")
            continue
        except OSError as e:
            err(f"{acc.address}: bağlantı hatası ({host}): {e}")
            continue
        # IMAP girişi başarılı -> adresin sahibi olduğunuz kanıtlandı.
        res.verified_emails.append(acc.address.lower())
        res.scanned.append(acc.address)
        res.events.extend(evs)

    for address in otp_verified_emails:
        address = address.strip().lower()
        if address not in res.verified_emails:
            res.verified_emails.append(address)
            res.scanned.append(f"{address} (OTP ile doğrulandı)")

    for backup in sms_backups:
        label = backup.label or (backup.source if isinstance(backup.source, str) else "SMS")
        log(f"[sms] {label} ({backup.phone})")
        try:
            res.events.extend(scan_sms_backup(backup.source, backup.phone))
        except (OSError, ET.ParseError) as e:
            err(f"{label}: SMS yedeği okunamadı ({e})")
            continue
        res.scanned.append(f"{backup.phone} (SMS yedeği)")

    if hibp_key:
        for address in res.verified_emails:
            log(f"[hibp] {address}")
            try:
                res.breaches.extend(breached_account(address, hibp_key))
            except HIBPError as e:
                err(f"{address}: {e}")

    res.inventory = build_inventory(res.events)
    log(f"{len(res.inventory)} hesap, {len(res.breaches)} sızıntı bulundu.")
    return res
