import 'package:ayakizi/app_state.dart';
import 'package:ayakizi/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen renders and add-email sheet opens', (tester) async {
    final state = AppState(store: MemoryKeyValueStore());
    await state.load();
    await tester.pumpWidget(AyakiziApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Taramayı başlat'), findsOneWidget);
    expect(find.text('Henüz adres eklenmedi.'), findsOneWidget);

    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta adresi ekle'), findsOneWidget);
  });

  test('settings persist through the store', () async {
    final store = MemoryKeyValueStore();
    final a = AppState(store: store);
    await a.load();
    await a.setHibpKey(' key ');
    await a.setSms(label: '+905550000000');
    final b = AppState(store: store);
    await b.load();
    expect(b.hibpKey, 'key');
    expect(b.phoneLabel, '+905550000000');
    await b.wipeAll();
    expect(store.data, isEmpty);
  });
}
