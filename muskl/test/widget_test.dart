import 'package:flutter_test/flutter_test.dart';

import 'package:muskl/main.dart';

void main() {
  testWidgets('MUSKL app opens on its splash screen', (tester) async {
    await tester.pumpWidget(const MusklApp());

    expect(find.text('MUSKL'), findsOneWidget);
    expect(find.text('ENTRENA · REGISTRA · SUPERA'), findsOneWidget);
  });
}
