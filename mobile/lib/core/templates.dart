String kvkkTemplate(String service, String identity) => '''Konu: KVKK md. 11 kapsamında kişisel verilerimin silinmesi talebi

Sayın $service Veri Sorumlusu,

6698 sayılı Kişisel Verilerin Korunması Kanunu'nun 7. ve 11. maddeleri
uyarınca, $identity hesabı/iletişim bilgisi ile ilişkili tüm kişisel
verilerimin silinmesini veya yok edilmesini, varsa hesabımın kalıcı olarak
kapatılmasını ve verilerimin aktarıldığı üçüncü kişilere bu işlemin
bildirilmesini talep ediyorum.

Kanun'un 13. maddesi uyarınca talebimin en geç otuz gün içinde
sonuçlandırılmasını rica ederim.

Ad Soyad:
Tarih:
''';

String gdprTemplate(String service, String identity) => '''Subject: Erasure request under Article 17 GDPR

Dear $service Data Protection Officer,

Under Article 17 of the General Data Protection Regulation, I request the
erasure of all personal data you hold relating to $identity, the closure of
any associated account, and notification of this erasure to any recipients
under Article 19.

Please confirm completion within one month as required by Article 12(3).

Name:
Date:
''';
