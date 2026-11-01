"""Bilinen servis kataloğu: gönderici alan adları ve SMS anahtar kelimeleri.

Katalog yalnızca *kullanıcının kendi* e-posta kutusundaki / SMS yedeğindeki
mesajları bir servise eşlemek için kullanılır; hiçbir servise istek atılmaz.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Service:
    name: str
    category: str
    domains: tuple[str, ...]
    sms_keywords: tuple[str, ...] = field(default=())

    def keywords(self) -> tuple[str, ...]:
        return self.sms_keywords or (self.name.lower(),)


CATEGORY_LABELS = {
    "dating": "Arkadaşlık / Flört",
    "social": "Sosyal medya",
    "shopping": "Alışveriş",
    "food": "Yemek / Ulaşım",
    "finance": "Finans / Kripto",
    "travel": "Seyahat",
    "streaming": "Dijital içerik",
    "gaming": "Oyun",
    "tech": "Teknoloji / Üretkenlik",
    "other": "Diğer",
}

CATEGORY_ORDER = list(CATEGORY_LABELS)


def _s(name: str, category: str, *domains: str, sms: tuple[str, ...] = ()) -> Service:
    return Service(name, category, tuple(domains), sms)


CATALOG: tuple[Service, ...] = (
    # Arkadaşlık / flört
    _s("Tinder", "dating", "gotinder.com", "tinder.com"),
    _s("Bumble", "dating", "bumble.com"),
    _s("Hinge", "dating", "hinge.co"),
    _s("OkCupid", "dating", "okcupid.com"),
    _s("Badoo", "dating", "badoo.com"),
    _s("Happn", "dating", "happn.com", "happn.fr"),
    _s("Grindr", "dating", "grindr.com"),
    _s("Match", "dating", "match.com", sms=("match.com",)),
    _s("Plenty of Fish", "dating", "pof.com", sms=("plenty of fish", "pof")),
    _s("Feeld", "dating", "feeld.co"),
    _s("Lovoo", "dating", "lovoo.com"),
    _s("Meetic", "dating", "meetic.com", "meetic.fr"),
    _s("Coffee Meets Bagel", "dating", "coffeemeetsbagel.com", sms=("coffee meets bagel",)),
    _s("HER", "dating", "weareher.com", sms=("weareher",)),
    _s("Taimi", "dating", "taimi.com"),
    _s("Boo", "dating", "boo.world", sms=("boo.world",)),
    # Sosyal medya
    _s("Facebook", "social", "facebookmail.com", "facebook.com", "meta.com"),
    _s("Instagram", "social", "instagram.com", "mail.instagram.com"),
    _s("X (Twitter)", "social", "x.com", "twitter.com", sms=("twitter", " x ")),
    _s("TikTok", "social", "tiktok.com", "tiktokv.com"),
    _s("Snapchat", "social", "snapchat.com"),
    _s("LinkedIn", "social", "linkedin.com"),
    _s("Reddit", "social", "reddit.com", "redditmail.com"),
    _s("Pinterest", "social", "pinterest.com"),
    _s("Tumblr", "social", "tumblr.com"),
    _s("Discord", "social", "discord.com", "discordapp.com"),
    _s("Telegram", "social", "telegram.org"),
    _s("Twitch", "social", "twitch.tv"),
    _s("VK", "social", "vk.com", sms=("vk.com", "vkontakte")),
    _s("Quora", "social", "quora.com"),
    _s("Threads", "social", "threads.net"),
    _s("Bluesky", "social", "bsky.app", "blueskyweb.xyz"),
    _s("WhatsApp", "social", "whatsapp.com"),
    # Alışveriş
    _s("Amazon", "shopping", "amazon.com", "amazon.com.tr", "amazon.de", "amazon.co.uk"),
    _s("Trendyol", "shopping", "trendyol.com"),
    _s("Hepsiburada", "shopping", "hepsiburada.com"),
    _s("n11", "shopping", "n11.com"),
    _s("Çiçeksepeti", "shopping", "ciceksepeti.com", sms=("ciceksepeti", "çiçeksepeti")),
    _s("AliExpress", "shopping", "aliexpress.com"),
    _s("Temu", "shopping", "temu.com"),
    _s("Shein", "shopping", "shein.com"),
    _s("eBay", "shopping", "ebay.com"),
    _s("Etsy", "shopping", "etsy.com"),
    _s("Sahibinden", "shopping", "sahibinden.com"),
    _s("Dolap", "shopping", "dolap.com"),
    _s("Letgo", "shopping", "letgo.com"),
    # Yemek / ulaşım
    _s("Yemeksepeti", "food", "yemeksepeti.com"),
    _s("Getir", "food", "getir.com"),
    _s("Uber", "food", "uber.com"),
    _s("Bolt", "food", "bolt.eu"),
    _s("Trendyol Yemek", "food", "trendyolyemek.com", sms=("trendyol yemek",)),
    # Finans / kripto
    _s("PayPal", "finance", "paypal.com"),
    _s("Papara", "finance", "papara.com"),
    _s("Wise", "finance", "wise.com", "transferwise.com"),
    _s("Revolut", "finance", "revolut.com"),
    _s("Binance", "finance", "binance.com", "binance.tr"),
    _s("Coinbase", "finance", "coinbase.com"),
    _s("BtcTurk", "finance", "btcturk.com"),
    _s("Paribu", "finance", "paribu.com"),
    _s("Stripe", "finance", "stripe.com"),
    # Seyahat
    _s("Airbnb", "travel", "airbnb.com"),
    _s("Booking.com", "travel", "booking.com", sms=("booking.com",)),
    _s("Pegasus", "travel", "flypgs.com"),
    _s("Türk Hava Yolları", "travel", "thy.com", "turkishairlines.com", sms=("thy", "turkish airlines", "miles&smiles")),
    _s("Obilet", "travel", "obilet.com"),
    _s("Enuygun", "travel", "enuygun.com"),
    _s("BlaBlaCar", "travel", "blablacar.com", "blablacar.com.tr"),
    _s("Expedia", "travel", "expedia.com"),
    # Dijital içerik
    _s("Netflix", "streaming", "netflix.com"),
    _s("Spotify", "streaming", "spotify.com"),
    _s("Disney+", "streaming", "disneyplus.com", sms=("disney+", "disneyplus")),
    _s("Exxen", "streaming", "exxen.com"),
    _s("BluTV", "streaming", "blutv.com"),
    _s("Deezer", "streaming", "deezer.com"),
    _s("YouTube", "streaming", "youtube.com"),
    # Oyun
    _s("Steam", "gaming", "steampowered.com", "steamcommunity.com"),
    _s("Epic Games", "gaming", "epicgames.com"),
    _s("Riot Games", "gaming", "riotgames.com"),
    _s("Ubisoft", "gaming", "ubisoft.com"),
    _s("EA", "gaming", "ea.com", sms=("electronic arts",)),
    _s("PlayStation", "gaming", "playstation.com", "sonyentertainmentnetwork.com"),
    _s("Roblox", "gaming", "roblox.com"),
    _s("Battle.net", "gaming", "battle.net", "blizzard.com", sms=("battle.net", "blizzard")),
    # Teknoloji / üretkenlik
    _s("Google", "tech", "google.com", "accounts.google.com"),
    _s("Microsoft", "tech", "microsoft.com", "accountprotection.microsoft.com", "live.com"),
    _s("Apple", "tech", "apple.com", "id.apple.com", sms=("apple id", "apple hesab")),
    _s("Dropbox", "tech", "dropbox.com", "dropboxmail.com"),
    _s("GitHub", "tech", "github.com"),
    _s("Zoom", "tech", "zoom.us"),
    _s("Slack", "tech", "slack.com"),
    _s("Notion", "tech", "notion.so", "mail.notion.so"),
    _s("Canva", "tech", "canva.com"),
    _s("Adobe", "tech", "adobe.com"),
    _s("Yahoo", "tech", "yahoo.com", "yahoo-inc.com"),
    _s("Proton", "tech", "proton.me", "protonmail.com"),
    _s("OpenAI", "tech", "openai.com", "tm.openai.com"),
    _s("Duolingo", "tech", "duolingo.com"),
)

# İki seviyeli genel son ekler (registrable domain hesaplamak için küçük bir liste).
_SECOND_LEVEL_SUFFIXES = {
    "com.tr", "org.tr", "net.tr", "gov.tr", "edu.tr", "gen.tr", "biz.tr", "info.tr",
    "co.uk", "org.uk", "ac.uk", "com.au", "net.au", "com.br", "co.jp", "co.kr",
    "com.mx", "co.in", "co.za", "com.cn", "com.sg", "co.nz",
}

_DOMAIN_INDEX: dict[str, Service] = {d: s for s in CATALOG for d in s.domains}


def registrable_domain(domain: str) -> str:
    """`mail.service.example.com.tr` -> `example.com.tr` (yaklaşık)."""
    labels = [p for p in domain.lower().strip(".").split(".") if p]
    if len(labels) <= 2:
        return ".".join(labels)
    if ".".join(labels[-2:]) in _SECOND_LEVEL_SUFFIXES:
        return ".".join(labels[-3:])
    return ".".join(labels[-2:])


def match_domain(domain: str) -> Service | None:
    """Gönderici alan adını (alt alan adları dahil) katalogdaki servise eşler."""
    domain = domain.lower().strip(".")
    labels = domain.split(".")
    for i in range(len(labels) - 1):
        candidate = ".".join(labels[i:])
        if candidate in _DOMAIN_INDEX:
            return _DOMAIN_INDEX[candidate]
    return None


def match_text(text: str) -> Service | None:
    """SMS gövdesi / gönderici kimliği içinde servis adını arar."""
    haystack = f" {text.lower()} "
    best: Service | None = None
    best_len = 0
    for service in CATALOG:
        for kw in service.keywords():
            kw_l = kw.lower()
            if kw_l.strip() != kw_l:
                found = kw_l in haystack
            else:
                found = _word_in(kw_l, haystack)
            # En uzun eşleşme kazanır ("trendyol yemek" > "trendyol").
            if found and len(kw_l) > best_len:
                best, best_len = service, len(kw_l)
    return best


def _word_in(word: str, haystack: str) -> bool:
    start = 0
    while True:
        idx = haystack.find(word, start)
        if idx < 0:
            return False
        before = haystack[idx - 1] if idx > 0 else " "
        after_i = idx + len(word)
        after = haystack[after_i] if after_i < len(haystack) else " "
        if not before.isalnum() and not after.isalnum():
            return True
        start = idx + 1
