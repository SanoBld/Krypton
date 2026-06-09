// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:krypton/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const KryptonApp());
    expect(find.byType(KryptonApp), findsOneWidget);
  });
}