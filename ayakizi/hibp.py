"""Have I Been Pwned entegrasyonu.

* breached_account: yalnızca IMAP ile oturum açılarak sahipliği kanıtlanmış
  adresler için CLI tarafından çağrılır.
* pwned_password_count: k-anonimlik; şifrenin yalnızca SHA-1 özetinin ilk 5
  karakteri gönderilir.
"""

from __future__ import annotations

import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "ayakizi-personal-footprint-audit"
API = "https://haveibeenpwned.com/api/v3"
PWNED_PASSWORDS = "https://api.pwnedpasswords.com/range/"


class HIBPError(RuntimeError):
    pass


def _get(url: str, headers: dict[str, str], retries: int = 3) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **headers})
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return 404, b""
            if e.code == 429 and attempt < retries:
                wait = float(e.headers.get("retry-after", "2") or 2)
                time.sleep(min(wait, 30))
                continue
            if e.code == 401:
                raise HIBPError("HIBP API anahtarı geçersiz (401).") from e
            raise HIBPError(f"HIBP hatası: HTTP {e.code}") from e
    raise HIBPError("HIBP: çok fazla istek (429).")


def breached_account(email: str, api_key: str) -> list[dict]:
    url = f"{API}/breachedaccount/{urllib.parse.quote(email)}?truncateResponse=false"
    status, body = _get(url, {"hibp-api-key": api_key})
    if status == 404:
        return []
    breaches = json.loads(body)
    return [
        {
            "name": b.get("Name"),
            "title": b.get("Title"),
            "domain": b.get("Domain"),
            "breach_date": b.get("BreachDate"),
            "data_classes": b.get("DataClasses", []),
            "is_sensitive": b.get("IsSensitive", False),
            "account": email,
        }
        for b in breaches
    ]


def parse_range_response(text: str, suffix: str) -> int:
    for line in text.splitlines():
        hash_suffix, _, count = line.strip().partition(":")
        if hash_suffix.upper() == suffix:
            try:
                return int(count)
            except ValueError:
                return 0
    return 0


def pwned_password_count(password: str) -> int:
    digest = hashlib.sha1(password.encode("utf-8")).hexdigest().upper()
    prefix, suffix = digest[:5], digest[5:]
    _, body = _get(PWNED_PASSWORDS + prefix, {"Add-Padding": "true"})
    return parse_range_response(body.decode("utf-8", "replace"), suffix)
