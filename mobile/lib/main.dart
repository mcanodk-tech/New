import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.load();
  runApp(AyakiziApp(state: state));
}

class AyakiziApp extends StatelessWidget {
  const AyakiziApp({super.key, required this.state});

  final AppState state;

  static const seed = Color(0xFF3B5BDB);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ayakizi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: HomePage(state: state),
    );
  }
}
