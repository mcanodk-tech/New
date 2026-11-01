import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from ayakizi import classify as C
from ayakizi import hibp, inbox
from ayakizi.models import Event, build_inventory
from ayakizi.report import write_reports
from ayakizi.services import match_domain, match_text, registrable_domain
from ayakizi.sms import scan_sms_backup


class ClassifyTests(unittest.TestCase):
    def test_english(self):
        self.assertEqual(C.classify("Welcome to Tinder!"), C.SIGNUP)
        self.assertEqual(C.classify("Please verify your email address"), C.SIGNUP)
        self.assertEqual(C.classify("Your account has been deleted"), C.DELETION)
        self.assertEqual(C.classify("We're sorry to see you go"), C.DELETION)
        self.assertEqual(C.classify("Reset your password"), C.PASSWORD_RESET)
        self.assertEqual(C.classify("New sign-in from Chrome on Windows"), C.SECURITY)
        self.assertEqual(C.classify("123456 is your Tinder code"), C.SECURITY)
        self.assertEqual(C.classify("50% off this weekend"), C.OTHER)

    def test_turkish(self):
        self.assertEqual(C.classify("Trendyol'a hoş geldin!"), C.SIGNUP)
        self.assertEqual(C.classify("HESABINIZ OLUŞTURULDU"), C.SIGNUP)
        self.assertEqual(C.classify("Hesabınız başarıyla silindi"), C.DELETION)
        self.assertEqual(C.classify("Üyeliğiniz sonlandırıldı"), C.DELETION)
        self.assertEqual(C.classify("Şifrenizi sıfırlayın"), C.PASSWORD_RESET)
        self.assertEqual(C.classify("Doğrulama kodunuz: 482913"), C.SECURITY)
        self.assertEqual(C.classify("Yeni sezon ürünleri"), C.OTHER)

    def test_deletion_beats_signup(self):
        self.assertEqual(C.classify("Welcome back - your account was deleted"), C.DELETION)


class ServiceTests(unittest.TestCase):
    def test_match_domain_subdomains(self):
        self.assertEqual(match_domain("mail.gotinder.com").name, "Tinder")
        self.assertEqual(match_domain("info.trendyol.com").name, "Trendyol")
        self.assertIsNone(match_domain("example.org"))

    def test_registrable_domain(self):
        self.assertEqual(registrable_domain("news.shop.example.com.tr"), "example.com.tr")
        self.assertEqual(registrable_domain("a.b.example.com"), "example.com")

    def test_match_text_word_boundary_and_longest(self):
        self.assertEqual(match_text("Your Bumble code is 1234").name, "Bumble")
        self.assertEqual(match_text("Trendyol Yemek siparişin yolda").name, "Trendyol Yemek")
        self.assertIsNone(match_text("tindering around"))


def _ev(service, event_type, days_ago, known=True, category="dating"):
    return Event("email", "me@x.com", "a@b.com", "subj", datetime.now(timezone.utc)
                 - timedelta(days=days_ago), event_type, service, category, known)


class InventoryTests(unittest.TestCase):
    def test_status(self):
        inv = {r.service: r for r in build_inventory([
            _ev("Tinder", C.SIGNUP, 900), _ev("Tinder", C.DELETION, 800),
            _ev("Bumble", C.SIGNUP, 30),
            _ev("Hinge", C.SIGNUP, 900),
            _ev("Badoo", C.DELETION, 500), _ev("Badoo", C.SECURITY, 10),
        ])}
        self.assertEqual(inv["Tinder"].status(), "deleted")
        self.assertEqual(inv["Bumble"].status(), "active")
        self.assertEqual(inv["Hinge"].status(), "dormant")
        self.assertEqual(inv["Badoo"].status(), "active")  # silindikten sonra tekrar kullanılmış

    def test_unknown_newsletters_dropped(self):
        inv = build_inventory([
            _ev("shop.com", C.OTHER, 5, known=False, category="other"),
            _ev("forum.net", C.SIGNUP, 5, known=False, category="other"),
        ])
        self.assertEqual([r.service for r in inv], ["forum.net"])


