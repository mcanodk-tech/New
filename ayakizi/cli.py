"""Komut satırı arayüzü.

    ayakizi scan --imap ben@gmail.com --sms sms-yedek.xml --phone +905551112233 --hibp
    ayakizi password
"""

from __future__ import annotations

import argparse
import getpass
import imaplib
import os
import sys
from datetime import date
from pathlib import Path

from . import __version__
from .hibp import HIBPError, breached_account, pwned_password_count
from .inbox import guess_imap_host, scan_mailbox
from .models import Event, build_inventory
from .report import write_reports
from .sms import scan_sms_backup


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)


def cmd_scan(args: argparse.Namespace) -> int:
    if not args.imap and not args.sms:
        _log("En az bir --imap adresi veya --sms yedeği verin.")
        return 2
    if args.sms and not args.phone:
        _log("--sms kullanırken kendi numaranızı --phone ile belirtin.")
        return 2
    if args.imap_host and len(args.imap) > 1:
        _log("--imap-host yalnızca tek bir --imap adresiyle kullanılabilir.")
        return 2

    since = date.fromisoformat(args.since) if args.since else None
    events: list[Event] = []
    verified_emails: list[str] = []
    scanned: list[str] = []

    for address in args.imap:
        host = args.imap_host or guess_imap_host(address)
        env_pw = os.environ.get("AYAKIZI_IMAP_PASSWORD") if len(args.imap) == 1 else None
        password = env_pw or getpass.getpass(f"{address} için IMAP / uygulama şifresi: ")
        _log(f"[e-posta] {address} @ {host}")
        try:
            evs = scan_mailbox(address, password, host=host, folders=args.folder or None,
                               since=since, progress=_log)
        except imaplib.IMAP4.error as e:
            _log(f"  ! giriş başarısız: {e}. Gmail/Outlook için 'uygulama şifresi' gerekir.")
            continue
        except OSError as e:
            _log(f"  ! bağlantı hatası ({host}): {e}")
            continue
        # IMAP girişi başarılı -> bu adresin sahibi olduğunuz kanıtlandı.
        verified_emails.append(address.lower())
        scanned.append(address)
        events.extend(evs)

    for path in args.sms:
        _log(f"[sms] {path}")
        events.extend(scan_sms_backup(path, args.phone))
        scanned.append(f"{args.phone} (SMS yedeği)")

    breaches: list[dict] = []
    if args.hibp:
        key = os.environ.get("HIBP_API_KEY")
        if not key:
            _log("! --hibp için HIBP_API_KEY ortam değişkeni gerekli (haveibeenpwned.com/API/Key).")
        for address in verified_emails if key else []:
            _log(f"[hibp] {address}")
            try:
                breaches.extend(breached_account(address, key))
            except HIBPError as e:
                _log(f"  ! {e}")

    inventory = build_inventory(events)
    json_path, html_path = write_reports(Path(args.out), events, inventory, breaches, scanned)
    _log(f"\n{len(inventory)} hesap, {len(breaches)} sızıntı bulundu.")
    print(html_path)
    print(json_path)
    return 0


def cmd_password(_args: argparse.Namespace) -> int:
    pw = getpass.getpass("Kontrol edilecek şifre (gönderilmez, yalnızca SHA-1 öneki): ")
    if not pw:
        return 2
    try:
        count = pwned_password_count(pw)
    except HIBPError as e:
        _log(str(e))
        return 1
    if count:
        print(f"Bu şifre sızıntılarda {count:,} kez görülmüş. Kullandığınız her yerde değiştirin.")
        return 1
    print("Bu şifre bilinen sızıntılarda bulunamadı.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ayakizi",
        description="Kendi e-posta kutunuzu ve SMS yedeğinizi tarayarak hangi servislerde "
                    "hesabınız olduğunu (ve hangilerini sildiğinizi) çıkaran kişisel denetim aracı.")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("scan", help="posta kutusu / SMS yedeği tara ve rapor üret")
    s.add_argument("--imap", action="append", default=[], metavar="ADRES",
                   help="taranacak kendi e-posta adresiniz (birden çok kez verilebilir)")
    s.add_argument("--imap-host", help="IMAP sunucusu (varsayılan: adresten tahmin edilir)")
    s.add_argument("--folder", action="append", help="yalnızca bu IMAP klasörlerini tara")
    s.add_argument("--since", help="YYYY-AA-GG tarihinden sonraki mesajlar")
    s.add_argument("--sms", action="append", default=[], metavar="XML",
                   help="Android 'SMS Backup & Restore' XML yedeği")
    s.add_argument("--phone", help="SMS yedeğinin ait olduğu kendi numaranız")
    s.add_argument("--hibp", action="store_true",
                   help="doğrulanmış adresleri Have I Been Pwned'de kontrol et (HIBP_API_KEY)")
    s.add_argument("--out", default="ayakizi-rapor", help="rapor klasörü")
    s.set_defaults(func=cmd_scan)

    pw = sub.add_parser("password", help="bir şifrenin sızıntılarda olup olmadığını kontrol et")
    pw.set_defaults(func=cmd_password)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
