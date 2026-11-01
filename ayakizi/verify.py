"""E-posta sahipliğini tek kullanımlık kod (OTP) ile doğrulama.

IMAP erişimi olmayan bir adres (iş e-postası, takma ad, yönlendirme adresi)
için kullanılır: adrese 6 haneli bir kod gönderilir, kod doğru girilirse adres
"doğrulanmış" sayılır ve sızıntı kontrolüne dahil edilir.

Kod kullanıcının kendi SMTP hesabından gönderilir:
    AYAKIZI_SMTP_USER, AYAKIZI_SMTP_PASSWORD   (zorunlu)
    AYAKIZI_SMTP_HOST, AYAKIZI_SMTP_PORT       (isteğe bağlı; adresten tahmin edilir)
"""

from __future__ import annotations

import hmac
import os
import secrets
import smtplib
import ssl
import time
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Callable

CODE_TTL_SECONDS = 600
MAX_ATTEMPTS = 3

KNOWN_SMTP_HOSTS = {
    "gmail.com": ("smtp.gmail.com", 465),
    "googlemail.com": ("smtp.gmail.com", 465),
    "outlook.com": ("smtp.office365.com", 587),
    "hotmail.com": ("smtp.office365.com", 587),
    "live.com": ("smtp.office365.com", 587),
    "yahoo.com": ("smtp.mail.yahoo.com", 465),
    "yandex.com": ("smtp.yandex.com", 465),
    "yandex.com.tr": ("smtp.yandex.com", 465),
    "icloud.com": ("smtp.mail.me.com", 587),
    "me.com": ("smtp.mail.me.com", 587),
}


class VerificationError(RuntimeError):
    pass


@dataclass
class SmtpConfig:
    user: str
    password: str
    host: str
    port: int

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "SmtpConfig":
        env = os.environ if env is None else env
        user = env.get("AYAKIZI_SMTP_USER", "")
        password = env.get("AYAKIZI_SMTP_PASSWORD", "")
        if not user or not password:
            raise VerificationError(
                "OTP göndermek için AYAKIZI_SMTP_USER ve AYAKIZI_SMTP_PASSWORD gerekli "
                "(kendi e-posta hesabınız + uygulama şifresi).")
        domain = user.rsplit("@", 1)[-1].lower()
        default_host, default_port = KNOWN_SMTP_HOSTS.get(domain, (f"smtp.{domain}", 587))
        host = env.get("AYAKIZI_SMTP_HOST") or default_host
        port = int(env.get("AYAKIZI_SMTP_PORT") or default_port)
        return cls(user, password, host, port)


def generate_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def send_code(cfg: SmtpConfig, to_address: str, code: str) -> None:
    msg = EmailMessage()
    msg["From"] = cfg.user
    msg["To"] = to_address
    msg["Subject"] = f"ayakizi doğrulama kodu: {code}"
    msg.set_content(
        f"Bu adresin size ait olduğunu doğrulamak için kod: {code}\n\n"
        f"Kod {CODE_TTL_SECONDS // 60} dakika geçerlidir. Bu isteği siz yapmadıysanız "
        "bu e-postayı yok sayın.\n")
    context = ssl.create_default_context()
    try:
        if cfg.port == 465:
            with smtplib.SMTP_SSL(cfg.host, cfg.port, context=context, timeout=30) as s:
                s.login(cfg.user, cfg.password)
                s.send_message(msg)
        else:
            with smtplib.SMTP(cfg.host, cfg.port, timeout=30) as s:
                s.starttls(context=context)
                s.login(cfg.user, cfg.password)
                s.send_message(msg)
    except (smtplib.SMTPException, OSError) as e:
        raise VerificationError(f"Kod gönderilemedi ({cfg.host}:{cfg.port}): {e}") from e


def verify_email(
    address: str,
    cfg: SmtpConfig,
    prompt: Callable[[str], str] = input,
    sender: Callable[[SmtpConfig, str, str], None] = send_code,
    clock: Callable[[], float] = time.monotonic,
) -> bool:
    """Kod gönderir, kullanıcıdan ister; doğruysa True döner."""
    code = generate_code()
    sender(cfg, address, code)
    deadline = clock() + CODE_TTL_SECONDS
    for attempt in range(1, MAX_ATTEMPTS + 1):
        entered = prompt(f"{address} adresine gelen 6 haneli kod ({attempt}/{MAX_ATTEMPTS}): ")
        if clock() > deadline:
            return False
        if hmac.compare_digest(entered.strip().replace(" ", ""), code):
            return True
    return False
