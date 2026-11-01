"""Yerel web uygulaması: `ayakizi app`.

Sunucu yalnızca 127.0.0.1'e bağlanır. Şifreler, SMTP bilgileri, SMS yedekleri ve
sonuçlar yalnızca bellekte tutulur; diske yazılmaz (rapor indirmeyi siz seçerseniz
tarayıcı kaydeder).

Güvenlik:
* Host başlığı yalnızca 127.0.0.1/localhost olabilir (DNS rebinding'e karşı).
* Tüm API çağrıları rastgele bir oturum anahtarı (X-Ayakizi-Token) ister; özel
  başlık tarayıcıyı CORS ön kontrolüne zorlar ve sunucu buna izin vermez, bu
  yüzden başka bir web sitesi API'yi çağıramaz.
* Sayfa çerçeve içine alınamaz (clickjacking'e karşı).
"""

from __future__ import annotations

import io
import json
import secrets
import threading
import webbrowser
from datetime import date
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .core import ImapAccount, ScanResult, SmsBackup, run_scan
from .hibp import HIBPError, pwned_password_count
from .report import build_data, render_html
from .verify import OtpStore, SmtpConfig, VerificationError

STATIC = Path(__file__).with_name("static")
MAX_JSON = 1 * 1024 * 1024
MAX_UPLOAD = 200 * 1024 * 1024


class AppState:
    def __init__(self, otp: OtpStore | None = None) -> None:
        self.lock = threading.Lock()
        self.token = secrets.token_urlsafe(32)
        self.smtp: SmtpConfig | None = None
        self.hibp_key: str | None = None
        self.otp = otp or OtpStore()
        self.sms: dict[str, dict] = {}
        self.job_status = "idle"
        self.job_log: list[str] = []
        self.result: ScanResult | None = None
        self.data: dict | None = None

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "smtp_configured": self.smtp is not None,
                "smtp_user": self.smtp.user if self.smtp else None,
                "hibp_configured": bool(self.hibp_key),
                "verified": sorted(self.otp.verified),
                "sms": [{"id": k, "name": v["name"], "phone": v["phone"], "size": len(v["data"])}
                        for k, v in self.sms.items()],
                "job": {"status": self.job_status, "log": self.job_log[-200:]},
                "result": self.data,
            }


