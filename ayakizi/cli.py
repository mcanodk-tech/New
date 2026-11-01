"""Komut satırı arayüzü.

    ayakizi scan --imap ben@gmail.com --sms sms-yedek.xml --phone +905551112233 --hibp
    ayakizi password
    ayakizi app          # tarayıcıda açılan uygulama
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from datetime import date
from pathlib import Path

from . import __version__
from .core import ImapAccount, SmsBackup, run_scan
from .hibp import HIBPError, pwned_password_count
from .report import write_reports
from .verify import SmtpConfig, VerificationError, verify_email


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)


def _parse_sms_arg(value: str, default_phone: str | None) -> tuple[str, str]:
    """`yedek.xml=+90555...` ya da `yedek.xml` (+ --phone)."""
    path, sep, phone = value.rpartition("=")
    if sep and phone.strip().lstrip("+").isdigit():
        return path, phone.strip()
    if not default_phone:
        raise ValueError(f"{value}: numarayı 'dosya.xml=+90555...' biçiminde ya da --phone ile verin.")
    return value, default_phone


def cmd_scan(args: argparse.Namespace) -> int:
    if not args.imap and not args.sms and not args.verify_email:
        _log("En az bir --imap, --verify-email adresi veya --sms yedeği verin.")
        return 2
    try:
        sms_inputs = [_parse_sms_arg(v, args.phone) for v in args.sms]
    except ValueError as e:
        _log(str(e))
        return 2
    if args.imap_host and len(args.imap) > 1:
        _log("--imap-host yalnızca tek bir --imap adresiyle kullanılabilir.")
        return 2

    since = date.fromisoformat(args.since) if args.since else None

    imap_accounts = []
    for address in args.imap:
        env_pw = os.environ.get("AYAKIZI_IMAP_PASSWORD") if len(args.imap) == 1 else None
        password = env_pw or getpass.getpass(f"{address} için IMAP / uygulama şifresi: ")
        imap_accounts.append(ImapAccount(address, password, args.imap_host, args.folder or None))

    otp_verified: list[str] = []
    if args.verify_email:
        try:
            smtp = SmtpConfig.from_env()
        except VerificationError as e:
            _log(f"! {e}")
            smtp = None
        for address in args.verify_email if smtp else []:
            address = address.strip().lower()
            if address in otp_verified:
                continue
            _log(f"[otp] {address} adresine kod gönderiliyor ({smtp.host})")
            try:
                ok = verify_email(address, smtp)
            except VerificationError as e:
                _log(f"  ! {e}")
                continue
            if ok:
                _log("  doğrulandı")
                otp_verified.append(address)
            else:
                _log("  ! kod doğrulanamadı; bu adres atlandı")

    hibp_key = None
    if args.hibp:
        hibp_key = os.environ.get("HIBP_API_KEY")
        if not hibp_key:
            _log("! --hibp için HIBP_API_KEY ortam değişkeni gerekli (haveibeenpwned.com/API/Key).")

    res = run_scan(
        imap_accounts=imap_accounts,
        otp_verified_emails=otp_verified,
        sms_backups=[SmsBackup(path, phone) for path, phone in sms_inputs],
        since=since,
        hibp_key=hibp_key,
        log=_log,
    )
    json_path, html_path = write_reports(Path(args.out), res.events, res.inventory,
                                         res.breaches, res.scanned)
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


def cmd_app(args: argparse.Namespace) -> int:
    from .web import serve
    serve(port=args.port, open_browser=not args.no_browser)
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
    s.add_argument("--verify-email", action="append", default=[], metavar="ADRES",
                   help="IMAP erişimi olmayan kendi adresiniz: OTP gönderilir, doğrulanırsa "
                        "sızıntı kontrolüne dahil edilir (AYAKIZI_SMTP_USER/PASSWORD)")
    s.add_argument("--sms", action="append", default=[], metavar="XML[=NUMARA]",
                   help="Android 'SMS Backup & Restore' XML yedeği; birden çok numara için "
                        "yedek.xml=+90555... biçimi")
    s.add_argument("--phone", help="numarası belirtilmeyen SMS yedeklerinin ait olduğu numara")
    s.add_argument("--hibp", action="store_true",
                   help="doğrulanmış adresleri Have I Been Pwned'de kontrol et (HIBP_API_KEY)")
    s.add_argument("--out", default="ayakizi-rapor", help="rapor klasörü")
    s.set_defaults(func=cmd_scan)

    app = sub.add_parser("app", help="uygulamayı tarayıcıda aç (yerel, 127.0.0.1)")
    app.add_argument("--port", type=int, default=8765)
    app.add_argument("--no-browser", action="store_true", help="tarayıcıyı otomatik açma")
    app.set_defaults(func=cmd_app)

    pw = sub.add_parser("password", help="bir şifrenin sızıntılarda olup olmadığını kontrol et")
    pw.set_defaults(func=cmd_password)
    return p


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    args = build_parser().parse_args(argv or ["app"])  # argümansız: uygulamayı aç
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
