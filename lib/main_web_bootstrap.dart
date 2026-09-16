import 'package:flutter_web_plugins/url_strategy.dart';

import 'main_web.dart' as imperium_web;

// O Web usa o mesmo fluxo de autenticação e empresa do aplicativo móvel.
Future<void> main() async {
  usePathUrlStrategy();
  await imperium_web.main();
}
