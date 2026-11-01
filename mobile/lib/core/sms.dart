import 'dart:io';

import 'package:flutter/services.dart';

import 'classify.dart';
import 'models.dart';

/// Bu telefonun gelen kutusundaki SMS'leri okur (yalnızca Android).
/// Telefonun kendisi elinizde olduğu için numara sahipliği zaten kanıtlıdır.

class SmsMessage {
  SmsMessage(this.address, this.body, this.date);
  final String address;
  final String body;
  final DateTime? date;
}

class SmsSource {
  static const _channel = MethodChannel('ayakizi/sms');

  static bool get supported => Platform.isAndroid;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<List<SmsMessage>> readInbox({DateTime? since}) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
          'readInbox',
          {'sinceMillis': since?.millisecondsSinceEpoch ?? 0},
        ) ??
        const [];
    return [
      for (final m in list)
        SmsMessage(
          (m['address'] as String?) ?? '',
          (m['body'] as String?) ?? '',
          (m['date'] as num?) == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt(), isUtc: true),
        ),
    ];
  }
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
