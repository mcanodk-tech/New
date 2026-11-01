import 'package:ayakizi/app_state.dart';
import 'package:ayakizi/core/sms.dart';
import 'package:ayakizi/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first launch shows consent, then home', (tester) async {
    final state = AppState(store: MemoryKeyValueStore());
    await state.load();
    await tester.pumpWidget(AyakiziApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Anladım, devam et'), findsOneWidget);
    await tester.tap(find.text('Anladım, devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Taramayı başlat'), findsOneWidget);
    expect(find.text('Henüz adres eklenmedi.'), findsOneWidget);
    expect(state.consented, isTrue);

    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta adresi ekle'), findsOneWidget);
  });

  test('settings persist through the store; SMS backups do not', () async {
    final store = MemoryKeyValueStore();
    final a = AppState(
      store: store,
      smsPicker: (phone) async => SmsBackup(
        phone: phone,
        fileName: 'y.xml',
        messages: [SmsMessage('TINDER', 'Your Tinder code is 123456', DateTime.utc(2020))],
      ),
    );
    await a.load();
    await a.acceptConsent();
    await a.setHibpKey(' key ');
    expect(await a.importSms('abc'), isNotNull); // geçersiz numara
    expect(await a.importSms('+90 555 000 0000'), isNull);
    expect(a.smsBackups.single.phone, '+905550000000');
    expect(a.hasAnySource, isTrue);

    final b = AppState(store: store);
    await b.load();
    expect(b.hibpKey, 'key');
    expect(b.consented, isTrue);
    expect(b.smsBackups, isEmpty);
    await b.wipeAll();
    expect(store.data, isEmpty);
  });

  test('import surfaces parse errors', () async {
    final a = AppState(
      store: MemoryKeyValueStore(),
      smsPicker: (phone) async => throw SmsBackupException('bozuk'),
    );
    expect(await a.importSms('+905550000000'), 'bozuk');
  });
}
