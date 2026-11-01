import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Have I Been Pwned. Hesap sorgusu yalnızca sahipliği kanıtlanmış adreslere
/// uygulama tarafından yapılır; şifre kontrolü k-anonimlik kullanır.

class HibpException implements Exception {
  HibpException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef HttpGet = Future<({int status, String body, Map<String, String> headers})> Function(
    Uri uri, Map<String, String> headers);

Future<({int status, String body, Map<String, String> headers})> defaultHttpGet(
    Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(uri);
    headers.forEach(req.headers.set);
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final body = await resp.transform(utf8.decoder).join();
    return (
      status: resp.statusCode,
      body: body,
      headers: {'retry-after': resp.headers.value('retry-after') ?? ''},
    );
  } finally {
    client.close();
  }
}

class Breach {
  Breach({
    required this.name,
    required this.title,
    required this.domain,
    required this.breachDate,
    required this.dataClasses,
    required this.account,
  });

  final String name;
  final String title;
  final String domain;
  final String breachDate;
  final List<String> dataClasses;
  final String account;

  Map<String, Object> toJson() => {
        'name': name,
        'title': title,
        'domain': domain,
        'breach_date': breachDate,
        'data_classes': dataClasses,
        'account': account,
      };
}

class HibpClient {
  HibpClient({this.get = defaultHttpGet, this.sleep = _sleep});

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  final HttpGet get;
  final Future<void> Function(Duration) sleep;

  static const _ua = 'ayakizi-personal-footprint-audit';

  Future<String> _get(Uri uri, Map<String, String> headers) async {
    for (var attempt = 0; attempt <= 3; attempt++) {
      final r = await get(uri, {'user-agent': _ua, ...headers});
      if (r.status == 200) return r.body;
      if (r.status == 404) return '';
      if (r.status == 401) throw HibpException('HIBP API anahtarı geçersiz (401).');
      if (r.status == 429 && attempt < 3) {
        final wait = double.tryParse(r.headers['retry-after'] ?? '') ?? 2;
        await sleep(Duration(milliseconds: (wait.clamp(1, 30) * 1000).round()));
        continue;
      }
      throw HibpException('HIBP hatası: HTTP ${r.status}');
    }
    throw HibpException('HIBP: çok fazla istek (429).');
  }

  Future<List<Breach>> breachedAccount(String email, String apiKey) async {
    final uri = Uri.parse('https://haveibeenpwned.com/api/v3/breachedaccount/'
        '${Uri.encodeComponent(email)}?truncateResponse=false');
    final body = await _get(uri, {'hibp-api-key': apiKey});
    if (body.isEmpty) return [];
    final list = jsonDecode(body) as List;
    return [
      for (final b in list.cast<Map>())
        Breach(
          name: '${b['Name'] ?? ''}',
          title: '${b['Title'] ?? b['Name'] ?? ''}',
          domain: '${b['Domain'] ?? ''}',
          breachDate: '${b['BreachDate'] ?? ''}',
          dataClasses: [for (final d in (b['DataClasses'] as List? ?? const [])) '$d'],
          account: email,
        ),
    ];
  }

  Future<int> pwnedPasswordCount(String password) async {
    final digest = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    final body = await _get(
        Uri.parse('https://api.pwnedpasswords.com/range/${digest.substring(0, 5)}'),
        {'add-padding': 'true'});
    return parseRangeResponse(body, digest.substring(5));
  }
}

int parseRangeResponse(String text, String suffix) {
  for (final line in const LineSplitter().convert(text)) {
    final parts = line.trim().split(':');
    if (parts.length == 2 && parts[0].toUpperCase() == suffix) {
      return int.tryParse(parts[1]) ?? 0;
    }
  }
  return 0;
}