class SmsTests(unittest.TestCase):
    def test_scan(self):
        xml = """<?xml version='1.0' encoding='UTF-8'?>
<smses count="4">
  <sms address="TINDER" body="Your Tinder code is 123456" date="1600000000000" type="1"/>
  <sms address="+905551112233" body="aksam gorusuruz" date="1600000000000" type="1"/>
  <sms address="ACME" body="Dogrulama kodunuz: 9911" date="1600000000000" type="1"/>
  <sms address="TINDER" body="sent by me" date="1600000000000" type="2"/>
</smses>"""
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False, encoding="utf-8") as f:
            f.write(xml)
        try:
            events = scan_sms_backup(f.name, "+90555")
        finally:
            Path(f.name).unlink()
        self.assertEqual([(e.service, e.event_type) for e in events],
                         [("Tinder", C.SECURITY), ("ACME", C.SECURITY)])


class FakeIMAP:
    def __init__(self, host, port):
        self.selected = []

    def login(self, user, pw):
        if pw != "ok":
            raise inbox.imaplib.IMAP4.error("bad")

    def list(self):
        return "OK", [b'(\\HasNoChildren) "/" "INBOX"',
                      b'(\\HasNoChildren \\All) "/" "[Gmail]/All Mail"',
                      b'(\\HasNoChildren \\Trash) "/" "[Gmail]/Trash"']

    def select(self, name, readonly=False):
        assert readonly
        self.selected.append(name)
        return "OK", [b"2"]

    def uid(self, cmd, *args):
        if cmd == "SEARCH":
            return "OK", [b"1 2"]
        assert "BODY.PEEK" in args[1]
        h1 = (b"From: Tinder <no-reply@mail.gotinder.com>\r\n"
              b"Subject: =?utf-8?q?Welcome_to_Tinder!?=\r\nDate: Tue, 1 Jan 2019 10:00:00 +0000\r\n\r\n")
        h2 = (b"From: Bumble <hello@bumble.com>\r\n"
              b"Subject: Your account has been deleted\r\nDate: Wed, 2 Jan 2019 10:00:00 +0000\r\n\r\n")
        return "OK", [(b"1 (UID 1 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {100}", h1), b")",
                      (b"2 (UID 2 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {100}", h2), b")"]

    def logout(self):
        pass


class InboxTests(unittest.TestCase):
    def test_choose_folders_gmail(self):
        self.assertEqual(inbox.choose_folders(FakeIMAP("", 0).list()[1]),
                         ["[Gmail]/All Mail", "[Gmail]/Trash"])

    def test_scan_dedups_across_folders(self):
        with mock.patch.object(inbox.imaplib, "IMAP4_SSL", FakeIMAP):
            events = inbox.scan_mailbox("me@gmail.com", "ok")
        self.assertEqual(len(events), 2)  # iki klasörde aynı mesajlar -> tekilleştirildi
        by = {e.service: e for e in events}
        self.assertEqual(by["Tinder"].event_type, C.SIGNUP)
        self.assertEqual(by["Tinder"].subject, "Welcome to Tinder!")
        self.assertEqual(by["Bumble"].event_type, C.DELETION)

    def test_guess_host(self):
        self.assertEqual(inbox.guess_imap_host("a@hotmail.com"), "outlook.office365.com")
        self.assertEqual(inbox.guess_imap_host("a@firma.com.tr"), "imap.firma.com.tr")


class HibpTests(unittest.TestCase):
    def test_parse_range(self):
        text = "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\nABCDEF:42\r\n"
        self.assertEqual(hibp.parse_range_response(text, "ABCDEF"), 42)
        self.assertEqual(hibp.parse_range_response(text, "FFFF"), 0)

    def test_password_sends_only_prefix(self):
        seen = {}

        def fake_get(url, headers, retries=3):
            seen["url"] = url
            return 200, b"1E4C9B93F3F0682250B6CF8331B7EE68FD8:3861493\r\n"

        with mock.patch.object(hibp, "_get", fake_get):
            self.assertEqual(hibp.pwned_password_count("password"), 3861493)
        self.assertTrue(seen["url"].endswith("/range/5BAA6"))


