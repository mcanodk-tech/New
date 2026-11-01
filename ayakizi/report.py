"""JSON + bağımsız (tek dosya) HTML rapor üretimi."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from html import escape
from pathlib import Path

from .classify import EVENT_LABELS
from .models import STATUS_LABELS, AccountRecord, Event
from .services import CATEGORY_LABELS, CATEGORY_ORDER

KVKK_TEMPLATE = """Konu: KVKK md. 11 kapsamında kişisel verilerimin silinmesi talebi

Sayın {service} Veri Sorumlusu,

6698 sayılı Kişisel Verilerin Korunması Kanunu'nun 11. maddesi ve 7. maddesi
uyarınca, {account} hesabı/iletişim bilgisi ile ilişkili tüm kişisel
verilerimin silinmesini veya yok edilmesini, varsa hesabımın kalıcı olarak
kapatılmasını ve verilerimin aktarıldığı üçüncü kişilere bu işlemin
bildirilmesini talep ediyorum.

Kanun'un 13. maddesi uyarınca talebimin en geç otuz gün içinde
sonuçlandırılmasını rica ederim.

Ad Soyad:
Tarih:
"""

GDPR_TEMPLATE = """Subject: Erasure request under Article 17 GDPR

Dear {service} Data Protection Officer,

Under Article 17 of the General Data Protection Regulation, I request the
erasure of all personal data you hold relating to {account}, the closure of
any associated account, and notification of this erasure to any recipients
under Article 19.

Please confirm completion within one month as required by Article 12(3).

Name:
Date:
"""


def write_reports(out_dir: Path, events: list[Event], inventory: list[AccountRecord],
                  breaches: list[dict], scanned: list[str]) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    inventory = sorted(
        inventory,
        key=lambda r: (CATEGORY_ORDER.index(r.category) if r.category in CATEGORY_ORDER else 99,
                       r.service.lower()))

    data = {
        "generated_at": now.isoformat(),
        "scanned": scanned,
        "accounts": [
            {
                "service": r.service,
                "category": r.category,
                "known_service": r.known,
                "status": r.status(now),
                "first_seen": r.first_seen.isoformat() if r.first_seen else None,
                "last_seen": r.last_seen.isoformat() if r.last_seen else None,
                "event_counts": r.counts,
                "linked_identities": sorted(r.accounts),
                "sources": sorted(r.sources),
                "sample_subjects": r.samples,
            }
            for r in inventory
        ],
        "breaches": breaches,
        "events": [e.to_dict() for e in events],
    }
    json_path = out_dir / "rapor.json"
    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    html_path = out_dir / "rapor.html"
    html_path.write_text(_render_html(inventory, breaches, scanned, now), encoding="utf-8")
    return json_path, html_path


def _fmt(d: datetime | None) -> str:
    return d.strftime("%Y-%m-%d") if d else "—"


def _render_html(inventory: list[AccountRecord], breaches: list[dict],
                 scanned: list[str], now: datetime) -> str:
    total = len(inventory)
    deleted = sum(1 for r in inventory if r.status(now) == "deleted")
    dating = sum(1 for r in inventory if r.category == "dating")

    rows = []
    for r in inventory:
        status = r.status(now)
        events = ", ".join(f"{escape(EVENT_LABELS.get(k, k))}: {v}" for k, v in sorted(r.counts.items()))
        samples = "<br>".join(escape(s) for s in r.samples)
        rows.append(
            f"<tr class='st-{status}'><td><b>{escape(r.service)}</b>"
            f"{'' if r.known else ' <span class=tag>katalog dışı</span>'}</td>"
            f"<td>{escape(CATEGORY_LABELS.get(r.category, r.category))}</td>"
            f"<td><span class='pill {status}'>{escape(STATUS_LABELS[status])}</span></td>"
            f"<td>{_fmt(r.first_seen)}</td><td>{_fmt(r.last_seen)}</td>"
            f"<td>{escape(', '.join(sorted(r.accounts)))}</td>"
            f"<td class=small>{events}<div class=muted>{samples}</div></td></tr>")

    breach_rows = "".join(
        f"<tr><td><b>{escape(str(b.get('title') or b.get('name')))}</b><div class=muted>"
        f"{escape(str(b.get('domain') or ''))}</div></td><td>{escape(str(b.get('breach_date') or ''))}</td>"
        f"<td>{escape(str(b.get('account')))}</td>"
        f"<td class=small>{escape(', '.join(b.get('data_classes') or []))}</td></tr>"
        for b in breaches)

    breach_section = (
        f"<table><thead><tr><th>Sızıntı</th><th>Tarih</th><th>Adres</th><th>Sızan veri</th>"
        f"</tr></thead><tbody>{breach_rows}</tbody></table>"
        if breaches else "<p class=muted>Sızıntı kontrolü yapılmadı ya da kayıt bulunamadı.</p>")

    return f"""<!doctype html>
