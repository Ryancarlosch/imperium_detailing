import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:imperium_detailing/screens/login_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ImperiumApp());
}

class ImperiumApp extends StatelessWidget {
  const ImperiumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Imperium Detailing',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