class ReportTests(unittest.TestCase):
    def test_html_escapes_untrusted_subjects(self):
        ev = Event("email", "me@x.com", "a@evil.com", "<script>alert(1)</script> welcome",
                   datetime.now(timezone.utc), C.SIGNUP, "evil.com", "other", False)
        with tempfile.TemporaryDirectory() as d:
            j, h = write_reports(Path(d), [ev], build_inventory([ev]), [], ["me@x.com"])
            html = h.read_text(encoding="utf-8")
            self.assertNotIn("<script>alert", html)
            self.assertIn("&lt;script&gt;", html)
            self.assertEqual(json.loads(j.read_text(encoding="utf-8"))["accounts"][0]["status"],
                             "active")


class VerifyTests(unittest.TestCase):
    def setUp(self):
        from ayakizi import verify
        self.v = verify
        self.cfg = verify.SmtpConfig("me@gmail.com", "pw", "smtp.gmail.com", 465)
        self.sent = {}

    def _sender(self, cfg, to, code):
        self.sent.update(to=to, code=code)

    def test_correct_code(self):
        ok = self.v.verify_email("a@x.com", self.cfg, prompt=lambda _: self.sent["code"],
                                 sender=self._sender)
        self.assertTrue(ok)
        self.assertEqual(self.sent["to"], "a@x.com")
        self.assertRegex(self.sent["code"], r"^\d{6}$")

    def test_wrong_code_limited_attempts(self):
        calls = []
        ok = self.v.verify_email("a@x.com", self.cfg,
                                 prompt=lambda _: calls.append(1) or "000000x",
                                 sender=self._sender)
        self.assertFalse(ok)
        self.assertEqual(len(calls), self.v.MAX_ATTEMPTS)

    def test_expired_code(self):
        t = iter([0, self.v.CODE_TTL_SECONDS + 1])
        ok = self.v.verify_email("a@x.com", self.cfg, prompt=lambda _: self.sent["code"],
                                 sender=self._sender, clock=lambda: next(t))
        self.assertFalse(ok)

    def test_config_from_env(self):
        cfg = self.v.SmtpConfig.from_env({"AYAKIZI_SMTP_USER": "me@outlook.com",
                                          "AYAKIZI_SMTP_PASSWORD": "x"})
        self.assertEqual((cfg.host, cfg.port), ("smtp.office365.com", 587))
        with self.assertRaises(self.v.VerificationError):
            self.v.SmtpConfig.from_env({})


class CliTests(unittest.TestCase):
    def test_parse_sms_arg(self):
        from ayakizi.cli import _parse_sms_arg
        self.assertEqual(_parse_sms_arg("a.xml=+905551112233", None), ("a.xml", "+905551112233"))
        self.assertEqual(_parse_sms_arg("a.xml", "+90"), ("a.xml", "+90"))
        with self.assertRaises(ValueError):
            _parse_sms_arg("a.xml", None)

    def test_hibp_only_for_verified_addresses(self):
        from ayakizi import cli
        checked = []
        env = {"AYAKIZI_SMTP_USER": "me@gmail.com", "AYAKIZI_SMTP_PASSWORD": "x",
               "HIBP_API_KEY": "k"}
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.dict(cli.os.environ, env), \
                mock.patch.object(cli, "verify_email", lambda addr, cfg: addr == "ok@x.com"), \
                mock.patch("ayakizi.core.breached_account",
                                  lambda addr, key: checked.append(addr) or []):
            rc = cli.main(["scan", "--verify-email", "ok@x.com", "--verify-email", "bad@x.com",
                           "--hibp", "--out", d])
        self.assertEqual(rc, 0)
        self.assertEqual(checked, ["ok@x.com"])


if __name__ == "__main__":
    unittest.main()