class ApiError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def make_handler(state: AppState, port_ref: dict):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ayakizi"
        sys_version = ""

        def log_message(self, fmt, *args):  # sessiz
            pass

        # ---- yardımcılar -------------------------------------------------
        def _host_ok(self) -> bool:
            host = (self.headers.get("Host") or "").lower()
            port = port_ref["port"]
            return host in {f"127.0.0.1:{port}", f"localhost:{port}"}

        def _send(self, status: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
                "connect-src 'self'; img-src data:; frame-ancestors 'none'; base-uri 'none'; "
                "form-action 'none'")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status: int, obj) -> None:
            self._send(status, json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                       "application/json; charset=utf-8")

        def _read_body(self, limit: int) -> bytes:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise ApiError(400, "Geçersiz Content-Length")
            if length > limit:
                raise ApiError(413, "İstek çok büyük")
            return self.rfile.read(length)

        def _read_json(self) -> dict:
            if not (self.headers.get("Content-Type") or "").startswith("application/json"):
                raise ApiError(415, "JSON bekleniyor")
            try:
                obj = json.loads(self._read_body(MAX_JSON) or b"{}")
            except json.JSONDecodeError:
                raise ApiError(400, "Geçersiz JSON")
            if not isinstance(obj, dict):
                raise ApiError(400, "Geçersiz JSON")
            return obj

        def _token_ok(self, query: dict) -> bool:
            given = self.headers.get("X-Ayakizi-Token") or (query.get("t") or [""])[0]
            return secrets.compare_digest(given, state.token)

        # ---- yönlendirme -------------------------------------------------
        def do_GET(self):
            if not self._host_ok():
                return self._send(403, b"forbidden", "text/plain")
            url = urlparse(self.path)
            q = parse_qs(url.query)
            if url.path == "/":
                html = (STATIC / "index.html").read_text(encoding="utf-8")
                html = html.replace("__AYAKIZI_TOKEN__", state.token)
                return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
            if not self._token_ok(q):
                return self._send(403, b"forbidden", "text/plain")
            if url.path == "/api/state":
                return self._json(200, state.snapshot())
            if url.path in ("/report", "/report.json"):
                res = state.result
                if res is None:
                    return self._send(404, "Henüz rapor yok".encode(), "text/plain; charset=utf-8")
                if url.path == "/report":
                    return self._send(200, render_html(res.inventory, res.breaches, res.scanned)
                                      .encode("utf-8"), "text/html; charset=utf-8")
                body = json.dumps(build_data(res.events, res.inventory, res.breaches, res.scanned),
                                  ensure_ascii=False, indent=2).encode("utf-8")
                return self._send(200, body, "application/json; charset=utf-8",
                                  {"Content-Disposition": 'attachment; filename="ayakizi-rapor.json"'})
            return self._send(404, b"not found", "text/plain")

        def do_POST(self):
            if not self._host_ok():
                return self._send(403, b"forbidden", "text/plain")
            url = urlparse(self.path)
            q = parse_qs(url.query)
            if not secrets.compare_digest(self.headers.get("X-Ayakizi-Token") or "", state.token):
                return self._json(403, {"error": "Geçersiz oturum anahtarı"})
            routes = {
                "/api/settings": self.api_settings,
                "/api/otp/send": self.api_otp_send,
                "/api/otp/check": self.api_otp_check,
                "/api/sms": lambda: self.api_sms_upload(q),
                "/api/sms/remove": self.api_sms_remove,
                "/api/scan": self.api_scan,
                "/api/password": self.api_password,
                "/api/reset": self.api_reset,
                "/api/quit": self.api_quit,
            }
            fn = routes.get(url.path)
            if fn is None:
                return self._json(404, {"error": "Bulunamadı"})
            try:
                status, obj = fn()
            except ApiError as e:
                status, obj = e.status, {"error": str(e)}
            except Exception as e:  # beklenmeyen hata: ayrıntıyı yerel kullanıcıya göster
                status, obj = 500, {"error": f"Beklenmeyen hata: {e}"}
            self._json(status, obj)

        def do_OPTIONS(self):  # CORS ön kontrolüne izin verme
            self._send(405, b"", "text/plain")

        # ---- API ---------------------------------------------------------
        def api_settings(self):
            body = self._read_json()
            with state.lock:
                if "smtp_user" in body:
                    user = str(body.get("smtp_user") or "").strip()
                    pw = str(body.get("smtp_password") or "")
                    if user and pw:
                        env = {"AYAKIZI_SMTP_USER": user, "AYAKIZI_SMTP_PASSWORD": pw,
                               "AYAKIZI_SMTP_HOST": str(body.get("smtp_host") or ""),
                               "AYAKIZI_SMTP_PORT": str(body.get("smtp_port") or "")}
                        try:
                            state.smtp = SmtpConfig.from_env(env)
                        except (VerificationError, ValueError) as e:
                            raise ApiError(400, str(e))
                    elif not user:
                        state.smtp = None
                if "hibp_key" in body:
                    state.hibp_key = str(body.get("hibp_key") or "").strip() or None
            return 200, {"ok": True}

        def api_otp_send(self):
            address = str(self._read_json().get("address") or "").strip().lower()
            if "@" not in address or len(address) > 254:
                raise ApiError(400, "Geçerli bir e-posta adresi girin.")
            if state.smtp is None:
                raise ApiError(400, "Önce Ayarlar'dan kod gönderecek e-posta hesabını girin.")
            try:
                state.otp.issue(address, state.smtp)
            except VerificationError as e:
                raise ApiError(502, str(e))
            return 200, {"ok": True, "message": f"Kod {address} adresine gönderildi."}

        def api_otp_check(self):
            body = self._read_json()
            with state.lock:
                ok, msg = state.otp.check(str(body.get("address") or ""), str(body.get("code") or ""))
            return 200, {"ok": ok, "message": msg}

        def api_sms_upload(self, q):
            phone = (q.get("phone") or [""])[0].strip()
            name = (q.get("name") or ["sms.xml"])[0][:120]
            if not phone.lstrip("+").replace(" ", "").isdigit():
                raise ApiError(400, "Telefon numarasını +905551112233 biçiminde girin.")
            data = self._read_body(MAX_UPLOAD)
            if not data:
                raise ApiError(400, "Dosya boş.")
            sid = secrets.token_hex(6)
            with state.lock:
                state.sms[sid] = {"name": name, "phone": phone.replace(" ", ""), "data": data}
            return 200, {"ok": True, "id": sid}

        def api_sms_remove(self):
            sid = str(self._read_json().get("id") or "")
            with state.lock:
                state.sms.pop(sid, None)
            return 200, {"ok": True}

        def api_scan(self):
            body = self._read_json()
            accounts = []
            for item in body.get("imap") or []:
                if not isinstance(item, dict):
                    continue
                address = str(item.get("address") or "").strip()
                password = str(item.get("password") or "")
                if "@" in address and password:
                    accounts.append(ImapAccount(address, password,
                                                str(item.get("host") or "").strip() or None))
            since = None
            if body.get("since"):
                try:
                    since = date.fromisoformat(str(body["since"]))
                except ValueError:
                    raise ApiError(400, "Tarih YYYY-AA-GG biçiminde olmalı.")
            with state.lock:
                if state.job_status == "running":
                    raise ApiError(409, "Bir tarama zaten çalışıyor.")
                backups = [SmsBackup(io.BytesIO(v["data"]), v["phone"], v["name"])
                           for v in state.sms.values()]
                verified = sorted(state.otp.verified)
                if not accounts and not backups and not verified:
                    raise ApiError(400, "Taranacak e-posta hesabı, doğrulanmış adres ya da SMS yedeği yok.")
                hibp_key = state.hibp_key if body.get("hibp", True) else None
                state.job_status = "running"
                state.job_log = []

            def log(msg: str) -> None:
                with state.lock:
                    state.job_log.append(msg)

            def worker():
                try:
                    res = run_scan(accounts, verified, backups, since, hibp_key, log)
                    data = build_data(res.events, res.inventory, res.breaches, res.scanned)
                    data.pop("events", None)  # arayüz için gereksiz; JSON indirmede var
                    data["errors"] = res.errors
                    with state.lock:
                        state.result, state.data, state.job_status = res, data, "done"
                except Exception as e:
                    log(f"! Tarama durdu: {e}")
                    with state.lock:
                        state.job_status = "error"

            threading.Thread(target=worker, daemon=True).start()
            return 202, {"ok": True}

        def api_password(self):
            pw = str(self._read_json().get("password") or "")
            if not pw:
                raise ApiError(400, "Şifre girin.")
            try:
                return 200, {"count": pwned_password_count(pw)}
            except HIBPError as e:
                raise ApiError(502, str(e))

        def api_reset(self):
            with state.lock:
                state.sms.clear()
                state.result = state.data = None
                state.job_status, state.job_log = "idle", []
            return 200, {"ok": True}

        def api_quit(self):
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return 200, {"ok": True}

    return Handler


def create_server(port: int = 8765, state: AppState | None = None) -> tuple[ThreadingHTTPServer, AppState]:
    state = state or AppState()
    port_ref = {"port": port}
    try:
        server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(state, port_ref))
    except OSError:
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(state, port_ref))
    port_ref["port"] = server.server_address[1]
    return server, state


def serve(port: int = 8765, open_browser: bool = True) -> None:
    server, _state = create_server(port)
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    print(f"ayakizi çalışıyor: {url}  (kapatmak için Ctrl+C)")
    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