<html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dijital Ayak İzi Raporu</title>
<style>
:root{{--bg:#f7f7f5;--fg:#1d1d1f;--muted:#6b6b70;--card:#fff;--line:#e3e3e0;
--red:#b42318;--green:#067647;--amber:#b54708}}
@media (prefers-color-scheme:dark){{:root{{--bg:#151517;--fg:#ececef;--muted:#9a9aa2;
--card:#1f1f23;--line:#2e2e33;--red:#f97066;--green:#47cd89;--amber:#fdb022}}}}
body{{background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,sans-serif;margin:0;padding:24px 16px}}
main{{max-width:1100px;margin:auto}} h1{{margin:0 0 4px}} h2{{margin-top:32px}}
.muted{{color:var(--muted)}} .small{{font-size:12px}}
.stats{{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}}
.stat{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 16px;min-width:140px}}
.stat b{{font-size:24px;display:block}}
.wrap{{overflow-x:auto}} table{{width:100%;border-collapse:collapse;background:var(--card)}}
th,td{{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{font-size:12px;color:var(--muted);font-weight:600}}
.pill{{font-size:12px;padding:2px 8px;border-radius:99px;border:1px solid currentColor;white-space:nowrap}}
.deleted{{color:var(--red)}} .active{{color:var(--green)}} .dormant{{color:var(--amber)}}
.tag{{font-size:11px;color:var(--muted);border:1px solid var(--line);border-radius:4px;padding:0 4px}}
pre{{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px;white-space:pre-wrap}}
</style></head><body><main>
<h1>Dijital Ayak İzi Raporu</h1>
<div class=muted>Oluşturulma: {now.strftime('%Y-%m-%d %H:%M UTC')} · Taranan: {escape(', '.join(scanned))}</div>
<div class=stats>
<div class=stat><b>{total}</b>tespit edilen hesap</div>
<div class=stat><b>{dating}</b>arkadaşlık uygulaması</div>
<div class=stat><b>{deleted}</b>silinmiş olabilir</div>
<div class=stat><b>{len(breaches)}</b>veri sızıntısı</div>
</div>
<p class=muted>Durumlar posta kutunuzdaki / SMS'lerinizdeki bildirimlerden tahmin edilir;
kesin değildir. Bildirim e-postasını sildiyseniz o hesap burada görünmez.</p>
<h2>Hesap envanteri</h2>
<div class=wrap><table><thead><tr><th>Servis</th><th>Kategori</th><th>Durum</th>
<th>İlk görülme</th><th>Son görülme</th><th>Bağlı kimlik</th><th>Olaylar</th></tr></thead>
<tbody>{''.join(rows) or '<tr><td colspan=7 class=muted>Kayıt bulunamadı.</td></tr>'}</tbody></table></div>
<h2>Veri sızıntıları (Have I Been Pwned)</h2>
<div class=wrap>{breach_section}</div>
<h2>Silme talebi şablonları</h2>
<p class=muted>Kullanmadığınız hesaplar için servisin gizlilik / KVKK iletişim adresine gönderin.</p>
<h3>KVKK (Türkiye)</h3><pre>{escape(KVKK_TEMPLATE)}</pre>
<h3>GDPR (AB)</h3><pre>{escape(GDPR_TEMPLATE)}</pre>
</main></body></html>
"""
