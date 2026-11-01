// Bu katalog ayakizi/services.py ile aynıdır.
// Yalnızca kullanıcının KENDİ e-postalarını / SMS'lerini bir servise eşlemek
// için kullanılır; hiçbir servise istek atılmaz.

class Service {
  const Service(this.name, this.category, this.domains, {this.sms = const []});

  final String name;
  final String category;
  final List<String> domains;
  final List<String> sms;

  List<String> get keywords => sms.isNotEmpty ? sms : [name.toLowerCase()];
}

const Map<String, String> categoryLabels = {
  'dating': 'Arkadaşlık / Flört',
  'social': 'Sosyal medya',
  'shopping': 'Alışveriş',
  'food': 'Yemek / Ulaşım',
  'finance': 'Finans / Kripto',
  'travel': 'Seyahat',
  'streaming': 'Dijital içerik',
  'gaming': 'Oyun',
  'tech': 'Teknoloji / Üretkenlik',
  'other': 'Diğer',
};

final List<String> categoryOrder = categoryLabels.keys.toList();

const List<Service> catalog = [
  Service('Tinder', 'dating', ['gotinder.com', 'tinder.com']),
  Service('Bumble', 'dating', ['bumble.com']),
  Service('Hinge', 'dating', ['hinge.co']),
  Service('OkCupid', 'dating', ['okcupid.com']),
  Service('Badoo', 'dating', ['badoo.com']),
  Service('Happn', 'dating', ['happn.com', 'happn.fr']),
  Service('Grindr', 'dating', ['grindr.com']),
  Service('Match', 'dating', ['match.com'], sms: ['match.com']),
  Service('Plenty of Fish', 'dating', ['pof.com'], sms: ['plenty of fish', 'pof']),
  Service('Feeld', 'dating', ['feeld.co']),
  Service('Lovoo', 'dating', ['lovoo.com']),
  Service('Meetic', 'dating', ['meetic.com', 'meetic.fr']),
  Service('Coffee Meets Bagel', 'dating', ['coffeemeetsbagel.com'], sms: ['coffee meets bagel']),
  Service('HER', 'dating', ['weareher.com'], sms: ['weareher']),
  Service('Taimi', 'dating', ['taimi.com']),
  Service('Boo', 'dating', ['boo.world'], sms: ['boo.world']),
  Service('Facebook', 'social', ['facebookmail.com', 'facebook.com', 'meta.com']),
  Service('Instagram', 'social', ['instagram.com', 'mail.instagram.com']),
  Service('X (Twitter)', 'social', ['x.com', 'twitter.com'], sms: ['twitter', ' x ']),
  Service('TikTok', 'social', ['tiktok.com', 'tiktokv.com']),
  Service('Snapchat', 'social', ['snapchat.com']),
  Service('LinkedIn', 'social', ['linkedin.com']),
  Service('Reddit', 'social', ['reddit.com', 'redditmail.com']),
  Service('Pinterest', 'social', ['pinterest.com']),
  Service('Tumblr', 'social', ['tumblr.com']),
  Service('Discord', 'social', ['discord.com', 'discordapp.com']),
  Service('Telegram', 'social', ['telegram.org']),
  Service('Twitch', 'social', ['twitch.tv']),
  Service('VK', 'social', ['vk.com'], sms: ['vk.com', 'vkontakte']),
  Service('Quora', 'social', ['quora.com']),
  Service('Threads', 'social', ['threads.net']),
  Service('Bluesky', 'social', ['bsky.app', 'blueskyweb.xyz']),
  Service('WhatsApp', 'social', ['whatsapp.com']),
  Service('Amazon', 'shopping', ['amazon.com', 'amazon.com.tr', 'amazon.de', 'amazon.co.uk']),
  Service('Trendyol', 'shopping', ['trendyol.com']),
  Service('Hepsiburada', 'shopping', ['hepsiburada.com']),
  Service('n11', 'shopping', ['n11.com']),
  Service('Çiçeksepeti', 'shopping', ['ciceksepeti.com'], sms: ['ciceksepeti', 'çiçeksepeti']),
  Service('AliExpress', 'shopping', ['aliexpress.com']),
  Service('Temu', 'shopping', ['temu.com']),
  Service('Shein', 'shopping', ['shein.com']),
  Service('eBay', 'shopping', ['ebay.com']),
  Service('Etsy', 'shopping', ['etsy.com']),
  Service('Sahibinden', 'shopping', ['sahibinden.com']),
  Service('Dolap', 'shopping', ['dolap.com']),
  Service('Letgo', 'shopping', ['letgo.com']),
  Service('Yemeksepeti', 'food', ['yemeksepeti.com']),
  Service('Getir', 'food', ['getir.com']),
  Service('Uber', 'food', ['uber.com']),
  Service('Bolt', 'food', ['bolt.eu']),
  Service('Trendyol Yemek', 'food', ['trendyolyemek.com'], sms: ['trendyol yemek']),
  Service('PayPal', 'finance', ['paypal.com']),
  Service('Papara', 'finance', ['papara.com']),
  Service('Wise', 'finance', ['wise.com', 'transferwise.com']),
  Service('Revolut', 'finance', ['revolut.com']),
  Service('Binance', 'finance', ['binance.com', 'binance.tr']),
  Service('Coinbase', 'finance', ['coinbase.com']),
  Service('BtcTurk', 'finance', ['btcturk.com']),
  Service('Paribu', 'finance', ['paribu.com']),
  Service('Stripe', 'finance', ['stripe.com']),
  Service('Airbnb', 'travel', ['airbnb.com']),
  Service('Booking.com', 'travel', ['booking.com'], sms: ['booking.com']),
  Service('Pegasus', 'travel', ['flypgs.com']),
  Service('Türk Hava Yolları', 'travel', ['thy.com', 'turkishairlines.com'], sms: ['thy', 'turkish airlines', 'miles&smiles']),
  Service('Obilet', 'travel', ['obilet.com']),
  Service('Enuygun', 'travel', ['enuygun.com']),
  Service('BlaBlaCar', 'travel', ['blablacar.com', 'blablacar.com.tr']),
  Service('Expedia', 'travel', ['expedia.com']),
  Service('Netflix', 'streaming', ['netflix.com']),
  Service('Spotify', 'streaming', ['spotify.com']),
  Service('Disney+', 'streaming', ['disneyplus.com'], sms: ['disney+', 'disneyplus']),
  Service('Exxen', 'streaming', ['exxen.com']),
  Service('BluTV', 'streaming', ['blutv.com']),
  Service('Deezer', 'streaming', ['deezer.com']),
  Service('YouTube', 'streaming', ['youtube.com']),
  Service('Steam', 'gaming', ['steampowered.com', 'steamcommunity.com']),
  Service('Epic Games', 'gaming', ['epicgames.com']),
  Service('Riot Games', 'gaming', ['riotgames.com']),
  Service('Ubisoft', 'gaming', ['ubisoft.com']),
  Service('EA', 'gaming', ['ea.com'], sms: ['electronic arts']),
  Service('PlayStation', 'gaming', ['playstation.com', 'sonyentertainmentnetwork.com']),
  Service('Roblox', 'gaming', ['roblox.com']),
  Service('Battle.net', 'gaming', ['battle.net', 'blizzard.com'], sms: ['battle.net', 'blizzard']),
  Service('Google', 'tech', ['google.com', 'accounts.google.com']),
  Service('Microsoft', 'tech', ['microsoft.com', 'accountprotection.microsoft.com', 'live.com']),
  Service('Apple', 'tech', ['apple.com', 'id.apple.com'], sms: ['apple id', 'apple hesab']),
  Service('Dropbox', 'tech', ['dropbox.com', 'dropboxmail.com']),
  Service('GitHub', 'tech', ['github.com']),
  Service('Zoom', 'tech', ['zoom.us']),
  Service('Slack', 'tech', ['slack.com']),
  Service('Notion', 'tech', ['notion.so', 'mail.notion.so']),
  Service('Canva', 'tech', ['canva.com']),
  Service('Adobe', 'tech', ['adobe.com']),
  Service('Yahoo', 'tech', ['yahoo.com', 'yahoo-inc.com']),
  Service('Proton', 'tech', ['proton.me', 'protonmail.com']),
  Service('OpenAI', 'tech', ['openai.com', 'tm.openai.com']),
  Service('Duolingo', 'tech', ['duolingo.com']),
];

