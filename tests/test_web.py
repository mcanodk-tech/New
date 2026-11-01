import json
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock

from ayakizi import web
from ayakizi.verify import OtpStore

SMS = b"""<?xml version='1.0' encoding='UTF-8'?><smses>
<sms address="TINDER" body="Your Tinder code is 123456" date="1600000000000" type="1"/>
<sms address="GETIR" body="Getir hesabiniz silindi." date="1650000000000" type="1"/>
</smses>"""


class WebTests(unittest.TestCase):
    def setUp(self):
        self.sent = {}
        otp = OtpStore(sender=lambda cfg, to, code: self.sent.update(to=to, code=code))
        self.server, self.state = web.create_server(0, web.AppState(otp))
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def req(self, path, body=None, raw=None, token=True, host=None, ctype=None):
        url = f"http://127.0.0.1:{self.port}{path}"
        headers = {}
        if token:
            headers["X-Ayakizi-Token"] = self.state.token
        if host:
            headers["Host"] = host
        data = None
        if raw is not None:
            data, headers["Content-Type"] = raw, "application/octet-stream"
        elif body is not None:
            data, headers["Content-Type"] = json.dumps(body).encode(), ctype or "application/json"
        r = urllib.request.Request(url, data=data, headers=headers,
                                   method="POST" if data is not None else "GET")
        try:
            with urllib.request.urlopen(r, timeout=5) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()

    def j(self, *a, **kw):
        status, body = self.req(*a, **kw)
        return status, json.loads(body)

    def test_index_has_token_and_security_headers(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/") as r:
            html = r.read().decode()
            self.assertIn(self.state.token, html)
            self.assertEqual(r.headers["X-Frame-Options"], "DENY")
            self.assertIn("frame-ancestors 'none'", r.headers["Content-Security-Policy"])

    def test_rejects_missing_token_and_foreign_host(self):
        self.assertEqual(self.req("/api/state", token=False)[0], 403)
        self.assertEqual(self.req("/api/reset", body={}, token=False)[0], 403)
        self.assertEqual(self.req("/", host="evil.example:80")[0], 403)
        # form-encoded (CORS'suz gönderilebilen) istek kabul edilmez
        self.assertEqual(self.req("/api/otp/check", body={}, ctype="text/plain")[0], 415)

    def test_otp_flow(self):
        s, r = self.j("/api/otp/send", {"address": "me@x.com"})
        self.assertEqual(s, 400)  # SMTP ayarı yok
        s, _ = self.j("/api/settings", {"smtp_user": "me@gmail.com", "smtp_password": "x"})
        self.assertEqual(s, 200)
        s, r = self.j("/api/otp/send", {"address": "Me@X.com"})
        self.assertEqual((s, self.sent["to"]), (200, "me@x.com"))
        s, r = self.j("/api/otp/check", {"address": "me@x.com", "code": "nope"})
        self.assertFalse(r["ok"])
        s, r = self.j("/api/otp/check", {"address": "me@x.com", "code": self.sent["code"]})
        self.assertTrue(r["ok"])
        self.assertEqual(self.j("/api/state")[1]["verified"], ["me@x.com"])

    def test_sms_upload_scan_and_report(self):
        s, r = self.j("/api/sms?phone=%2B905551112233&name=yedek.xml", raw=SMS)
        self.assertEqual(s, 200)
        self.assertEqual(self.j("/api/otp/send", {"address": "x"})[0], 400)
        with mock.patch("ayakizi.core.breached_account", lambda a, k: []):
            s, _ = self.j("/api/scan", {"imap": [], "hibp": False})
            self.assertEqual(s, 202)
            for _ in range(50):
                st = self.j("/api/state")[1]
                if st["job"]["status"] != "running":
                    break
                threading.Event().wait(0.05)
        self.assertEqual(st["job"]["status"], "done")
        services = {a["service"]: a["status"] for a in st["result"]["accounts"]}
        self.assertEqual(services, {"Tinder": "dormant", "Getir": "deleted"})
        self.assertNotIn("123456", json.dumps(st))  # OTP kodları sızmaz
        s, html = self.req(f"/report?t={self.state.token}", token=False)
        self.assertEqual(s, 200)
        self.assertIn(b"Tinder", html)

    def test_scan_requires_input(self):
        self.assertEqual(self.j("/api/scan", {"imap": []})[0], 400)


if __name__ == "__main__":
    unittest.main()
