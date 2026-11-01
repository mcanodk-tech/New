import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

import 'classify.dart';
import 'models.dart';

/// Kullanıcının kendi seçtiği SMS yedeği dosyasını içe aktarır.
///
/// Uygulama telefonun SMS'lerine doğrudan erişmez (READ_SMS izni yoktur);
/// kullanıcı Android'de "SMS Backup & Restore" ile aldığı XML yedeğini dosya
/// seçiciyle verir. Dosya yalnızca bellekte işlenir, kopyalanmaz.

class SmsMessage {
  SmsMessage(this.address, this.body, this.date);
  final String address;
  final String body;
  final DateTime? date;
}

class SmsBackup {
  SmsBackup({required this.phone, required this.fileName, required this.messages});
  final String phone;
  final String fileName;
  final List<SmsMessage> messages;
}

class SmsBackupException implements Exception {
  SmsBackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

const String _received = '1';

/// "SMS Backup & Restore" XML biçimini akış halinde çözer; yalnızca gelen
/// (type="1") mesajları döndürür.
Future<List<SmsMessage>> parseSmsBackup(Stream<String> xmlText) async {
  final out = <SmsMessage>[];
  var sawRoot = false;
  try {
    await for (final events in xmlText.toXmlEvents()) {
      for (final e in events) {
        if (e is! XmlStartElementEvent) continue;
        if (e.name == 'smses') sawRoot = true;
        if (e.name != 'sms') continue;
        final a = {for (final attr in e.attributes) attr.name: attr.value};
        if ((a['type'] ?? _received) != _received) continue;
        final ms = int.tryParse(a['date'] ?? '');
        out.add(SmsMessage(
          a['address'] ?? '',
          a['body'] ?? '',
          ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        ));
      }
    }
  } on FormatException catch (e) {
    throw SmsBackupException('Dosya okunamadı: ${e.message}');
  } on XmlException catch (e) {
    throw SmsBackupException('Geçerli bir SMS yedeği değil (${e.message}).');
  }
  if (!sawRoot) {
    throw SmsBackupException(
        'Bu dosya "SMS Backup & Restore" yedeği gibi görünmüyor (<smses> bulunamadı).');
  }
  return out;
}

/// Dosya seçiciyi açar; kullanıcı vazgeçerse null döner.
Future<SmsBackup?> pickSmsBackup(String phone) async {
  final file = await FilePicker.pickFile(dialogTitle: 'SMS yedeğini seçin (.xml)');
  if (file == null) return null;
  if (!(file.name.toLowerCase().endsWith('.xml'))) {
    throw SmsBackupException('Lütfen .xml uzantılı SMS yedeğini seçin.');
  }
  final messages = await parseSmsBackup(
    file.readAsByteStream().cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)),
  );
  return SmsBackup(phone: phone, fileName: file.name, messages: messages);
}

final RegExp _code = RegExp(r'\b\d{4,8}\b');

/// SMS'leri hesap olaylarına çevirir. Hesapla ilgisiz kişisel mesajlar atılır,
/// doğrulama kodları maskelenir.
List<AccountEvent> smsToEvents(List<SmsMessage> messages, String phone) {
  final out = <AccountEvent>[];
  for (final m in messages) {
    final body = m.body.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
    final svc = resolveSmsService(m.address, body);
    final type = classify(body);
    if (!svc.known && type == EventType.other) continue;
    final masked = body.replaceAll(_code, '••••');
    out.add(AccountEvent(
      source: 'sms',
      account: phone,
      sender: m.address,
      subject: masked.length > 160 ? masked.substring(0, 160) : masked,
      date: m.date,
      type: type,
      service: svc.service,
      category: svc.category,
      known: svc.known,
    ));
  }
  return out;
}
