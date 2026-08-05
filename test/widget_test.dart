import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clipper_mobile/core/providers/theme_provider.dart';
import 'package:clipper_mobile/main.dart';

void main() {
  testWidgets('ClipperApp loads import screen smoke test', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const ClipperApp(),
      ),
    );

    expect(find.text('Clipper Mobile'), findsWidgets);
  });
}