const Set<String> _secondLevelSuffixes = {
  'com.tr', 'org.tr', 'net.tr', 'gov.tr', 'edu.tr', 'gen.tr', 'biz.tr', 'info.tr',
  'co.uk', 'org.uk', 'ac.uk', 'com.au', 'net.au', 'com.br', 'co.jp', 'co.kr',
  'com.mx', 'co.in', 'co.za', 'com.cn', 'com.sg', 'co.nz',
};

final Map<String, Service> _domainIndex = {
  for (final s in catalog)
    for (final d in s.domains) d: s,
};

/// `mail.service.example.com.tr` -> `example.com.tr` (yaklaşık).
String registrableDomain(String domain) {
  final labels = domain.toLowerCase().split('.').where((p) => p.isNotEmpty).toList();
  if (labels.length <= 2) return labels.join('.');
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  if (_secondLevelSuffixes.contains(lastTwo)) {
    return labels.sublist(labels.length - 3).join('.');
  }
  return lastTwo;
}

/// Gönderici alan adını (alt alan adları dahil) katalogdaki servise eşler.
Service? matchDomain(String domain) {
  final labels = domain.toLowerCase().split('.').where((p) => p.isNotEmpty).toList();
  for (var i = 0; i < labels.length - 1; i++) {
    final s = _domainIndex[labels.sublist(i).join('.')];
    if (s != null) return s;
  }
  return null;
}

/// SMS gövdesi / gönderici kimliği içinde servis adını arar (en uzun eşleşme kazanır).
Service? matchText(String text) {
  final haystack = ' ${text.toLowerCase()} ';
  Service? best;
  var bestLen = 0;
  for (final service in catalog) {
    for (final kw in service.keywords) {
      final k = kw.toLowerCase();
      final found = k.trim() != k ? haystack.contains(k) : _wordIn(k, haystack);
      if (found && k.length > bestLen) {
        best = service;
        bestLen = k.length;
      }
    }
  }
  return best;
}

bool _isAlnum(String ch) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);

bool _wordIn(String word, String haystack) {
  var start = 0;
  while (true) {
    final idx = haystack.indexOf(word, start);
    if (idx < 0) return false;
    final before = idx > 0 ? haystack[idx - 1] : ' ';
    final afterI = idx + word.length;
    final after = afterI < haystack.length ? haystack[afterI] : ' ';
    if (!_isAlnum(before) && !_isAlnum(after)) return true;
    start = idx + 1;
  }
}
