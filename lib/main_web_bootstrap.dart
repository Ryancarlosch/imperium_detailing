import 'package:flutter_web_plugins/url_strategy.dart';

import 'main_web.dart' as imperium_web;

Future<void> main() async {
  usePathUrlStrategy();
  await imperium_web.main();
}
