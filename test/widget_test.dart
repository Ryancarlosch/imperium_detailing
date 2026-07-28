import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/main.dart';

void main() {
  testWidgets('Aplicativo inicia', (WidgetTester tester) async {
    await tester.pumpWidget(const ImperiumApp());

    expect(find.byType(ImperiumApp), findsOneWidget);
  });
}