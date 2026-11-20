import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home_tiva/main.dart';

void main() {
  testWidgets('SmartHomeApp builds cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartHomeApp());
    expect(find.text('Connect to Device'), findsOneWidget);
  });
}