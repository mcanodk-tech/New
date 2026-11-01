import 'dart:convert';

/// E-posta başlıklarını (From / Subject / Date) çözümler.
class ParsedHeaders {
  ParsedHeaders(this.from, this.subject, this.date);
  final String from;
  final String subject;
  final DateTime? date;

  String get domain => from.contains('@') ? from.substring(from.lastIndexOf('@') + 1) : '';
}

ParsedHeaders parseHeaders(List<int> raw) {
  final text = latin1.decode(raw, allowInvalid: true).replaceAll(RegExp(r'\r?\n[ \t]+'), ' ');
  final fields = <String, String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final name = line.substring(0, i).trim().toLowerCase();
    fields.putIfAbsent(name, () => line.substring(i + 1).trim());
  }
  final from = extractAddress(decodeHeaderValue(fields['from'] ?? ''));
  final subject = decodeHeaderValue(fields['subject'] ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return ParsedHeaders(from, subject, parseRfc2822Date(fields['date'] ?? ''));
}

String extractAddress(String value) {
  final angle = RegExp(r'<([^<>\s]+@[^<>\s]+)>').firstMatch(value);
  if (angle != null) return angle.group(1)!.toLowerCase();
  final bare = RegExp(r'[^\s<>"(),;:]+@[^\s<>"(),;:]+').firstMatch(value);
  return bare?.group(0)?.toLowerCase() ?? '';
}

/// RFC 2047 kodlu sözcükleri (=?utf-8?B?...?=) ve 8-bit ham UTF-8'i çözer.
String decodeHeaderValue(String latin1Value) {
  // Ham 8-bit başlıklar çoğunlukla UTF-8'dir.
  var value = latin1Value;
  if (value.codeUnits.any((c) => c > 127)) {
    try {
      value = utf8.decode(latin1.encode(value));
    } on FormatException {
      value = _decodeCharset('windows-1254', latin1.encode(latin1Value));
    }
  }
  value = value.replaceAllMapped(RegExp(r'(\?=)\s+(=\?)'), (m) => '${m[1]}${m[2]}');
  return value.replaceAllMapped(RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?='), (m) {
    final charset = m[1]!.split('*').first.toLowerCase();
    final enc = m[2]!.toUpperCase();
    final payload = m[3]!;
    try {
      final bytes = enc == 'B' ? _b64(payload) : _qDecode(payload);
      return _decodeCharset(charset, bytes);
    } catch (_) {
      return m[0]!;
    }
  });
}

List<int> _b64(String s) {
  var t = s.replaceAll(RegExp(r'\s'), '');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

List<int> _qDecode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '_') {
      out.add(0x20);
    } else if (c == '=' && i + 2 < s.length) {
      final hex = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
      if (hex != null) {
        out.add(hex);
        i += 2;
      } else {
        out.add(c.codeUnitAt(0));
      }
    } else {
      out.addAll(utf8.encode(c));
    }
  }
  return out;
}

// ISO-8859-9 / Windows-1254: Latin-1'den farklı olan Türkçe karakterler.
const Map<int, String> _turkishOverrides = {
  0xD0: 'Ğ', 0xDD: 'İ', 0xDE: 'Ş', 0xF0: 'ğ', 0xFD: 'ı', 0xFE: 'ş',
};

String _decodeCharset(String charset, List<int> bytes) {
  switch (charset) {
    case 'utf-8':
    case 'utf8':
      return utf8.decode(bytes, allowMalformed: true);
    case 'iso-8859-9':
    case 'windows-1254':
    case 'cp1254':
    case 'latin5':
      return String.fromCharCodes(bytes.map((b) => (_turkishOverrides[b] ?? String.fromCharCode(b)).codeUnitAt(0)));
    case 'iso-8859-1':
    case 'us-ascii':
    case 'latin1':
    case 'windows-1252':
      return latin1.decode(bytes, allowInvalid: true);
    default:
      return utf8.decode(bytes, allowMalformed: true);
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};
const _zones = {
  'ut': 0, 'utc': 0, 'gmt': 0, 'z': 0, 'est': -5, 'edt': -4, 'cst': -6, 'cdt': -5,
  'mst': -7, 'mdt': -6, 'pst': -8, 'pdt': -7,
};

DateTime? parseRfc2822Date(String s) {
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,5})?',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months[m[2]!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m[3]!);
  if (year < 100) year += year < 50 ? 2000 : 1900;
  var dt = DateTime.utc(year, month, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!),
      int.parse(m[6] ?? '0'));
  final zone = m[7];
  if (zone != null) {
    if (zone.startsWith('+') || zone.startsWith('-')) {
      final sign = zone.startsWith('-') ? -1 : 1;
      final minutes = int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5));
      dt = dt.subtract(Duration(minutes: sign * minutes));
    } else {
      dt = dt.subtract(Duration(hours: _zones[zone.toLowerCase()] ?? 0));
    }
  }
  return dt;
}

/// SMTP için RFC 2822 tarih biçimi (UTC).
String formatRfc2822Date(DateTime t) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[u.weekday - 1]}, ${two(u.day)} ${months[u.month - 1]} ${u.year} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
}
