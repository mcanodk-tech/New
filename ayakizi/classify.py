"""Mesaj konusu / gövdesinden hesap olayı türünü çıkarır (TR + EN)."""

from __future__ import annotations

import re

SIGNUP = "signup"
DELETION = "deletion"
PASSWORD_RESET = "password_reset"
SECURITY = "security"
OTHER = "other"

EVENT_LABELS = {
    SIGNUP: "Kayıt / hoş geldiniz",
    DELETION: "Hesap silme / kapatma",
    PASSWORD_RESET: "Şifre sıfırlama",
    SECURITY: "Giriş / doğrulama kodu",
    OTHER: "Diğer",
}

_I = "[iıİI]"  # Türkçe/İngilizce i harfi varyantları

_PATTERNS: list[tuple[str, list[str]]] = [
    (DELETION, [
        r"account (has been |was |is being )?(deleted|closed|deactivated|removed|terminated|cancell?ed)",
        r"(deleted|closed|deactivated) your account",
        r"(account|data) deletion",
        r"sorry to see you go",
        r"goodbye from",
        rf"hesab{_I}n{_I}z ?{_I}?( başar{_I}yla)? (s{_I}l{_I}nd{_I}|s{_I}l{_I}nm{_I}şt{_I}r|kapat{_I}ld{_I}|kapat{_I}lm{_I}şt{_I}r|dondurul)",
        rf"hesap (s{_I}lme|kapatma)",
        rf"üyel{_I}ğ{_I}n{_I}z (sonland{_I}r{_I}ld{_I}|{_I}ptal|s{_I}l{_I}nd{_I})",
    ]),
    (SIGNUP, [
        r"welcome( to|,|!|\b)",
        r"(verify|confirm) your (e-?mail|email address|account|registration|sign-?up)",
        r"activate your account",
        r"account (has been |was )?created",
        r"thanks? (you )?for (signing up|joining|registering|creating)",
        r"complete your (registration|sign-?up|profile)",
        r"you('re| are) (in|registered)",
        rf"hoş ?geld{_I}n",
        rf"hesab{_I}n{_I}z{_I}? ?(oluşturuldu|doğrula|onayla|akt{_I}f)",
        rf"e-?posta adres{_I}n{_I}z{_I} (doğrula|onayla)",
        rf"üyel{_I}ğ{_I}n{_I}z{_I}? ?(oluşturuldu|başlad{_I}|onayla|tamamla|akt{_I}f)",
        rf"kayd{_I}n{_I}z{_I}? ?(tamamla|oluşturuldu|al{_I}nd{_I}|onayla)",
        rf"aram{_I}za hoş",
    ]),
    (PASSWORD_RESET, [
        r"(reset|change|recover) your password",
        r"password (reset|change|recovery)",
        r"forgot (your )?password",
        rf"ş{_I}fre(n{_I}z{_I})? ?(s{_I}f{_I}rla|yen{_I}le|değ{_I}ş|hat{_I}rlat)",
        rf"parola(n{_I}z{_I})? ?(s{_I}f{_I}rla|yen{_I}le|değ{_I}ş)",
    ]),
    (SECURITY, [
        r"new (sign-?in|login|device)",
        r"(security|login|sign-?in) (alert|code|notification)",
        r"(verification|confirmation|one-?time|security|login) (code|pin)",
        r"\b(otp|2fa|two-factor)\b",
        r"\bis your .{0,20}code\b",
        r"\bcode( is)?[: ]+\d{4,8}\b",
        r"\byour \w+( \w+)? code\b",
        rf"g{_I}r{_I}ş (yap{_I}ld{_I}|kodu|uyar{_I}s{_I}|b{_I}ld{_I}r{_I}m)",
        rf"(doğrulama|onay|güvenl{_I}k|tek kullan{_I}ml{_I}k) (kodu|ş{_I}fre)",
        rf"\bkod(unuz|u)?[: ]+\d{{4,8}}\b",
    ]),
]

_COMPILED = [(event, [re.compile(p, re.IGNORECASE) for p in pats]) for event, pats in _PATTERNS]


def classify(text: str) -> str:
    """Metni en yüksek öncelikli olay türüne sınıflar."""
    if not text:
        return OTHER
    for event, patterns in _COMPILED:
        if any(p.search(text) for p in patterns):
            return event
    return OTHER
